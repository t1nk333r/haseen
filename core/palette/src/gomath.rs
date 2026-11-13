// Ported from Go (Copyright 2009 The Go Authors; BSD-3-Clause) and, through
// it, fdlibm (Copyright (C) 1993 Sun Microsystems); both notices are in
// core/palette/LICENSE-GO.
//! Go's `math` functions, ported so a palette is the one the Go generator
//! wrote, bit for bit, whatever C library this is linked against.
//!
//! It matters more than it looks: a grey pixel's OKLab `a` and `b` are
//! round-off residues of the cube root, their angle is the colour's hue, and
//! the scheme modes turn the most chromatic dominant colour's hue into the
//! whole palette. A libm `cbrt` or `pow` that differs in the last bit from
//! Go's moves those hues. Go computes these in pure Go on amd64 (no
//! assembly) except `Exp`, which is amd64 assembly from SLEEF, with an FMA
//! path on CPUs that have one; [`exp`] is that path, the one the Go releases
//! took on the machines the golden files were recorded on (plan 167). Go's
//! `Log` assembly agrees with its pure-Go `log` on every input tested
//! (5,000,000 random), so [`log`] is the pure-Go one. `Sqrt`, `Floor`,
//! `Trunc`, `Mod` and `Round` are exact in both languages and come from
//! Rust's `f64`. Rust never fuses `a * b + c`, and neither does Go on amd64,
//! so the arithmetic below is written in Go's order.

// Each function keeps Go's name for its constants and its order of
// operations, so the literals are Go's and are not rounded again.
#![allow(clippy::excessive_precision, clippy::approx_constant)]

use std::f64::consts::PI;

const MASK: u64 = 0x7FF;
const SHIFT: u32 = 64 - 11 - 1;
const BIAS: i64 = 1023;

fn normalize(x: f64) -> (f64, i64) {
    const SMALLEST_NORMAL: f64 = 2.2250738585072014e-308;
    if x.abs() < SMALLEST_NORMAL {
        return (x * (1u64 << 52) as f64, -52);
    }
    (x, 0)
}

/// Go's `math.Frexp`.
pub fn frexp(f: f64) -> (f64, i64) {
    if f == 0.0 || f.is_infinite() || f.is_nan() {
        return (f, 0);
    }
    let (f, mut exp) = normalize(f);
    let mut x = f.to_bits();
    exp += ((x >> SHIFT) & MASK) as i64 - BIAS + 1;
    x &= !(MASK << SHIFT);
    x |= ((-1 + BIAS) as u64) << SHIFT;
    (f64::from_bits(x), exp)
}

/// Go's `math.Ldexp`.
pub fn ldexp(frac: f64, exp: i64) -> f64 {
    if frac == 0.0 || frac.is_infinite() || frac.is_nan() {
        return frac;
    }
    let (frac, e) = normalize(frac);
    let mut exp = exp + e;
    let mut x = frac.to_bits();
    exp += ((x >> SHIFT) & MASK) as i64 - BIAS;
    if exp < -1075 {
        return 0.0_f64.copysign(frac);
    }
    if exp > 1023 {
        return if frac < 0.0 {
            f64::NEG_INFINITY
        } else {
            f64::INFINITY
        };
    }
    let mut m = 1.0;
    if exp < -1022 {
        exp += 53;
        m = 1.0 / (1u64 << 53) as f64;
    }
    x &= !(MASK << SHIFT);
    x |= ((exp + BIAS) as u64) << SHIFT;
    m * f64::from_bits(x)
}

/// Go's `math.Modf`.
pub fn modf(f: f64) -> (f64, f64) {
    let int = f.trunc();
    (int, (f - int).copysign(f))
}

