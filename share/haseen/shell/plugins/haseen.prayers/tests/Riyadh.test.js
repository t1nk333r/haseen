// haseen.prayers: the shipped defaults (Riyadh city centre, Umm al-Qura)
// against a published reference, through the real zone script.
//
// Reference: AlAdhan timings API, method 4 (Umm Al-Qura University, Makkah),
// queried 2026-10-04:
//   https://api.aladhan.com/v1/timings/04-10-2026?latitude=24.7136&longitude=46.6753&method=4&timezonestring=Asia/Riyadh
//   https://api.aladhan.com/v1/timings/15-03-2027?latitude=24.7136&longitude=46.6753&method=4&timezonestring=Asia/Riyadh
// Every listed time must match within one minute, and the Hijri date exactly.
process.env.TZ = "UTC"
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const fs = require("node:fs")
const path = require("node:path")
const Engine = require("../Engine.js")

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const d = name => manifest.settings[name].default

const references = [
  {
    date: "2026-10-04",
    hijri: { day: 23, month: "Rabi' al-Thani", year: 1448 },
    timings: { Imsak: "04:19", Fajr: "04:29", Sunrise: "05:46", Dhuhr: "11:42", Asr: "15:06", Maghrib: "17:37", Isha: "19:07", Midnight: "23:42", Firstthird: "21:40", Lastthird: "01:43" }
  },
  {
    date: "2027-03-15",
    hijri: { day: 7, month: "Shawwal", year: 1448 },
    timings: { Imsak: "04:35", Fajr: "04:45", Sunrise: "06:03", Dhuhr: "12:02", Asr: "15:27", Maghrib: "18:02", Isha: "19:32", Midnight: "00:02", Firstthird: "22:02", Lastthird: "02:03" }
  }
]

const minutes = clock => {
  const [h, m] = clock.split(":").map(Number)
  return h * 60 + m
}

let compared = 0
for (const ref of references) {
  // Noon in Riyadh (UTC+3) on the reference day.
  const now = Date.parse(`${ref.date}T09:00:00Z`)
  const zone = JSON.parse(execFileSync(path.join(__dirname, "..", "haseen-prayers-zone.sh"),
    ["--timezone", d("timezone"), "--days", "5", "--now", String(now / 1000)], { encoding: "utf8" }))
  const schedule = Engine.buildSchedule({
    locationLabel: d("locationLabel"),
    latitude: d("latitude"),
    longitude: d("longitude"),
    timezone: d("timezone"),
    method: d("calculationMethod"),
    school: 0,
    latitudeAdjustmentMethod: 3,
    midnightMode: 0,
    hijriAdjustment: 0,
    tune: d("tune"),
    shafaq: "general",
    methodSettings: ""
  }, zone, now)
  assert.equal(schedule.ok, true, schedule.error)
  const day = schedule.days.find(entry => entry.date === ref.date)
  assert.ok(day, `no schedule day ${ref.date}`)
  for (const [name, expected] of Object.entries(ref.timings)) {
    const got = day.timings[name].time
    let delta = Math.abs(minutes(got) - minutes(expected))
    delta = Math.min(delta, 1440 - delta)
    assert.ok(delta <= 1, `${ref.date} ${name}: engine ${got}, AlAdhan ${expected}`)
    compared++
  }
  const hijri = day.hijri
  assert.equal(Number(hijri.day), ref.hijri.day, `${ref.date} Hijri day`)
  assert.equal(hijri.month, ref.hijri.month, `${ref.date} Hijri month`)
  assert.equal(Number(hijri.year), ref.hijri.year, `${ref.date} Hijri year`)
}
console.log(`Riyadh reference passed (${compared} times within 1 min)`)
