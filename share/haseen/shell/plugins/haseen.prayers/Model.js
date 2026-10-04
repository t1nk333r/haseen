.import "Engine.js" as Engine

var EngineRef = typeof Engine !== "undefined" ? Engine : require("./Engine.js")
var METHODS = EngineRef.METHODS
var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
var DAY_ORDER = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
var NIGHT_ORDER = ["Imsak", "Midnight", "Firstthird", "Lastthird"]
var TUNE_ORDER = [
  "Imsak", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Sunset", "Isha", "Midnight"
]
var TUNE_EDITABLE = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
var LOCATION_RESPONSE_LIMIT = 65536
var DETECT_RESPONSE_LIMIT = 1024
var LOCATION_RESULT_LIMIT = 6
var LOCATION_FIELD_LIMIT = 128
var LOCATION_ZONE_LIMIT = 64

var ARABIC_NAMES = {
  Fajr: "\u0627\u0644\u0641\u062c\u0631",
  Sunrise: "\u0627\u0644\u0634\u0631\u0648\u0642",
  Dhuhr: "\u0627\u0644\u0638\u0647\u0631",
  Asr: "\u0627\u0644\u0639\u0635\u0631",
  Sunset: "\u0627\u0644\u063a\u0631\u0648\u0628",
  Maghrib: "\u0627\u0644\u0645\u063a\u0631\u0628",
  Isha: "\u0627\u0644\u0639\u0634\u0627\u0621",
  Imsak: "\u0627\u0644\u0625\u0645\u0633\u0627\u0643",
  Midnight: "\u0645\u0646\u062a\u0635\u0641 \u0627\u0644\u0644\u064a\u0644",
  Firstthird: "\u0627\u0644\u062b\u0644\u062b \u0627\u0644\u0623\u0648\u0644",
  Lastthird: "\u0627\u0644\u062b\u0644\u062b \u0627\u0644\u0623\u062e\u064a\u0631"
}

var ENGLISH_NAMES = {
  Fajr: "Fajr",
  Sunrise: "Sunrise",
  Dhuhr: "Dhuhr",
  Asr: "Asr",
  Sunset: "Sunset",
  Istijabah: "Waqt istijabah",
  Maghrib: "Maghrib",
  Isha: "Isha",
  Imsak: "Imsak",
  Midnight: "Midnight",
  Firstthird: "First third",
  Lastthird: "Last third"
}

// Option rings for the settings the panel lets the user change in place. Each
// one mirrors the enum in manifest.json, and the order is the click order of
// the panel's cycle buttons.
var PANEL_STYLES = ["Horizon", "Compact"]
var TIME_FORMATS = ["24-hour", "12-hour"]
var LANGUAGES = ["English", "Arabic"]
var SCHOOLS = ["Shafi", "Hanafi"]
var BAR_DISPLAYS = [
  "Strip + countdown", "Icon only", "Name + countdown", "Name + time",
  "Countdown only"
]

// English then Arabic for every string the display section paints. The panel
// is bilingual everywhere else, so its own controls follow `language` too
// rather than staying English inside an otherwise Arabic panel.
var UI_LABELS = {
  location: ["Location", "الموقع"],
  detect: ["Detect", "تحديد"],
  detectPrivacy: ["Detect asks wttr.in for an approximate city using your IP.", "يطلب تحديد الموقع مدينة تقريبية من wttr.in باستخدام عنوان IP الخاص بك."],
  citySearch: ["Search for a city", "ابحث عن مدينة"],
  citySearchPrivacy: ["City search sends your text to Open-Meteo.", "يرسل بحث المدينة النص الذي تكتبه إلى Open-Meteo."],
  searching: ["Searching…", "جاري البحث…"],
  noMatches: ["No matching city", "لا توجد مدينة مطابقة"],
  searchFailed: ["City search failed", "فشل البحث عن المدينة"],
  detectFailed: ["Could not detect a location", "تعذر تحديد الموقع"],
  detectHint: ["Detected from your connection — confirm it", "محدد من اتصالك — تأكيده"],
  calculation: ["Calculation", "الحساب"],
  method: ["Method", "طريقة الحساب"],
  asr: ["Asr", "العصر"],
  tuning: ["Adjust minutes", "تعديل الدقائق"],
  reset: ["Reset", "إعادة ضبط"],
  edit: ["Edit", "تعديل"],
  done: ["Done", "تم"],
  none: ["None", "لا شيء"],
  suggested: ["Suggested for", "المقترح لـ"],
  apply: ["Apply", "تطبيق"],
  dismiss: ["Dismiss", "تجاهل"],
  approximate: ["High-latitude approximation: nearest valid latitude used", "تقريب للمناطق القطبية: استُخدم أقرب خط عرض صالح"],
  searchMethod: ["Search methods", "ابحث عن طريقة"],
  noMethod: ["No matching method", "لا توجد طريقة مطابقة"],
  display: ["Display", "العرض"],
  layout: ["Layout", "التصميم"],
  clock: ["Clock", "الساعة"],
  names: ["Names", "الأسماء"],
  barLabel: ["Bar label", "شريط النظام"],
  sunrise: ["Sunrise row", "صف الشروق"],
  nightMarkers: ["Night markers", "علامات الليل"],
  centerPanel: ["Center panel", "توسيط اللوحة"],
  notifications: ["Notifications", "التنبيهات"],
  accentLead: ["Accent lead", "التلوين المسبق"],
  chime: ["Chime", "نغمة التنبيه"],
  chimeFile: ["Chime file", "ملف النغمة"],
  bundledChime: ["Bundled chime", "النغمة المرفقة"],
  volume: ["Volume", "مستوى الصوت"],
  iqama: ["Iqama", "الإقامة"],
  jumuah: ["Jumu'ah", "الجمعة"],
  istijabah: ["Waqt istijabah", "وقت الاستجابة"],
  istijabahNote: ["The hour before Maghrib on Friday", "الساعة التي قبل المغرب يوم الجمعة"],
  iqamaOffsets: ["Iqama after adhan", "الإقامة بعد الأذان"],
  minutes: ["min", "دقيقة"],
  off: ["Off", "معطل"],
  settingsTip: ["Display settings", "إعدادات العرض"],
  nextTip: ["Switch to", "تحويل إلى"]
}