// The Go code is a modified version of the original C code from
// http://www.netlib.org/fdlibm/s_cbrt.c and came with this notice.
//
// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunSoft, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
/// Go's `math.Cbrt` (FreeBSD's s_cbrt.c, as Go has it).
pub fn cbrt(x: f64) -> f64 {
    const B1: u64 = 715094163;
    const B2: u64 = 696219795;
    const C: f64 = 5.42857142857142815906e-01;
    const D: f64 = -7.05306122448979611050e-01;
    const E: f64 = 1.41428571428571436819e+00;
    const F: f64 = 1.60714285714285720630e+00;
    const G: f64 = 3.57142857142857150787e-01;
    const SMALLEST_NORMAL: f64 = 2.22507385850720138309e-308;
    if x == 0.0 || x.is_nan() || x.is_infinite() {
        return x;
    }
    let mut x = x;
    let sign = x < 0.0;
    if sign {
        x = -x;
    }
    let mut t = f64::from_bits(x.to_bits() / 3 + (B1 << 32));
    if x < SMALLEST_NORMAL {
        t = (1u64 << 54) as f64;
        t *= x;
        t = f64::from_bits(t.to_bits() / 3 + (B2 << 32));
    }
    let mut r = t * t / x;
    let mut s = C + r * t;
    t *= G + F / (s + E + D / s);
    t = f64::from_bits((t.to_bits() & (0xFFFFFFFFC << 28)) + (1 << 30));
    s = t * t;
    r = x / s;
    let w = t + t;
    r = (r - t) / (w + r);
    t = t + t * r;
    if sign {
        t = -t;
    }
    t
}

// Go's log follows FreeBSD's /usr/src/lib/msun/src/e_log.c, which came
// with this notice:
//
// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunPro, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
/// Go's `math.Log`.
pub fn log(x: f64) -> f64 {
    const LN2_HI: f64 = 6.93147180369123816490e-01;
    const LN2_LO: f64 = 1.90821492927058770002e-10;
    const L1: f64 = 6.666666666666735130e-01;
    const L2: f64 = 3.999999999940941908e-01;
    const L3: f64 = 2.857142874366239149e-01;
    const L4: f64 = 2.222219843214978396e-01;
    const L5: f64 = 1.818357216161805012e-01;
    const L6: f64 = 1.531383769920937332e-01;
    const L7: f64 = 1.479819860511658591e-01;
    if x.is_nan() || x == f64::INFINITY {
        return x;
    }
    if x < 0.0 {
        return f64::NAN;
    }
    if x == 0.0 {
        return f64::NEG_INFINITY;
    }
    let (mut f1, mut ki) = frexp(x);
    if f1 < std::f64::consts::SQRT_2 / 2.0 {
        f1 *= 2.0;
        ki -= 1;
    }
    let f = f1 - 1.0;
    let k = ki as f64;
    let s = f / (2.0 + f);
    let s2 = s * s;
    let s4 = s2 * s2;
    let t1 = s2 * (L1 + s4 * (L3 + s4 * (L5 + s4 * L7)));
    let t2 = s4 * (L2 + s4 * (L4 + s4 * L6));
    let r = t1 + t2;
    let hfsq = 0.5 * f * f;
    k * LN2_HI - ((hfsq - (s * (hfsq + r) + k * LN2_LO)) - f)
}

