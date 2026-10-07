pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen as Haseen

// qs.Services.WeatherService for DankMaterialShell plugins (architecture
// 5.4): DMS's current-weather object, filled from whichever haseen plugin
// provides the `weather` role (haseen.weather by default), so a DMS widget
// shows the same place and reading as the bar and makes no request of its
// own. Field names and units follow DankMaterialShell's
// quickshell/Services/WeatherService.qml (MIT, Copyright (c) 2025 Avenge
// Media LLC): temp/feelsLike in °C (tempF/feelsLikeF in °F), wind in km/h,
// humidity in %, wCode a WMO weather code as Open-Meteo reports it. A
// reading that came from wttr.in carries a WWO code, which is translated to
// the nearest WMO one. With no provider or no reading yet, `available` is
// false. The hourly forecast is not provided (forecast stays empty), and
// addRef/removeRef only count: the provider refreshes on its own schedule.
Singleton {
    id: root

    property int refCount: 0
    readonly property var provider: Haseen.Plugins.roles["weather"] ? Haseen.Plugins.roles["weather"].instance : null
    readonly property var current: provider && provider.current ? provider.current : null

    // wttr.in (WWO) condition code -> WMO code.
    readonly property var _wwoToWmo: ({
            "113": 0,
            "116": 2,
            "119": 3,
            "122": 3,
            "143": 45,
            "248": 45,
            "260": 48,
            "176": 80,
            "263": 51,
            "266": 53,
            "281": 56,
            "284": 57,
            "293": 61,
            "296": 61,
            "299": 63,
            "302": 63,
            "305": 65,
            "308": 65,
            "311": 66,
            "314": 67,
            "182": 66,
            "185": 56,
            "317": 66,
            "320": 67,
            "353": 80,
            "356": 81,
            "359": 82,
            "362": 66,
            "365": 67,
            "179": 71,
            "323": 71,
            "326": 71,
            "329": 73,
            "332": 73,
            "335": 75,
            "338": 75,
            "227": 75,
            "230": 75,
            "350": 77,
            "374": 77,
            "377": 77,
            "368": 85,
            "371": 86,
            "200": 95,
            "386": 95,
            "389": 95,
            "392": 96,
            "395": 96
        })

    readonly property var weather: {
        const c = current;
        const p = provider;
        if (!c)
            return emptyWeather();
        const wmo = c.openMeteoWeatherCode !== undefined && c.openMeteoWeatherCode !== null ? Number(c.openMeteoWeatherCode) : (_wwoToWmo[String(c.weatherCode)] ?? 0);
        return {
            available: true,
            loading: false,
            temp: Number(c.temp_C),
            tempF: Number(c.temp_F),
            feelsLike: Number(c.FeelsLikeC),
            feelsLikeF: Number(c.FeelsLikeF),
            city: p.reportLocation || "",
            country: p.reportCountry || "",
            wCode: wmo,
            humidity: Number(c.humidity),
            wind: Number(c.windspeedKmph),
            sunrise: "06:00",
            sunset: "18:00",
            uv: Number(c.uvIndex || 0),
            pressure: Number(c.pressure || 0),
            precipitationProbability: 0,
            isDay: c.isDay === undefined || c.isDay === null ? true : Number(c.isDay) !== 0,
            forecast: []
        };
    }

    function emptyWeather() {
        return {
            available: false,
            loading: provider !== null,
            temp: 0,
            tempF: 0,
            feelsLike: 0,
            feelsLikeF: 0,
            city: "",
            country: "",
            wCode: 0,
            humidity: 0,
            wind: "",
            sunrise: "06:00",
            sunset: "18:00",
            uv: 0,
            pressure: 0,
            precipitationProbability: 0,
            isDay: true,
            forecast: []
        };
    }

    function addRef() {
        refCount++;
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function forceRefresh() {
        if (provider && typeof provider.refresh === "function")
            provider.refresh();
    }
}