// Short forms of the enum values. The bar-display names are abbreviated
// because they ride a 150px control rather than the manifest's settings form.
var OPTION_LABELS = {
  Horizon: ["Horizon", "أفق"],
  Compact: ["Compact", "مضغوط"],
  "24-hour": ["24h", "24h"],
  "12-hour": ["12h", "12h"],
  English: ["English", "إنجليزي"],
  Arabic: ["Arabic", "عربي"],
  Shafi: ["Shafi", "شافعي"],
  Hanafi: ["Hanafi", "حنفي"],
  "Strip + countdown": ["Strip", "شريط"],
  "Icon only": ["Icon", "أيقونة"],
  "Name + countdown": ["Name + left", "الاسم والمتبقي"],
  "Name + time": ["Name + time", "الاسم والوقت"],
  "Countdown only": ["Countdown", "المتبقي"]
}

function parseEnvelope(raw) {
  try {
    var value = JSON.parse(String(raw || "{}"))
    return value && typeof value === "object" && !(value instanceof Array) ? value : null
  } catch (e) {
    return null
  }
}

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function latinDigits(value) {
  return text(value).replace(/[\u0660-\u0669\u06f0-\u06f9]/g, function(digit) {
    var code = digit.charCodeAt(0)
    return String(code >= 0x06f0 ? code - 0x06f0 : code - 0x0660)
  })
}