/// Go's `math.Exp` on amd64 with FMA: `exp_amd64.s`, its `avxfma` path.
/// CVTSD2SL rounds to nearest even; a value outside int32 becomes
/// 0x80000000, which `as i32` gives too (it saturates), and both then
/// underflow to 0.
pub fn exp(x: f64) -> f64 {
    const LOG2E: f64 = 1.4426950408889634073599246810018920;
    const LN2U: f64 = 0.69314718055966295651160180568695068359375;
    const LN2L: f64 = 0.28235290563031577122588448175013436025525412068e-12;
    const OVERFLOW: f64 = 7.09782712893384e+02;
    const T: [f64; 9] = [
        0.5,
        1.0,
        2.0,
        1.6666666666666666667e-1,
        4.1666666666666666667e-2,
        8.3333333333333333333e-3,
        1.3888888888888888889e-3,
        1.9841269841269841270e-4,
        2.4801587301587301587e-5,
    ];
    if !x.is_finite() {
        if x == f64::NEG_INFINITY {
            return 0.0;
        }
        return x; // NaN or +Inf
    }
    if x > OVERFLOW {
        return f64::INFINITY;
    }
    let mut bx = (LOG2E * x).round_ties_even() as i32;
    let k = bx as f64;
    let mut x0 = (-k).mul_add(LN2U, x);
    x0 = (-k).mul_add(LN2L, x0);
    x0 *= 0.0625;
    let mut x1 = T[8];
    x1 = x1.mul_add(x0, T[7]);
    x1 = x1.mul_add(x0, T[6]);
    x1 = x1.mul_add(x0, T[5]);
    x1 = x1.mul_add(x0, T[4]);
    x1 = x1.mul_add(x0, T[3]);
    x1 = x1.mul_add(x0, T[0]);
    x1 = x1.mul_add(x0, T[1]);
    x0 *= x1;
    x1 = x0 + T[2];
    x0 *= x1;
    x1 = x0 + T[2];
    x0 *= x1;
    x1 = x0 + T[2];
    x0 *= x1;
    x1 = x0 + T[2];
    x0 = x0.mul_add(x1, T[1]);
    // ldexp, as the assembly does it
    bx = bx.wrapping_add(0x3FF);
    if bx <= 0 {
        if bx < -52 {
            return 0.0;
        }
        bx += 0x3FE;
        x0 *= f64::from_bits(((bx as u32) as u64) << 52);
        bx = 1;
    } else if bx >= 0x7FF {
        return f64::INFINITY;
    }
    x0 * f64::from_bits(((bx as u32) as u64) << 52)
}

fn is_odd_int(x: f64) -> bool {
    if x.abs() >= (1u64 << 53) as f64 {
        return false;
    }
    let (xi, xf) = modf(x);
    xf == 0.0 && (xi as i64) & 1 == 1
}

/// Go's `math.Pow`.
pub fn pow(x: f64, y: f64) -> f64 {
    if y == 0.0 || x == 1.0 {
        return 1.0;
    }
    if y == 1.0 {
        return x;
    }
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    if x == 0.0 {
        if y < 0.0 {
            if x.is_sign_negative() && is_odd_int(y) {
                return f64::NEG_INFINITY;
            }
            return f64::INFINITY;
        }
        if y > 0.0 {
            if x.is_sign_negative() && is_odd_int(y) {
                return x;
            }
            return 0.0;
        }
    }
    if y.is_infinite() {
        if x == -1.0 {
            return 1.0;
        }
        if (x.abs() < 1.0) == (y == f64::INFINITY) {
            return 0.0;
        }
        return f64::INFINITY;
    }
    if x.is_infinite() {
        if x == f64::NEG_INFINITY {
            return pow(1.0 / x, -y);
        }
        if y < 0.0 {
            return 0.0;
        }
        if y > 0.0 {
            return f64::INFINITY;
        }
    }
    if y == 0.5 {
        return x.sqrt();
    }
    if y == -0.5 {
        return 1.0 / x.sqrt();
    }
    let (mut yi, mut yf) = modf(y.abs());
    if yf != 0.0 && x < 0.0 {
        return f64::NAN;
    }
    if yi >= 9.223372036854775808e18 {
        if x == -1.0 {
            return 1.0;
        }
        if (x.abs() < 1.0) == (y > 0.0) {
            return 0.0;
        }
        return f64::INFINITY;
    }
    let mut a1 = 1.0;
    let mut ae: i64 = 0;
    if yf != 0.0 {
        if yf > 0.5 {
            yf -= 1.0;
            yi += 1.0;
        }
        a1 = exp(yf * log(x));
    }
    let (mut x1, mut xe) = frexp(x);
    let mut i = yi as i64;
    while i != 0 {
        if !(-(1 << 12)..=(1 << 12)).contains(&xe) {
            ae += xe;
            break;
        }
        if i & 1 == 1 {
            a1 *= x1;
            ae += xe;
        }
        x1 *= x1;
        xe <<= 1;
        if x1 < 0.5 {
            x1 += x1;
            xe -= 1;
        }
        i >>= 1;
    }
    if y < 0.0 {
        a1 = 1.0 / a1;
        ae = -ae;
    }
    ldexp(a1, ae)
}

