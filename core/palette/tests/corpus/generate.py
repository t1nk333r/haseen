#!/usr/bin/env python3
"""Generate the palette corpus: small synthetic images, one per decoder path.

    python3 core/palette/tests/corpus/generate.py [OUTDIR]

Every picture is drawn here from arithmetic; none is a photograph. PNG and GIF
are written by hand below so every colour type, bit depth, filter, interlace,
transparency and frame offset that Go's decoders treat differently is present;
JPEG and WebP come from Pillow (libjpeg, libwebp), which is the only
dependency. The committed files are the corpus: tests compare against them and
against the Go generator's answers recorded for them (../golden/), so running
this again with another Pillow may write different JPEG and WebP bytes, and
the goldens would then have to be recorded again with the Go generator, which
is gone (plan 167). Run it only to add a picture.
"""

import colorsys
import io
import os
import struct
import sys
import zlib

from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))


# --- scenes: (x, y, w, h) -> (r, g, b) in 0..255 ------------------------------


def lcg(seed):
    state = seed & 0xFFFFFFFF
    while True:
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        yield state


def hsl(h, s, l):
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360, l, s)
    return (round(r * 255), round(g * 255), round(b * 255))


def sunset(x, y, w, h):
    t = y / max(1, h - 1)
    sky = hsl(280 - 250 * t, 0.55, 0.18 + 0.45 * t)
    cx, cy, r = w * 0.62, h * 0.58, min(w, h) * 0.18
    if (x - cx) ** 2 + (y - cy) ** 2 < r * r:
        return hsl(40, 0.95, 0.62)
    if y > h * 0.78:
        return hsl(220, 0.35, 0.10 + 0.05 * ((x // 7) % 2))
    return sky


def bands(colors):
    def scene(x, y, w, h):
        return colors[min(y * len(colors) // h, len(colors) - 1)]

    return scene


def forest(x, y, w, h):
    v = ((x * 37 + y * 91) ^ (x * y)) % 23
    base = hsl(95 + v * 3 + (y * 40) // max(1, h), 0.45, 0.16 + v / 80)
    if (x // 9 + y // 13) % 11 == 0:
        return hsl(15, 0.7, 0.45)  # a few red mushrooms
    return base


def mono(hue):
    def scene(x, y, w, h):
        l = 0.08 + 0.8 * ((x + 2 * y) % (w + h)) / (w + h)
        return hsl(hue, 0.12, l)

    return scene


def gray(x, y, w, h):
    v = (x * 255) // max(1, w - 1)
    if (x // 8 + y // 8) % 2 and y < h // 2:
        v = 255 - v
    return (v, v, v)


def pastel(x, y, w, h):
    return hsl(x * 360 / w + y, 0.45, 0.78 + 0.1 * ((y // 5) % 2))


def neon(x, y, w, h):
    if (x + y) % 17 < 2:
        return hsl((x * 7) % 360, 1.0, 0.55)
    if abs(y - h // 2) < 2:
        return (255, 40, 200)
    return hsl(250, 0.6, 0.06 + 0.04 * (x % 3))


def checker(x, y, w, h):
    hue = ((x // 3) * 47 + (y // 3) * 89) % 360
    return hsl(hue, 0.8, 0.35 + 0.3 * ((x + y) % 2))


def pixels(scene, w, h):
    return [[scene(x, y, w, h) for x in range(w)] for y in range(h)]


# --- PNG, by hand ---------------------------------------------------------------


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def filter_rows(rows, bpp):
    """Each row gets filter (row index % 5): all five types are decoded."""
    out = b""
    prev = bytes(len(rows[0])) if rows else b""
    for i, row in enumerate(rows):
        ft = i % 5
        f = bytearray()
        for j, v in enumerate(row):
            a = row[j - bpp] if j >= bpp else 0
            b = prev[j]
            c = prev[j - bpp] if j >= bpp else 0
            pred = [0, a, b, (a + b) // 2, paeth(a, b, c)][ft]
            f.append((v - pred) & 0xFF)
        out += bytes([ft]) + bytes(f)
        prev = row
    return out


def pack(samples, depth):
    """Samples of one row at a bit depth, as bytes."""
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b"".join(struct.pack(">H", s) for s in samples)
    out, acc, n = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | s
        n += depth
        if n == 8:
            out.append(acc)
            acc, n = 0, 0
    if n:
        out.append(acc << (8 - n))
    return bytes(out)


ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def write_png(path, w, h, ctype, depth, sample_rows, plte=None, trns=None, interlace=False):
    """sample_rows[y][x] is a tuple of samples for that pixel."""
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = max(1, channels * depth // 8)
    data = b""
    passes = ADAM7 if interlace else [(0, 0, 1, 1)]
    for x0, y0, dx, dy in passes:
        rows = []
        for y in range(y0, h, dy):
            samples = [s for x in range(x0, w, dx) for s in sample_rows[y][x]]
            if samples:
                rows.append(pack(samples, depth))
        if rows:
            data += filter_rows(rows, bpp)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, int(interlace)))
    if plte:
        png += chunk(b"PLTE", b"".join(bytes(c) for c in plte))
    if trns is not None:
        png += chunk(b"tRNS", trns)
    png += chunk(b"IDAT", zlib.compress(data, 9)) + chunk(b"IEND", b"")
    open(os.path.join(OUT, path), "wb").write(png)


def quantize(rgb_rows, palette):
    def nearest(c):
        return min(range(len(palette)), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, palette[i])))

    return [[(nearest(c),) for c in row] for row in rgb_rows]


# --- GIF, by hand ---------------------------------------------------------------


def lzw_literal(indices, min_size):
    """LZW codes that are all literals, with a clear code often enough that the
    code width never grows: valid for every decoder, and trivial to write."""
    clear, end = 1 << min_size, (1 << min_size) + 1
    width = min_size + 1
    per_clear = (1 << min_size) - 2
    codes = []
    for i, v in enumerate(indices):
        if i % per_clear == 0:
            codes.append(clear)
        codes.append(v)
    codes.append(end)
    out, acc, n = bytearray(), 0, 0
    for c in codes:
        acc |= c << n
        n += width
        while n >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            n -= 8
    if n:
        out.append(acc & 0xFF)
    blocks = b"".join(bytes([len(out[i : i + 255])]) + bytes(out[i : i + 255]) for i in range(0, len(out), 255))
    return bytes([min_size]) + blocks + b"\x00"


def color_table(palette):
    size = 2
    while size < len(palette):
        size *= 2
    table = list(palette) + [(0, 0, 0)] * (size - len(palette))
    return b"".join(bytes(c) for c in table), size.bit_length() - 2


def gif_frame(left, top, w, h, idx_rows, palette=None, interlace=False, transparent=None):
    out = b""
    if transparent is not None:
        out += b"\x21\xf9\x04" + bytes([1, 0, 0, transparent, 0])
    flags = 0
    lct = b""
    if palette:
        lct, bits = color_table(palette)
        flags |= 0x80 | bits
    if interlace:
        flags |= 0x40
        order = list(range(0, h, 8)) + list(range(4, h, 8)) + list(range(2, h, 4)) + list(range(1, h, 2))
    else:
        order = list(range(h))
    out += b"\x2c" + struct.pack("<HHHHB", left, top, w, h, flags) + lct
    flat = [idx_rows[y][x] for y in order for x in range(w)]
    ncolors = len(palette) if palette else 256
    out += lzw_literal(flat, max(2, (ncolors - 1).bit_length()))
    return out


def write_gif(path, sw, sh, frames, global_palette=None, background=0):
    flags = 0
    gct = b""
    if global_palette:
        gct, bits = color_table(global_palette)
        flags = 0x80 | 0x70 | bits
    data = b"GIF89a" + struct.pack("<HHBBB", sw, sh, flags, background, 0) + gct
    data += b"".join(frames) + b"\x3b"
    open(os.path.join(OUT, path), "wb").write(data)


# --- the corpus -----------------------------------------------------------------


def rgb_rows(scene, w, h):
    return pixels(scene, w, h)


def pillow_gif(path, w, h, idx_rows, palette):
    """A paletted picture through Pillow's GIF writer, which compresses."""
    im = Image.new("P", (w, h))
    im.putpalette([v for c in palette for v in c])
    im.putdata([p[0] for row in idx_rows for p in row])
    im.save(os.path.join(OUT, path), optimize=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    warm = bands([(18, 22, 40), (190, 80, 70), (60, 140, 120), (230, 210, 150), (90, 60, 140)])

    # PNG: every type Go's decoder returns (Gray, Gray16, RGBA, RGBA64, NRGBA,
    # NRGBA64, Paletted), filters 0-4 on every row cycle, Adam7, tRNS.
    w, h = 120, 90
    write_png("png-rgb8.png", w, h, 2, 8, rgb_rows(sunset, w, h))
    w, h = 1000, 260  # wider than 400: the scaler shrinks
    write_png("png-rgb8-wide.png", w, h, 2, 8, rgb_rows(warm, w, h))
    w, h = 96, 80
    rows = [[c + ((0 if (x // 12 + y // 12) % 3 == 0 else 255),) for x, c in enumerate(row)] for y, row in enumerate(rgb_rows(sunset, w, h))]
    write_png("png-rgba8-holes.png", w, h, 6, 8, rows)
    w, h = 130, 90
    write_png("png-gray8.png", w, h, 0, 8, [[(c[0],) for c in row] for row in rgb_rows(gray, w, h)])
    w, h = 100, 100
    write_png("png-gray2.png", w, h, 0, 2, [[(c[0] >> 6,) for c in row] for row in rgb_rows(gray, w, h)])
    w, h = 64, 48
    write_png("png-gray16.png", w, h, 0, 16, [[(min(65535, c[0] * 257 + (x * 13) % 200),) for x, c in enumerate(row)] for row in rgb_rows(mono(30), w, h)])
    w, h = 40, 56  # taller than wide
    write_png("png-rgb16.png", w, h, 2, 16, [[tuple(v * 257 ^ (x * 31 % 256) for v in c) for x, c in enumerate(row)] for row in rgb_rows(pastel, w, h)])
    w, h = 40, 40
    write_png("png-rgba16.png", w, h, 6, 16, [[tuple(v * 257 for v in c) + (65535 - (x * y * 40) % 30000,) for x, c in enumerate(row)] for y, row in enumerate(rgb_rows(neon, w, h))])
    w, h = 72, 64
    write_png("png-graya8.png", w, h, 4, 8, [[(c[0], 255 if x < 60 else 40) for x, c in enumerate(row)] for row in rgb_rows(mono(200), w, h)])
    w, h = 80, 60
    write_png("png-rgb8-trns.png", w, h, 2, 8, rgb_rows(warm, w, h), trns=struct.pack(">HHH", 190, 80, 70))
    w, h = 77, 53  # odd sizes through every Adam7 pass
    write_png("png-rgb8-adam7.png", w, h, 2, 8, rgb_rows(checker, w, h), interlace=True)
    pal = [hsl(i * 11, 0.6, 0.15 + (i % 8) * 0.09) for i in range(32)]
    w, h = 700, 60
    write_png("png-pal8.png", w, h, 3, 8, quantize(rgb_rows(sunset, w, h), pal), plte=pal)
    pal = [hsl(i * 40, 0.5, 0.3 + (i % 3) * 0.2) for i in range(12)]
    w, h = 90, 90
    trns = bytes([0, 255, 255, 128] + [255] * 4)  # shorter than the palette
    write_png("png-pal4-trns.png", w, h, 3, 4, quantize(rgb_rows(pastel, w, h), pal), plte=pal, trns=trns)

    # GIF: a global table, then a local table, an interlaced frame at an
    # offset inside a larger screen with a transparent index, and a second
    # frame the decoder must not read.
    pal = [hsl(i * 9, 0.55, 0.1 + (i % 10) * 0.08) for i in range(40)]
    w, h = 120, 80
    pillow_gif("gif-global.gif", w, h, quantize(rgb_rows(sunset, w, h), pal), pal)
    pal2 = [hsl(100 + i * 5, 0.5, 0.1 + i * 0.05) for i in range(16)]
    fw, fh = 60, 50
    idx = [[p[0] for p in row] for row in quantize(rgb_rows(forest, fw, fh), pal2)]
    for y in range(fh):
        for x in range(fw):
            if (x + y) % 9 == 0:
                idx[y][x] = 3
    second = gif_frame(0, 0, 10, 10, [[0] * 10 for _ in range(10)], palette=[(255, 0, 0), (0, 0, 255)])
    write_gif("gif-offset-local.gif", 100, 100, [gif_frame(10, 20, fw, fh, idx, palette=pal2, interlace=True, transparent=3), second], global_palette=[(0, 0, 0), (255, 255, 255)])
    pal = [hsl(i * 23, 0.8, 0.2 + (i % 5) * 0.12) for i in range(64)]
    w, h = 640, 120
    pillow_gif("gif-wide.gif", w, h, quantize(rgb_rows(neon, w, h), pal), pal)

    def img(scene, w, h, mode="RGB"):
        im = Image.new("RGB", (w, h))
        im.putdata([c for row in rgb_rows(scene, w, h) for c in row])
        return im.convert(mode)

    # JPEG: 4:2:0, 4:2:2, 4:4:4, grayscale, progressive, restart markers,
    # Adobe CMYK, odd sizes that end inside an MCU.
    img(sunset, 160, 120).save(os.path.join(OUT, "jpg-420.jpg"), quality=80, subsampling=2)
    img(forest, 120, 90).save(os.path.join(OUT, "jpg-422.jpg"), quality=80, subsampling=1)
    img(checker, 73, 45).save(os.path.join(OUT, "jpg-444-odd.jpg"), quality=85, subsampling=0)
    img(gray, 100, 100, "L").save(os.path.join(OUT, "jpg-gray.jpg"), quality=80)
    img(pastel, 480, 270).save(os.path.join(OUT, "jpg-progressive.jpg"), quality=40, subsampling=2, progressive=True)
    img(neon, 83, 75).save(os.path.join(OUT, "jpg-restart.jpg"), quality=80, subsampling=2, restart_marker_blocks=3)
    img(mono(25), 80, 80, "CMYK").save(os.path.join(OUT, "jpg-cmyk.jpg"), quality=85)

    # WebP: lossy (VP8, YCbCr 4:2:0), lossless (VP8L, NRGBA) with few and
    # many colours, and both with alpha (VP8X: NYCbCrA, NRGBA).
    img(sunset, 160, 100).save(os.path.join(OUT, "webp-lossy.webp"), quality=70, method=6)
    img(sunset, 600, 340).save(os.path.join(OUT, "webp-lossy-wide.webp"), quality=30, method=6)
    img(checker, 81, 67).save(os.path.join(OUT, "webp-lossless.webp"), lossless=True, quality=100, method=6)
    img(warm, 120, 90).save(os.path.join(OUT, "webp-lossless-few.webp"), lossless=True, quality=100, method=6)
    a = img(neon, 100, 100).convert("RGBA")
    a.putalpha(Image.linear_gradient("L").resize((100, 100)))
    a.save(os.path.join(OUT, "webp-lossy-alpha.webp"), quality=75, method=6)
    a = img(pastel, 80, 60).convert("RGBA")
    a.putalpha(Image.radial_gradient("L").resize((80, 60)).point(lambda v: 255 - v))
    a.save(os.path.join(OUT, "webp-lossless-alpha.webp"), lossless=True, quality=100, method=6)

    # Refused: one colour is not enough; a header that claims 30000 px a side
    # must fail before any pixel is read; a file that is not an image.
    w, h = 40, 40
    write_png("bad-one-colour.png", w, h, 2, 8, [[(40, 90, 160)] * w for _ in range(h)])
    huge = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 30000, 10, 8, 2, 0, 0, 0)) + chunk(b"IEND", b"")
    open(os.path.join(OUT, "bad-huge-header.png"), "wb").write(huge)
    open(os.path.join(OUT, "bad-not-an-image.png"), "wb").write(b"certainly not a png\n")


if __name__ == "__main__":
    main()