function number(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function bool(value) {
  return value === true || value === 1 || text(value).toLowerCase() === "true"
}

function sameNumber(left, right) {
  return Math.abs(number(left, NaN) - number(right, NaN)) < 0.000001
}

function sameConfig(actual, expected) {
  if (!actual || !expected) return false
  return text(actual.locationLabel) === text(expected.locationLabel)
    && sameNumber(actual.latitude, expected.latitude)
    && sameNumber(actual.longitude, expected.longitude)
    && text(actual.timezone) === text(expected.timezone)
    && number(actual.method, -1) === number(expected.method, -2)
    && number(actual.school, -1) === number(expected.school, -2)
    && number(actual.latitudeAdjustmentMethod, -1) === number(expected.latitudeAdjustmentMethod, -2)
    && number(actual.midnightMode, -1) === number(expected.midnightMode, -2)
    && number(actual.hijriAdjustment, 0) === number(expected.hijriAdjustment, 0)
    && text(actual.tune) === text(expected.tune)
    && text(actual.shafaq) === text(expected.shafaq)
    && text(actual.methodSettings) === text(expected.methodSettings)
}

function label(name, language) {
  var names = text(language) === "Arabic" ? ARABIC_NAMES : ENGLISH_NAMES
  return names[name] || text(name)
}

function localized(table, key, language) {
  var pair = table[text(key)]
  if (!pair) return ""
  return text(language) === "Arabic" ? pair[1] : pair[0]
}

function uiLabel(key, language) {
  return localized(UI_LABELS, key, language)
}

// Falls back to the raw value so a hand-edited shell.json still names itself
// in the panel instead of rendering an empty control.
function optionLabel(value, language) {
  return localized(OPTION_LABELS, value, language) || text(value)
}

// Builds the { value, label } list a Dropdown or ButtonGroup wants, with the
// values kept as the canonical strings that go back into shell.json.
function optionModel(ring, language) {
  var out = []
  for (var i = 0; i < ring.length; i++)
    out.push({ value: ring[i], label: optionLabel(ring[i], language) })
  return out
}

function methodLabel(id, language) {
  var method = EngineRef.methodById(id)
  if (!method) return text(id)
  return text(language) === "Arabic" ? method.name[1] : method.name[0]
}

function decimalText(value) {
  var numberValue = Number(value)
  if (!isFinite(numberValue)) return "0"
  return String(numberValue)
}

function methodValueText(name, value, minutes, language) {
  var prefix = label(name, language) + " "
  if (minutes > 0)
    return prefix + decimalText(minutes) + (text(language) === "Arabic" ? " د" : " min")
  return prefix + decimalText(value) + "°"
}

function methodDescription(method, language, methodSettings) {
  var params = method.id === 99
    ? EngineRef.methodParameters({ method: 99, methodSettings: methodSettings })
    : method
  var parts = [methodValueText("Fajr", params.fajr, 0, language)]
  if (method.id === 99) {
    if (params.maghrib > 0)
      parts.push(methodValueText("Maghrib", params.maghrib, 0, language))
    else
      parts.push(label("Maghrib", language) + " "
        + (text(language) === "Arabic" ? "الغروب" : "sunset"))
  } else if (params.maghribMinutes > 0) {
    parts.push(methodValueText("Maghrib", 0, params.maghribMinutes, language))
  } else if (params.maghrib > 0) {
    parts.push(methodValueText("Maghrib", params.maghrib, 0, language))
  }
  parts.push(methodValueText("Isha", params.isha, params.ishaMinutes, language))
  return parts.join(" · ")
}

function methodOptions(language, methodSettings) {
  var out = []
  for (var i = 0; i < METHODS.length; i++) {
    out.push({
      value: String(METHODS[i].id),
      label: methodLabel(METHODS[i].id, language),
      description: methodDescription(METHODS[i], language, methodSettings)
    })
  }
  return out
}

function suggestedMethod(countryCode, currentMethod) {
  var country = text(countryCode).toUpperCase()
  if (country === "") return null
  for (var i = 0; i < METHODS.length; i++) {
    if (METHODS[i].regions.indexOf(country) !== -1) {
      if (Number(currentMethod) === METHODS[i].id) return null
      return { id: METHODS[i].id, label: METHODS[i].name[0] }
    }
  }
  return null
}

function tuneValues(value) {
  var source = value instanceof Array ? value : text(value).split(",")
  var out = []
  for (var i = 0; i < TUNE_ORDER.length; i++) {
    var parsed = Number(source[i])
    out.push(isFinite(parsed) ? Math.round(parsed) : 0)
  }
  return out
}

function tuneText(values) {
  return tuneValues(values).join(",")
}

function tuneSummary(values, language) {
  var normalized = tuneValues(values)
  var parts = []
  for (var i = 0; i < TUNE_ORDER.length; i++) {
    if (normalized[i] === 0) continue
    var amount = normalized[i] > 0 ? "+" + normalized[i] : "−" + Math.abs(normalized[i])
    parts.push(label(TUNE_ORDER[i], language) + " " + amount)
  }
  return parts.join(" · ")
}

function schoolLabel(school, language) {
  return optionLabel(Number(school) === 1 || text(school) === "Hanafi" ? "Hanafi" : "Shafi", language)
}

// curl >= 8.4 enforces max-filesize even without Content-Length. Disable the
// user's curlrc so it cannot add extra transfers or automatic decompression.
function geocodeCommand(query) {
  return ["curl", "-q", "-fsS", "--max-time", "6",
    "--max-filesize", String(LOCATION_RESPONSE_LIMIT),
    "https://geocoding-api.open-meteo.com/v1/search?name="
      + encodeURIComponent(query) + "&count=" + LOCATION_RESULT_LIMIT + "&language=en&format=json"]
}

function detectLocationCommand() {
  return ["curl", "-q", "-fsS", "--max-time", "5",
    "--max-filesize", String(DETECT_RESPONSE_LIMIT), "https://wttr.in/?format=%l"]
}

function locationField(value, limit) {
  if (value === undefined || value === null) return ""
  if (typeof value !== "string" || value.length > limit) return null
  return value.replace(/^\s+|\s+$/g, "")
}

// Open-Meteo geocoding response to a list of choices. The timezone is why this
// endpoint is used at all: prayer times are computed against an absolute zone,
// and deriving one from coordinates would be a silent correctness risk. A
// result without a zone is therefore dropped rather than guessed at — a search
// for "Springfield" spans two different zones, so the zone has to come from the
// row the user actually picked.
function parseLocationResults(raw) {
  // Guard before JSON.parse too. The transport cap is in bytes; a decoded
  // UTF-8 response cannot contain more UTF-16 code units than input bytes.
  if (typeof raw !== "string" || raw.length > LOCATION_RESPONSE_LIMIT) return []
  var data = parseEnvelope(raw)
  if (!data || !(data.results instanceof Array)) return []
  var out = []
  for (var i = 0; i < Math.min(data.results.length, LOCATION_RESULT_LIMIT); i++) {
    var result = data.results[i]
    if (!result || typeof result !== "object") continue
    var name = locationField(result.name, LOCATION_FIELD_LIMIT)
    var admin = locationField(result.admin1, LOCATION_FIELD_LIMIT)
    var country = locationField(result.country, LOCATION_FIELD_LIMIT)
    var countryCode = locationField(result.country_code, 2)
    var timezone = locationField(result.timezone, LOCATION_ZONE_LIMIT)
    if (!name || !timezone || admin === null || country === null || countryCode === null) continue
    var latitude = result.latitude
    var longitude = result.longitude
    if (typeof latitude !== "number" || typeof longitude !== "number"
        || !isFinite(latitude) || !isFinite(longitude)
        || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) continue
    var region = [admin, country]
      .filter(function(part) { return part !== "" })
      .join(", ")
    out.push({
      name: name,
      region: region,
      country: country,
      countryCode: countryCode.toUpperCase(),
      latitude: latitude,
      longitude: longitude,
      timezone: timezone
    })
  }
  return out
}

// wttr.in answers `?format=%l` with "City, Region, CC". Only the leading
// segment is kept, and it is used to seed the search box rather than treated as
// a location: the address it derives from the connection can be a long way from
// where the user actually is.
function detectedLocationQuery(raw) {
  if (typeof raw !== "string" || raw.length > DETECT_RESPONSE_LIMIT) return ""
  var value = raw.replace(/^\s+|\s+$/g, "")
  if (value === "") return ""
  var query = value.split(",")[0].replace(/\+/g, " ").replace(/^\s+|\s+$/g, "")
  return query.length <= LOCATION_FIELD_LIMIT ? query : ""
}

// The four location keys are written as one unit. A partial write would leave
// the timezone describing a different place than the coordinates.
// locationLabelAr is
// cleared because an Arabic label kept from the previous city would name the
// wrong place; the panel falls back to locationLabel when it is empty.
function locationSettings(choice) {
  if (!choice) return null
  var latitude = Number(choice.latitude)
  var longitude = Number(choice.longitude)
  if (!isFinite(latitude) || !isFinite(longitude)) return null
  if (text(choice.timezone) === "" || text(choice.name) === "") return null
  return {
    locationLabel: text(choice.name),
    locationLabelAr: "",
    latitude: String(latitude),
    longitude: String(longitude),
    timezone: text(choice.timezone)
  }
}

// A value outside the ring lands on the first option rather than nowhere, so a
// typo in shell.json cannot strand a cycle button on a value it does not know.
function nextInRing(ring, current) {
  if (!(ring instanceof Array) || ring.length === 0) return ""
  var index = ring.indexOf(text(current))
  return index < 0 ? ring[0] : ring[(index + 1) % ring.length]
}

// Keep values handed to the panel's dropdown inside its fixed option ring, so
// a typo in shell.json shows a real option rather than a raw value.
function valueInRing(ring, current) {
  if (!(ring instanceof Array) || ring.length === 0) return ""
  var value = text(current)
  return ring.indexOf(value) >= 0 ? value : ring[0]
}

function dayForDate(schedule, dateKey) {
  var days = schedule && schedule.days instanceof Array ? schedule.days : []
  for (var i = 0; i < days.length; i++) {
    if (text(days[i].date) === text(dateKey)) return days[i]
  }
  return null
}

function today(schedule) {
  return dayForDate(schedule, schedule ? schedule.today : "")
}

function timing(day, name) {
  return day && day.timings && day.timings[name] ? day.timings[name] : null
}

function instant(value) {
  if (!value || !value.at) return null
  var parsed = new Date(value.at)
  return isNaN(parsed.getTime()) ? null : parsed
}

function scheduleEvents(schedule, names) {
  var days = schedule && schedule.days instanceof Array ? schedule.days : []
  var wanted = names || PRAYERS
  var result = []
  for (var d = 0; d < days.length; d++) {
    for (var p = 0; p < wanted.length; p++) {
      var value = timing(days[d], wanted[p])
      var at = instant(value)
      if (!at) continue
      result.push({
        name: wanted[p],
        date: days[d].date,
        at: at,
        iso: value.at,
        time: value.time || "",
        day: days[d]
      })
    }
  }
  result.sort(function(a, b) { return a.at.getTime() - b.at.getTime() })
  return result
}

function nextPrayer(schedule, now) {
  var epoch = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(epoch)) epoch = Date.now()
  var events = scheduleEvents(schedule, PRAYERS)
  for (var i = 0; i < events.length; i++) {
    if (events[i].at.getTime() > epoch) return events[i]
  }
  return null
}