// Go took these from the Cephes library (sin.c, atan.c), with its notice:
//
// Cephes Math Library Release 2.8:  June, 2000
// Copyright 1984, 1987, 1989, 1992, 2000 by Stephen L. Moshier
//
// The readme file at http://netlib.sandia.gov/cephes/ says:
//    Some software in this archive may be from the book _Methods and
// Programs for Mathematical Functions_ (Prentice-Hall or Simon & Schuster
// International, 1989) or from the Cephes Mathematical Library, a
// commercial product. In either event, it is copyrighted by the author.
// What you see here may be used freely but it comes with no support or
// guarantee.
fn xatan(x: f64) -> f64 {
    const P0: f64 = -8.750608600031904122785e-01;
    const P1: f64 = -1.615753718733365076637e+01;
    const P2: f64 = -7.500855792314704667340e+01;
    const P3: f64 = -1.228866684490136173410e+02;
    const P4: f64 = -6.485021904942025371773e+01;
    const Q0: f64 = 2.485846490142306297962e+01;
    const Q1: f64 = 1.650270098316988542046e+02;
    const Q2: f64 = 4.328810604912902668951e+02;
    const Q3: f64 = 4.853903996359136964868e+02;
    const Q4: f64 = 1.945506571482613964425e+02;
    let mut z = x * x;
    z = z * ((((P0 * z + P1) * z + P2) * z + P3) * z + P4)
        / (((((z + Q0) * z + Q1) * z + Q2) * z + Q3) * z + Q4);
    x * z + x
}

fn satan(x: f64) -> f64 {
    const MOREBITS: f64 = 6.123233995736765886130e-17;
    const TAN3PIO8: f64 = 2.41421356237309504880;
    if x <= 0.66 {
        return xatan(x);
    }
    if x > TAN3PIO8 {
        return PI / 2.0 - xatan(1.0 / x) + MOREBITS;
    }
    PI / 4.0 + xatan((x - 1.0) / (x + 1.0)) + 0.5 * MOREBITS
}

/// Go's `math.Atan`.
pub fn atan(x: f64) -> f64 {
    if x == 0.0 {
        return x;
    }
    if x > 0.0 {
        return satan(x);
    }
    -satan(-x)
}

/// Go's `math.Atan2`.
pub fn atan2(y: f64, x: f64) -> f64 {
    if y.is_nan() || x.is_nan() {
        return f64::NAN;
    }
    if y == 0.0 {
        if x >= 0.0 && !x.is_sign_negative() {
            return 0.0_f64.copysign(y);
        }
        return PI.copysign(y);
    }
    if x == 0.0 {
        return (PI / 2.0).copysign(y);
    }
    if x.is_infinite() {
        if x == f64::INFINITY {
            if y.is_infinite() {
                return (PI / 4.0).copysign(y);
            }
            return 0.0_f64.copysign(y);
        }
        if y.is_infinite() {
            // Go's constant 3*Pi/4, rounded once.
            return 2.356194490192344928846982537459627163_f64.copysign(y);
        }
        return PI.copysign(y);
    }
    if y.is_infinite() {
        return (PI / 2.0).copysign(y);
    }
    let q = atan(y / x);
    if x < 0.0 {
        if q <= 0.0 {
            return q + PI;
        }
        return q - PI;
    }
    q
}

