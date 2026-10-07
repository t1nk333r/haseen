pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common

// qs.Services.BatteryService for DankMaterialShell plugins (architecture
// 5.4): the laptop battery as UPower reports it, read-only. Property and
// function names, the multi-battery aggregation, the 20 % / 10 % low and
// critical thresholds and the Material icon names follow DankMaterialShell's
// quickshell/Services/BatteryService.qml (MIT, Copyright (c) 2025 Avenge
// Media LLC). Not provided here: DMS's battery alerts (the haseen.battery
// service sends the low and critical notifications, plan 075), its sounds
// (haseen has none), the FreeBSD fallback, and anything that changes power
// state.
Singleton {
    id: root

    readonly property int lowThreshold: 20
    readonly property int criticalThreshold: 10

    // DMS_PREFERRED_BATTERY picks one battery by native path, as in DMS.
    readonly property string preferredBatteryOverride: Quickshell.env("DMS_PREFERRED_BATTERY") || ""
    readonly property bool usePreferred: preferredBatteryOverride.length > 0

    readonly property var batteries: UPower.devices.values.filter(dev => dev.isLaptopBattery)
    readonly property var readyBatteries: batteries.filter(b => b.ready)
    readonly property var stateKnownBatteries: batteries.filter(b => b.ready && b.state !== UPowerDeviceState.Unknown)
    readonly property var chargeBatteries: readyBatteries.filter(b => root._hasUsableCharge(b))
    readonly property var energyBatteries: readyBatteries.filter(b => b.energyCapacity > 0)

    readonly property UPowerDevice preferredDevice: usePreferred ? (batteries.find(dev => dev.nativePath.toLowerCase().includes(preferredBatteryOverride.toLowerCase())) || null) : null
    readonly property bool preferredDeviceReady: preferredDevice !== null && preferredDevice.ready
    readonly property bool preferredDeviceKnown: preferredDeviceReady && preferredDevice.state !== UPowerDeviceState.Unknown

    // The main battery.
    readonly property UPowerDevice device: {
        if (usePreferred)
            return preferredDeviceKnown ? preferredDevice : (stateKnownBatteries[0] || null);
        return stateKnownBatteries[0] || readyBatteries[0] || batteries[0] || null;
    }

    readonly property bool batteryAvailable: batteries.length > 0
    readonly property real batteryLevel: batteryAvailable ? _chargePercent() : 0
    readonly property bool isCharging: {
        if (!batteryAvailable)
            return false;
        if (usePreferred)
            return preferredDeviceKnown && preferredDevice.state === UPowerDeviceState.Charging;
        return stateKnownBatteries.some(b => b.state === UPowerDeviceState.Charging);
    }
    readonly property bool isPluggedIn: !UPower.onBattery
    readonly property bool hasBatteryReading: batteryAvailable && batteryLevel > 0
    readonly property bool isLowBattery: hasBatteryReading && batteryLevel <= lowThreshold
    readonly property bool isCriticalBattery: hasBatteryReading && batteryLevel <= criticalThreshold

    // Watts summed over the batteries whose state is known.
    readonly property real changeRate: {
        if (!batteryAvailable)
            return 0;
        if (usePreferred)
            return preferredDeviceKnown ? preferredDevice.changeRate : 0;
        return stateKnownBatteries.reduce((sum, b) => sum + b.changeRate, 0);
    }

    readonly property string batteryHealth: {
        if (!batteryAvailable)
            return "N/A";
        if (usePreferred && preferredDeviceReady && preferredDevice.healthSupported)
            return Math.round(preferredDevice.healthPercentage) + "%";
        const valid = readyBatteries.filter(b => b.healthSupported && b.healthPercentage > 0);
        if (valid.length === 0)
            return "N/A";
        return Math.round(valid.reduce((sum, b) => sum + b.healthPercentage, 0) / valid.length) + "%";
    }

    // Watt-hours now in the batteries, and when full.
    readonly property real batteryEnergy: {
        if (!batteryAvailable)
            return 0;
        if (usePreferred)
            return preferredDeviceReady ? preferredDevice.energy : 0;
        return energyBatteries.reduce((sum, b) => sum + Math.max(0, b.energy), 0);
    }
    readonly property real batteryCapacity: {
        if (!batteryAvailable)
            return 0;
        if (usePreferred)
            return preferredDeviceReady ? preferredDevice.energyCapacity : 0;
        return energyBatteries.reduce((sum, b) => sum + b.energyCapacity, 0);
    }

    readonly property string batteryStatus: {
        if (!batteryAvailable)
            return I18n.tr("No battery", "battery status");
        if (stateKnownBatteries.length === 0 || (isCharging && !stateKnownBatteries.some(b => b.changeRate > 0)))
            return isCharging ? I18n.tr("Charging", "battery status") : (isPluggedIn ? I18n.tr("Plugged in", "battery status") : I18n.tr("Discharging", "battery status"));
        const states = stateKnownBatteries.map(b => b.state);
        if (states.every(s => s === states[0]))
            return translateBatteryState(states[0]);
        return isCharging ? I18n.tr("Charging", "battery status") : (isPluggedIn ? I18n.tr("Plugged in", "battery status") : I18n.tr("Discharging", "battery status"));
    }

    function _hasUsableCharge(dev) {
        if (!dev || !dev.ready)
            return false;
        return dev.percentage > 0 || (dev.energy > 0 && dev.energyCapacity > 0);
    }

    function _devicePercent(dev) {
        if (!dev)
            return 0;
        if (dev.percentage > 0)
            return Math.min(100, Math.round(dev.percentage * 100));
        if (dev.energy > 0 && dev.energyCapacity > 0)
            return Math.min(100, Math.round(dev.energy * 100 / dev.energyCapacity));
        return 0;
    }

    // One battery: its charge. Several: UPower's display device, else the
    // energy-weighted (or plain) average.
    function _chargePercent() {
        if (usePreferred)
            return _hasUsableCharge(preferredDevice) ? _devicePercent(preferredDevice) : 0;
        if (batteries.length > 1 && _hasUsableCharge(UPower.displayDevice))
            return _devicePercent(UPower.displayDevice);
        if (chargeBatteries.length === 1)
            return _devicePercent(chargeBatteries[0]);
        if (chargeBatteries.length > 1) {
            const packs = chargeBatteries.filter(b => b.energy > 0 && b.energyCapacity > 0);
            const cap = packs.reduce((sum, b) => sum + b.energyCapacity, 0);
            if (packs.length === chargeBatteries.length && cap > 0)
                return Math.min(100, Math.round(packs.reduce((sum, b) => sum + b.energy, 0) * 100 / cap));
            return Math.min(100, Math.round(chargeBatteries.reduce((sum, b) => sum + _devicePercent(b), 0) / chargeBatteries.length));
        }
        return _hasUsableCharge(UPower.displayDevice) ? _devicePercent(UPower.displayDevice) : 0;
    }

    function translateBatteryState(state) {
        switch (state) {
        case UPowerDeviceState.Charging:
            return I18n.tr("Charging", "battery status");
        case UPowerDeviceState.Discharging:
            return I18n.tr("Discharging", "battery status");
        case UPowerDeviceState.Empty:
            return I18n.tr("Empty", "battery status");
        case UPowerDeviceState.FullyCharged:
            return I18n.tr("Fully Charged", "battery status");
        case UPowerDeviceState.PendingCharge:
            return I18n.tr("Pending Charge", "battery status");
        case UPowerDeviceState.PendingDischarge:
            return I18n.tr("Pending Discharge", "battery status");
        default:
            return I18n.tr("Unknown", "battery status");
        }
    }

    // Seconds until full while charging, until empty otherwise; 0 when
    // unknown or over a day.
    function estimatedSeconds() {
        if (!batteryAvailable || changeRate <= 0)
            return 0;
        const hours = isCharging ? (batteryCapacity - batteryEnergy) / changeRate : batteryEnergy / changeRate;
        const seconds = Math.abs(hours * 3600);
        return seconds > 0 && seconds <= 86400 ? seconds : 0;
    }

    function formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return hours > 0 ? I18n.tr("%1h %2m", "battery time remaining").arg(hours).arg(minutes) : I18n.tr("%1m", "battery time remaining").arg(minutes);
    }

    function formatTimeRemaining() {
        const seconds = estimatedSeconds();
        return seconds ? formatDuration(seconds) : "Unknown";
    }

    function getBatteryIcon() {
        if (!batteryAvailable)
            return "power";
        if (isCharging || isPluggedIn) {
            if (batteryLevel >= 90)
                return "battery_charging_full";
            if (batteryLevel >= 80)
                return "battery_charging_90";
            if (batteryLevel >= 60)
                return "battery_charging_80";
            if (batteryLevel >= 50)
                return "battery_charging_60";
            if (batteryLevel >= 30)
                return "battery_charging_50";
            if (batteryLevel >= 20)
                return "battery_charging_30";
            return "battery_charging_20";
        }
        if (batteryLevel >= 95)
            return "battery_full";
        if (batteryLevel >= 85)
            return "battery_6_bar";
        if (batteryLevel >= 70)
            return "battery_5_bar";
        if (batteryLevel >= 55)
            return "battery_4_bar";
        if (batteryLevel >= 40)
            return "battery_3_bar";
        if (batteryLevel >= 25)
            return "battery_2_bar";
        return "battery_1_bar";
    }
}