function currentPrayer(schedule, now) {
  var epoch = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(epoch)) epoch = Date.now()
  var events = scheduleEvents(schedule, PRAYERS)
  var current = null
  for (var i = 0; i < events.length; i++) {
    if (events[i].at.getTime() > epoch) break
    current = events[i]
  }
  return current
}

// What the countdown should actually be aimed at. Between an adhan and its
// iqama the prayer has not passed — the congregation is what is coming — so
// for that stretch the target is the iqama, and only afterwards the next
// adhan. Returns a prayer event unchanged, or an iqama shaped like one
// (`at`, `time`, `name`, `date`, `day`) with `kind: "iqama"` and the caption
// key the timetable already uses, so every caller that formats an event needs
// no new case to keep working.
//
// iqamaFor is the single source for the offset, Friday's Jumu'ah included, so
// the bar cannot disagree with the row under it. Without offsets, or with this
// prayer's offset at zero, the answer is exactly what nextPrayer gives.
function nextEvent(schedule, now, iqamaOffsets) {
  var epoch = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(epoch)) epoch = Date.now()
  var next = nextPrayer(schedule, now)
  var current = currentPrayer(schedule, now)
  if (!current || !iqamaOffsets) return next
  var iqama = iqamaFor(current.day, current.name, iqamaOffsets)
  if (!iqama) return next
  var at = typeof iqama.at === "number" ? iqama.at : Date.parse(text(iqama.at))
  if (!isFinite(at) || at <= epoch) return next
  // An offset long enough to run past the following adhan would otherwise hide
  // it. The adhan is the harder deadline, so it wins that overlap.
  if (next && next.at.getTime() <= at) return next
  return {
    name: current.name,
    date: current.date,
    day: current.day,
    time: iqama.time,
    at: new Date(at),
    iso: current.iso,
    kind: "iqama",
    label: iqama.label || "iqama",
    minutes: iqama.minutes,
    prayer: current
  }
}

