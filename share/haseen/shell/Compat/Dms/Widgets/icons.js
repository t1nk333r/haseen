.pragma library

// Material Symbols names (what DMS's DankIcon takes) -> Nerd Font Material
// Design Icons codepoints, for systems without the Material Symbols font.
// haseen's shell layer installs ttf-nerd-fonts-symbols; the codepoints are
// the nf-md-* names from nerd-fonts glyphnames.json. Unknown names show the
// puzzle-piece glyph ("extension"), so a widget never renders empty.

var nerd = {
    "account_circle": 0xF0009,
    "add": 0xF0415,
    "apps": 0xF003B,
    "battery_full": 0xF0079,
    "bluetooth": 0xF00AF,
    "calendar_today": 0xF00ED,
    "check": 0xF012C,
    "close": 0xF0156,
    "cloud": 0xF015F,
    "code": 0xF0174,
    "content_copy": 0xF018F,
    "counter_1": 0xF03A4,
    "dashboard": 0xF056E,
    "delete": 0xF01B4,
    "download": 0xF01DA,
    "edit": 0xF03EB,
    "emoji_emotions": 0xF01F5,
    "error": 0xF0028,
    "extension": 0xF0431,
    "favorite": 0xF02D1,
    "folder": 0xF024B,
    "home": 0xF02DC,
    "image": 0xF02E9,
    "info": 0xF02FC,
    "keyboard": 0xF030C,
    "language": 0xF059F,
    "lock": 0xF033E,
    "memory": 0xF035B,
    "menu": 0xF035C,
    "monitor": 0xF0379,
    "mood": 0xF0C71,
    "music_note": 0xF075A,
    "notes": 0xF039E,
    "notifications": 0xF009A,
    "palette": 0xF03D8,
    "pause": 0xF03E4,
    "person": 0xF0004,
    "play_arrow": 0xF040A,
    "power_settings_new": 0xF0425,
    "radio_button_checked": 0xF043E,
    "radio_button_unchecked": 0xF043D,
    "refresh": 0xF0450,
    "remove": 0xF0374,
    "schedule": 0xF0150,
    "search": 0xF0349,
    "settings": 0xF0493,
    "settings_off": 0xF13CE,
    "speed": 0xF04C5,
    "star": 0xF04CE,
    "sticky_note_2": 0xF039A,
    "stop": 0xF04DB,
    "storage": 0xF02CA,
    "terminal": 0xF018D,
    "thermostat": 0xF050F,
    "timer": 0xF051B,
    "toggle_off": 0xF0522,
    "toggle_on": 0xF0521,
    "upload": 0xF0552,
    "verified_user": 0xF0565,
    "visibility": 0xF0208,
    "volume_up": 0xF057E,
    "wallpaper": 0xF0E09,
    "warning": 0xF0026,
    "widgets": 0xF072C,
    "wifi": 0xF05A9
};

var fallback = 0xF0431;

var _material = null;

// True when a Material Symbols font is installed: DankIcon then renders the
// name as a ligature, exactly like DMS. Checked once per engine.
function hasMaterial() {
    if (_material === null)
        _material = Qt.fontFamilies().indexOf("Material Symbols Rounded") >= 0;
    return _material;
}

function glyph(name) {
    var cp = nerd[String(name)];
    return String.fromCodePoint(cp !== undefined ? cp : fallback);
}