const SIN: [f64; 6] = [
    1.58962301576546568060e-10,
    -2.50507477628578072866e-8,
    2.75573136213857245213e-6,
    -1.98412698295895385996e-4,
    8.33333333332211858878e-3,
    -1.66666666666666307295e-1,
];
const COS: [f64; 6] = [
    -1.13585365213876817300e-11,
    2.08757008419747316778e-9,
    -2.75573141792967388112e-7,
    2.48015872888517045348e-5,
    -1.38888888888730564116e-3,
    4.16666666666665929218e-2,
];
const PI4A: f64 = 7.85398125648498535156e-1;
const PI4B: f64 = 3.77489470793079817668e-8;
const PI4C: f64 = 2.69515142907905952645e-15;
/// Go's constant 4/Pi, rounded once (the same bits as 4.0 / PI, checked by a
/// test).
const FOUR_OVER_PI: f64 = 1.273239544735162686151070106980114896;
/// Go switches to Payne-Hanek reduction from here. Every angle the palette
/// takes is a hue in radians, under 7, so that path is not ported.
const REDUCE_THRESHOLD: f64 = (1u64 << 29) as f64;

/// Cody-Waite reduction to an octant, as Go's `sin` and `cos` do it.
fn reduce(x: f64) -> (u64, f64) {
    assert!(
        x < REDUCE_THRESHOLD,
        "angle {x} needs Payne-Hanek reduction"
    );
    let mut j = (x * FOUR_OVER_PI) as u64;
    let mut y = j as f64;
    if j & 1 == 1 {
        j += 1;
        y += 1.0;
    }
    j &= 7;
    (j, ((x - y * PI4A) - y * PI4B) - y * PI4C)
}

fn sin_poly(z: f64, zz: f64) -> f64 {
    z + z
        * zz
        * ((((((SIN[0] * zz) + SIN[1]) * zz + SIN[2]) * zz + SIN[3]) * zz + SIN[4]) * zz + SIN[5])
}

fn cos_poly(zz: f64) -> f64 {
    1.0 - 0.5 * zz
        + zz * zz
            * ((((((COS[0] * zz) + COS[1]) * zz + COS[2]) * zz + COS[3]) * zz + COS[4]) * zz
                + COS[5])
}

/// Go's `math.Cos`.
pub fn cos(x: f64) -> f64 {
    if x.is_nan() || x.is_infinite() {
        return f64::NAN;
    }
    let mut sign = false;
    let (mut j, z) = reduce(x.abs());
    if j > 3 {
        j -= 4;
        sign = !sign;
    }
    if j > 1 {
        sign = !sign;
    }
    let zz = z * z;
    let y = if j == 1 || j == 2 {
        sin_poly(z, zz)
    } else {
        cos_poly(zz)
    };
    if sign {
        -y
    } else {
        y
    }
}

/// Go's `math.Sin`.
pub fn sin(x: f64) -> f64 {
    if x == 0.0 || x.is_nan() {
        return x;
    }
    if x.is_infinite() {
        return f64::NAN;
    }
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let (mut j, z) = reduce(x);
    if j > 3 {
        sign = !sign;
        j -= 4;
    }
    let zz = z * z;
    let y = if j == 1 || j == 2 {
        cos_poly(zz)
    } else {
        sin_poly(z, zz)
    };
    if sign {
        -y
    } else {
        y
    }
}

/// Go's `math.Max`: +Inf wins, then NaN, and +0 over -0.
pub fn max(x: f64, y: f64) -> f64 {
    if x == f64::INFINITY || y == f64::INFINITY {
        return f64::INFINITY;
    }
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    if x == 0.0 && x == y {
        return if x.is_sign_negative() { y } else { x };
    }
    if x > y {
        x
    } else {
        y
    }
}