function minutesUntil(event, now) {
  if (!event || !event.at) return Infinity
  var epoch = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(epoch)) epoch = Date.now()
  return Math.ceil((event.at.getTime() - epoch) / 60000)
}

function remaining(event, now, language) {
  var minutes = minutesUntil(event, now)
  if (!isFinite(minutes)) return ""
  if (minutes <= 0) return text(language) === "Arabic" ? "\u0627\u0644\u0622\u0646" : "now"
  return formatDuration(minutes, language)
}

function formatClock(clock, format) {
  var match = /^(\d{1,2}):(\d{2})/.exec(text(clock))
  if (!match) return text(clock)
  var hour = parseInt(match[1], 10)
  var minute = match[2]
  if (text(format) !== "12-hour") return (hour < 10 ? "0" : "") + hour + ":" + minute
  var suffix = hour >= 12 ? "PM" : "AM"
  var displayHour = hour % 12
  if (displayHour === 0) displayHour = 12
  return displayHour + ":" + minute + " " + suffix
}

function minutesOfDay(value) {
  var match = /^(\d{1,2}):(\d{2})/.exec(text(value && value.time))
  if (!match) return NaN
  var hour = parseInt(match[1], 10)
  var minute = parseInt(match[2], 10)
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return NaN
  return hour * 60 + minute
}

function formatDuration(minutes, language) {
  var value = Number(minutes)
  if (!isFinite(value) || value < 0) return ""
  value = Math.round(value)
  var hours = Math.floor(value / 60)
  var rest = value % 60
  var hourUnit = text(language) === "Arabic" ? " س" : "h"
  var minuteUnit = text(language) === "Arabic" ? " د" : "m"
  if (hours <= 0) return rest + minuteUnit
  if (rest === 0) return hours + hourUnit
  return hours + hourUnit + " " + rest + minuteUnit
}

function methodShortName(methodId, fallbackName, language) {
  var method = EngineRef.methodById(methodId)
  if (method) return text(language) === "Arabic" ? method.short[1] : method.short[0]
  var words = text(fallbackName).match(/[A-Za-z0-9]+/g) || []
  var acronym = ""
  for (var i = 0; i < words.length && acronym.length < 5; i++) {
    if (words[i].length >= 3) acronym += words[i].charAt(0).toUpperCase()
  }
  return acronym || "METHOD " + methodId
}

function tomorrowPrayerLabel(prayer, language, timeFormat) {
  if (!prayer) return ""
  if (text(language) === "Arabic")
    return "\u2067\u063a\u062f\u064b\u0627  " + label(prayer.name, language) + "  \u00b7  "
      + formatClock(prayer.time, timeFormat) + "\u2069"
  return "Tomorrow \u2068" + label(prayer.name, language) + "\u2069  \u00b7  "
    + formatClock(prayer.time, timeFormat)
}

// The bar's name slot for an event: the prayer, or — while its iqama is what
// is being counted — the same caption the timetable prints under that prayer
// ("Iqama", "Jumu'ah", and their Arabic forms). The prayer itself is the one
// that has just been called, so repeating its name buys nothing and the bar
// has little room; the tooltip and the panel still say both.
function eventLabel(event, language) {
  if (!event) return ""
  if (event.kind === "iqama") return uiLabel(event.label || "iqama", language)
  return label(event.name, language)
}

function barText(next, now, language, mode, timeFormat) {
  var icon = "\ueed3"
  if (!next) return icon
  var prayer = eventLabel(next, language)
  if (mode === "Icon only") return icon
  if (mode === "Countdown only") return remaining(next, now, language)
  var value = mode === "Name + time"
    ? formatClock(next.time, timeFormat)
    : remaining(next, now, language)
  if (text(language) === "Arabic") return "\u2067" + prayer + " " + value + "\u2069"
  return prayer + " " + value
}

function tooltip(schedule, next, now, language, timeFormat, locationOverride) {
  var arabic = text(language) === "Arabic"
  if (!next) return arabic ? "مواقيت الصلاة غير متاحة" : "Prayer times unavailable"
  var location = text(locationOverride)
  if (!location && schedule && schedule.config) location = text(schedule.config.locationLabel)
  var prefix = location ? location + " \u00b7 " : ""
  var prayerDay = dayForDate(schedule, next.date) || next.day
  var methodName = prayerDay ? text(prayerDay.methodName) : ""
  var method = methodName ? " \u00b7 " + methodName : ""
  var subject = next.kind === "iqama"
    ? label(next.name, language) + " " + uiLabel(next.label || "iqama", language)
    : label(next.name, language)
  var result = prefix + subject + (arabic ? " بعد " : " in ")
    + remaining(next, now, language)
    + " (" + formatClock(next.time, timeFormat) + ")" + method
  // Location and calculation-method labels can come from network responses,
  // so neutralize markup delimiters before any rich-text renderer sees them.
  return result.replace(/</g, "‹").replace(/>/g, "›")
}

// The congregational start, `offset` minutes after the prayer itself. Zero or
// missing means this prayer has no iqama and its row stays one line; sunrise
// never has one. Both fields are derived here and nowhere stored: the iqama
// moves with the adhan, so it is recomputed from the schedule on every read.
function iqamaValue(value, offsetMinutes) {
  var minutes = Number(offsetMinutes)
  if (!value || !isFinite(minutes) || minutes <= 0) return null
  var clock = /^(\d{1,2}):(\d{2})/.exec(text(value.time))
  if (!clock) return null
  var total = (parseInt(clock[1], 10) * 60 + parseInt(clock[2], 10) + Math.round(minutes)) % 1440
  if (total < 0) total += 1440
  var hour = Math.floor(total / 60)
  var stamp = typeof value.at === "number" ? value.at : Date.parse(text(value.at))
  return {
    time: (hour < 10 ? "0" : "") + hour + ":" + (total % 60 < 10 ? "0" : "") + (total % 60),
    minutes: Math.round(minutes),
    at: isFinite(stamp) ? stamp + Math.round(minutes) * 60000 : value.at
  }
}

// Friday is the schedule's own weekday, not the machine's: a day carries the
// location's local date, so the weekday is read from that date alone.
function isFriday(day) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text(day && day.date))
  if (!match) return false
  return new Date(Date.UTC(parseInt(match[1], 10), parseInt(match[2], 10) - 1,
    parseInt(match[3], 10))).getUTCDay() === 5
}

// Friday's Dhuhr is the Jumu'ah: its iqama follows the khutbah, so it reads
// its own offset and names itself.
function iqamaFor(day, name, offsets) {
  if (!offsets || DAY_ORDER.indexOf(name) === -1 || name === "Sunrise") return null
  var friday = isFriday(day)
  var offset = friday && name === "Dhuhr" ? offsets.Jumuah : offsets[name]
  var value = iqamaValue(timing(day, name), offset)
  if (!value) return null
  value.label = friday && name === "Dhuhr" ? "jumuah" : "iqama"
  return value
}

// The hour of answered supplication: the last hour before Friday's Maghrib.
function istijabahTime(day, leadMinutes) {
  var minutes = Number(leadMinutes)
  if (!isFriday(day) || !isFinite(minutes) || minutes <= 0) return null
  var clock = /^(\d{1,2}):(\d{2})/.exec(text((timing(day, "Maghrib") || {}).time))
  if (!clock) return null
  var total = (parseInt(clock[1], 10) * 60 + parseInt(clock[2], 10) - Math.round(minutes)) % 1440
  if (total < 0) total += 1440
  var hour = Math.floor(total / 60)
  var maghrib = timing(day, "Maghrib")
  var stamp = typeof maghrib.at === "number" ? maghrib.at : Date.parse(text(maghrib.at))
  return {
    time: (hour < 10 ? "0" : "") + hour + ":" + (total % 60 < 10 ? "0" : "") + (total % 60),
    minutes: Math.round(minutes),
    at: isFinite(stamp) ? stamp - Math.round(minutes) * 60000 : maghrib.at,
    // Where the window ends: Maghrib's own instant, so a repeating reminder
    // knows to stop before the adhan rather than on top of it.
    endAt: isFinite(stamp) ? stamp : maghrib.at,
    label: "istijabah"
  }
}

function dayRows(day, showSunrise, iqamaOffsets, istijabah) {
  var result = []
  for (var i = 0; i < DAY_ORDER.length; i++) {
    if (DAY_ORDER[i] === "Sunrise" && !showSunrise) continue
    var value = timing(day, DAY_ORDER[i])
    if (value) result.push({
      name: DAY_ORDER[i],
      value: value,
      iqama: iqamaFor(day, DAY_ORDER[i], iqamaOffsets)
    })
    // Fridays carry one extra row, directly under the Maghrib it precedes.
    if (DAY_ORDER[i] === "Maghrib" && istijabah && istijabah.enabled) {
      var window = istijabahTime(day, istijabah.leadMinutes)
      if (window) result.push({ name: "Istijabah", value: window, iqama: null, marker: true })
    }
  }
  return result
}

function daySegments(day, showSunrise) {
  if (!day) return []
  var boundaries = []
  for (var i = 0; i < DAY_ORDER.length; i++) {
    if (DAY_ORDER[i] === "Sunrise" && !showSunrise) continue
    var value = timing(day, DAY_ORDER[i])
    var minutes = minutesOfDay(value)
    if (!value || !isFinite(minutes)) return []
    while (boundaries.length && minutes <= boundaries[boundaries.length - 1].minutes)
      minutes += 1440
    if (boundaries.length && minutes >= boundaries[0].minutes + 1440) return []
    boundaries.push({ name: DAY_ORDER[i], value: value, minutes: minutes })
  }
  var result = []
  for (var b = 0; b < boundaries.length; b++) {
    var start = boundaries[b].minutes
    var end = b + 1 < boundaries.length
      ? boundaries[b + 1].minutes
      : boundaries[0].minutes + 1440
    result.push({
      name: boundaries[b].name,
      value: boundaries[b].value,
      start: start,
      end: end,
      length: end - start
    })
  }
  return result
}