/// Go's `math.Min`: -Inf wins, then NaN, and -0 over +0.
pub fn min(x: f64, y: f64) -> f64 {
    if x == f64::NEG_INFINITY || y == f64::NEG_INFINITY {
        return f64::NEG_INFINITY;
    }
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    if x == 0.0 && x == y {
        return if x.is_sign_negative() { x } else { y };
    }
    if x < y {
        x
    } else {
        y
    }
}

/// Go's `math.Mod`: the exact remainder with the sign of x, which is what
/// Rust's `%` computes.
pub fn fmod(x: f64, y: f64) -> f64 {
    if y == 0.0 || x.is_infinite() || x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    x % y
}

#[cfg(test)]
mod tests {
    use super::*;

    // Values printed by Go 1.27.3 on amd64 (with FMA), math.Float64bits of
    // each call; see plan 167, phase 3.
    #[test]
    fn constants_are_gos() {
        assert_eq!(FOUR_OVER_PI.to_bits(), 0x3ff45f306dc9c883);
        assert_eq!((4.0 / PI).to_bits(), 0x3ff45f306dc9c883);
        assert_eq!((1.0 / 2.4_f64).to_bits(), 0x3fdaaaaaaaaaaaab);
        assert_eq!((1.0 + 1e-6_f64).to_bits(), 0x3ff000010c6f7a0b);
    }

    #[test]
    fn frexp_ldexp_round_trip() {
        for x in [1.0, 0.75, 3.5e-310, -2.0e300, 123.456] {
            let (f, e) = frexp(x);
            assert!((0.5..1.0).contains(&f.abs()), "{x}: {f}");
            assert_eq!(ldexp(f, e), x);
        }
        assert_eq!(frexp(0.0), (0.0, 0));
    }

    #[test]
    fn special_values_follow_go() {
        assert_eq!(pow(2.0, 10.0), 1024.0);
        assert_eq!(pow(4.0, 0.5), 2.0);
        assert!(pow(-8.0, 1.0 / 3.0).is_nan());
        assert_eq!(cbrt(27.0), 3.0);
        assert_eq!(cbrt(-0.0).to_bits(), (-0.0_f64).to_bits());
        assert_eq!(atan2(0.0, -0.0), PI);
        assert_eq!(atan2(-0.0, 1.0).to_bits(), (-0.0_f64).to_bits());
        assert_eq!(exp(0.0), 1.0);
        assert_eq!(exp(-1000.0), 0.0);
        assert_eq!(exp(1000.0), f64::INFINITY);
        assert_eq!(max(-0.0, 0.0).to_bits(), 0.0_f64.to_bits());
        assert_eq!(min(-0.0, 0.0).to_bits(), (-0.0_f64).to_bits());
        assert_eq!(sin(0.0), 0.0);
        assert_eq!(cos(0.0), 1.0);
    }

    // Bits from Go's own math package on the recording machine.
    #[test]
    fn values_match_go_bit_for_bit() {
        type Case = (fn(f64) -> f64, f64, u64);
        let cases: &[Case] = &[
            (cbrt, 0.2, 0x3fe2b6b5edf6b54a),
            (cbrt, 1e-20, 0x3e8cea94cb5c6ff1),
            (log, 0.37, 0xbfefd0ea24bf89b8),
            (exp, -1.3, 0x3fd17129308ce281),
            (exp, -0.123456789, 0x3fec48946a8fcf97),
            (sin, 1.0, 0x3feaed548f090cee),
            (cos, 2.5, 0xbfe9a2f7ef858b7d),
            (atan, 0.7, 0x3fe38b112d7bd4ad),
        ];
        for &(f, x, want) in cases {
            assert_eq!(f(x).to_bits(), want, "{x}");
        }
        assert_eq!(pow(0.5, 2.4).to_bits(), 0x3fc8406003b2ae5d);
        assert_eq!(pow(0.3, 1.0 / 2.4).to_bits(), 0x3fe3607b29bf3436);
        assert_eq!(atan2(-0.02, -0.07).to_bits(), 0xc006e8062854db5e);
    }
}