function nightRows(day) {
  var result = []
  for (var i = 0; i < NIGHT_ORDER.length; i++) {
    var value = timing(day, NIGHT_ORDER[i])
    if (value) result.push({ name: NIGHT_ORDER[i], value: value })
  }
  return result
}

function nightMarkers(day) {
  if (!day) return null
  var start = minutesOfDay(timing(day, "Maghrib"))
  var fajr = minutesOfDay(timing(day, "Fajr"))
  if (!isFinite(start) || !isFinite(fajr)) return null
  var end = fajr + 1440
  var span = end - start
  if (span <= 0) return null
  var names = NIGHT_ORDER.slice(1)
  names.push("Isha")
  var marks = []
  for (var i = 0; i < names.length; i++) {
    var minutes = minutesOfDay(timing(day, names[i]))
    if (!isFinite(minutes)) continue
    if (minutes < start) minutes += 1440
    var fraction = Math.max(0, Math.min(1, (minutes - start) / span))
    marks.push({ name: names[i], minutes: minutes, fraction: fraction })
  }
  marks.sort(function(left, right) { return left.fraction - right.fraction })
  return { start: start, end: end, span: span, marks: marks }
}

function fractionOfDay(day, now) {
  var fajr = instant(timing(day, "Fajr"))
  if (!fajr) return 0
  var epoch = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(epoch)) return 0
  var fraction = (epoch - fajr.getTime()) / 86400000
  if (fraction < 0) fraction += 1
  return Math.max(0, Math.min(1, fraction))
}

function windowLabel(segment, language) {
  return formatDuration(segment ? segment.length : NaN, language)
}

function hijriLabel(day, language) {
  if (!day || !day.hijri) return ""
  if (text(language) === "Arabic" && day.hijri.displayAr)
    return text(day.hijri.displayAr)
  if (day.hijri.display) return text(day.hijri.display)
  return [day.hijri.day, day.hijri.month, day.hijri.year].filter(function(value) {
    return text(value) !== ""
  }).join(" ")
}

function statusLabel(status, language) {
  if (text(language) === "Arabic") {
    if (status === "local") return "محسوبة دون اتصال"
    return "غير محمل"
  }
  if (status === "local") return "calculated offline"
  return "not loaded"
}

function notificationEvents(schedule, previousEpoch, currentEpoch, beforeMinutes, graceMinutes, istijabah) {
  var previous = Number(previousEpoch)
  var current = Number(currentEpoch)
  if (!isFinite(previous) || !isFinite(current) || current <= previous) return []
  var before = Math.max(0, Math.floor(number(beforeMinutes, 0)))
  var graceMs = Math.max(1, Math.floor(number(graceMinutes, 10))) * 60000
  var events = scheduleEvents(schedule, PRAYERS)
  var result = []

  // Friday's hour of answered supplication. It opens an hour before Maghrib
  // and, with `repeatMinutes` set, is announced again every so many minutes
  // until Maghrib — the window is a period, not a moment, and a single note at
  // its start is easy to miss. Each reminder has its own key, so the dedup
  // state lets every one through once and no more; `repeatMinutes` 0 (the
  // default when the setting is absent) keeps the historic single alert.
  if (istijabah && istijabah.enabled) {
    var days = schedule && schedule.days instanceof Array ? schedule.days : []
    var step = Math.max(0, Math.round(number(istijabah.repeatMinutes, 0)))
    for (var d = 0; d < days.length; d++) {
      var window = istijabahTime(days[d], istijabah.leadMinutes)
      var windowAt = window ? instant(window) : null
      if (!windowAt) continue
      var windowEpoch = windowAt.getTime()
      var endEpoch = Number(window.endAt)
      var offsets = [0]
      for (var k = step; step > 0 && k < window.minutes; k += step) {
        // Strictly before Maghrib: the adhan fires its own event, and a
        // reminder landing on it would talk over the call.
        if (isFinite(endEpoch) && windowEpoch + k * 60000 >= endEpoch) break
        offsets.push(k)
      }
      for (var o = 0; o < offsets.length; o++) {
        var reminderEpoch = windowEpoch + offsets[o] * 60000
        if (previous < reminderEpoch && reminderEpoch <= current
            && current - reminderEpoch <= graceMs) {
          result.push({
            key: days[d].date + "|istijabah+" + offsets[o],
            name: "Istijabah",
            kind: "istijabah",
            minutes: window.minutes,
            repeatMinutes: offsets[o],
            time: window.time,
            triggerEpoch: reminderEpoch
          })
        }
      }
    }
  }

  for (var i = 0; i < events.length; i++) {
    var prayerAt = events[i].at.getTime()
    if (before > 0) {
      var reminderAt = prayerAt - before * 60000
      if (previous < reminderAt && reminderAt <= current
          && current - reminderAt <= graceMs && current < prayerAt) {
        result.push({
          key: events[i].iso + "|before-" + before,
          name: events[i].name,
          kind: "before",
          minutes: before,
          time: events[i].time,
          triggerEpoch: reminderAt
        })
      }
    }
    if (previous < prayerAt && prayerAt <= current && current - prayerAt <= graceMs) {
      result.push({
        key: events[i].iso + "|at",
        name: events[i].name,
        kind: "at",
        minutes: 0,
        time: events[i].time,
        triggerEpoch: prayerAt
      })
    }
  }
  // Chronological: a long tick (the machine was asleep) can catch a reminder
  // and the adhan after it in one window, and the adhan must read last.
  result.sort(function (a, b) { return a.triggerEpoch - b.triggerEpoch })
  return result
}

function notificationText(event, language, timeFormat) {
  var prayer = label(event.name, language)
  var arabic = text(language) === "Arabic"
  if (event.kind === "istijabah") {
    if (arabic) {
      return {
        title: uiLabel("istijabah", language),
        body: uiLabel("istijabahNote", language) + " · " + formatClock(event.time, timeFormat)
      }
    }
    return {
      title: uiLabel("istijabah", language),
      body: uiLabel("istijabahNote", language) + " · " + formatClock(event.time, timeFormat)
    }
  }
  if (event.kind === "before") {
    if (arabic) {
      return {
        title: prayer + " بعد " + formatDuration(event.minutes, language),
        body: "الموعد " + formatClock(event.time, timeFormat)
      }
    }
    return {
      title: prayer + " in " + event.minutes + " minutes",
      body: "Scheduled for " + formatClock(event.time, timeFormat)
    }
  }
  if (arabic) {
    return {
      title: "حان وقت " + prayer,
      body: formatClock(event.time, timeFormat)
    }
  }
  return {
    title: "It is time for " + prayer,
    body: formatClock(event.time, timeFormat)
  }
}

function filePath(url) {
  var value = decodeURIComponent(text(url))
  return value.replace(/^file:\/\//, "")
}

if (typeof module !== "undefined") {
  module.exports = {
    LOCATION_RESPONSE_LIMIT: LOCATION_RESPONSE_LIMIT,
    DETECT_RESPONSE_LIMIT: DETECT_RESPONSE_LIMIT,
    LOCATION_RESULT_LIMIT: LOCATION_RESULT_LIMIT,
    LOCATION_FIELD_LIMIT: LOCATION_FIELD_LIMIT,
    LOCATION_ZONE_LIMIT: LOCATION_ZONE_LIMIT,
    geocodeCommand: geocodeCommand,
    detectLocationCommand: detectLocationCommand,
    METHODS: METHODS,
    PRAYERS: PRAYERS,
    DAY_ORDER: DAY_ORDER,
    NIGHT_ORDER: NIGHT_ORDER,
    PANEL_STYLES: PANEL_STYLES,
    TIME_FORMATS: TIME_FORMATS,
    LANGUAGES: LANGUAGES,
    BAR_DISPLAYS: BAR_DISPLAYS,
    SCHOOLS: SCHOOLS,
    TUNE_ORDER: TUNE_ORDER,
    TUNE_EDITABLE: TUNE_EDITABLE,
    parseEnvelope: parseEnvelope,
    latinDigits: latinDigits,
    sameConfig: sameConfig,
    label: label,
    uiLabel: uiLabel,
    optionLabel: optionLabel,
    optionModel: optionModel,
    methodOptions: methodOptions,
    methodLabel: methodLabel,
    suggestedMethod: suggestedMethod,
    tuneValues: tuneValues,
    tuneText: tuneText,
    tuneSummary: tuneSummary,
    schoolLabel: schoolLabel,
    nextInRing: nextInRing,
    valueInRing: valueInRing,
    parseLocationResults: parseLocationResults,
    detectedLocationQuery: detectedLocationQuery,
    locationSettings: locationSettings,
    dayForDate: dayForDate,
    today: today,
    timing: timing,
    instant: instant,
    scheduleEvents: scheduleEvents,
    nextPrayer: nextPrayer,
    currentPrayer: currentPrayer,
    nextEvent: nextEvent,
    eventLabel: eventLabel,
    minutesUntil: minutesUntil,
    remaining: remaining,
    formatClock: formatClock,
    minutesOfDay: minutesOfDay,
    formatDuration: formatDuration,
    methodShortName: methodShortName,
    tomorrowPrayerLabel: tomorrowPrayerLabel,
    barText: barText,
    tooltip: tooltip,
    dayRows: dayRows,
    iqamaValue: iqamaValue,
    iqamaFor: iqamaFor,
    isFriday: isFriday,
    istijabahTime: istijabahTime,
    daySegments: daySegments,
    nightRows: nightRows,
    nightMarkers: nightMarkers,
    fractionOfDay: fractionOfDay,
    windowLabel: windowLabel,
    hijriLabel: hijriLabel,
    statusLabel: statusLabel,
    notificationEvents: notificationEvents,
    notificationText: notificationText,
    filePath: filePath,
    bool: bool,
    number: number
  }
}
