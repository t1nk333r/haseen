import QtQuick
import qs.Haseen
import "Model.js" as Model

// Adapted from PanelHorizon.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem Sayed); see
// LICENSE and UPSTREAM.md beside this file. Ported to qs.Haseen: `host` is
// the haseen.prayers service, Theme supplies colours and sizes.

Column {
  id: horizonRoot

  property var host
  readonly property var firstSegment: host.daySegments.length > 0 ? host.daySegments[0] : null
  readonly property var longestSegment: {
    var longest = null
    for (var i = 0; i < host.daySegments.length; i++) {
      if (!longest || host.daySegments[i].length > longest.length)
        longest = host.daySegments[i]
    }
    return longest
  }
  readonly property real cycleMinutes: firstSegment
    ? firstSegment.start + host.dayFraction * 1440
    : 0
  readonly property var fajrTiming: Model.timing(host.todayDay, "Fajr")
  // The next prayer's iqama, wherever that prayer falls: built from its own
  // clock rather than today's timings, so a "· TOMORROW" prayer is right too.
  // Friday's hour of answered supplication, shown under the Maghrib it
  // precedes (the table row below reads it from the same helper).
  readonly property var istijabah: host.istijabahEnabled
    ? Model.istijabahTime(host.todayDay, host.istijabahLead)
    : null

  readonly property var heroIqama: host.nextPrayer
    ? Model.iqamaValue({ time: host.nextPrayer.time, at: host.nextPrayer.at },
        (host.iqamaOffsets || {})[host.nextPrayer.name])
    : null
  readonly property string heroIqamaLabel: host.nextPrayer
    && host.nextPrayer.name === "Dhuhr" && Model.isFriday({ date: host.nextPrayer.date })
    ? "jumuah" : "iqama"

  readonly property real nightNowFraction: {
    if (!firstSegment || host.nightBand === null) return -1
    if (cycleMinutes < host.nightBand.start || cycleMinutes > host.nightBand.end) return -1
    return Math.max(0, Math.min(1,
      (cycleMinutes - host.nightBand.start) / host.nightBand.span
    ))
  }

  width: parent ? parent.width : 0
  spacing: horizonRoot.host.sp(9)

  // Fraction-based x positions do not inherit LayoutMirroring, so mirror them here.
  function place(fraction, itemWidth) {
    return host.isArabic ? width - fraction * width - itemWidth : fraction * width
  }

  function containsNow(segment) {
    return firstSegment !== null && cycleMinutes >= segment.start && cycleMinutes < segment.end
  }

  function isPast(segment) {
    return firstSegment !== null && segment.end <= cycleMinutes
  }

  component NightLabel: Row {
    required property string markerName
    required property bool includeClock
    readonly property var markerTiming: Model.timing(horizonRoot.host.todayDay, markerName)

    spacing: horizonRoot.host.sp(4)

    Text {
      textFormat: Text.PlainText
      text: Model.label(parent.markerName, horizonRoot.host.language)
      color: horizonRoot.host.faint
      font.family: horizonRoot.host.nameFontFamily
      font.pixelSize: horizonRoot.host.fCaption
    }

    Text {
      textFormat: Text.PlainText
      visible: parent.includeClock && parent.markerTiming !== null
      text: parent.markerTiming
        ? Model.formatClock(parent.markerTiming.time, horizonRoot.host.timeFormat)
        : ""
      color: horizonRoot.host.faint
      font.family: horizonRoot.host.fontFamily
      font.pixelSize: horizonRoot.host.fCaption
    }
  }

  Item {
    width: parent.width
    height: Math.max(heroLead.implicitHeight, countdownText.implicitHeight)

    Column {
      id: heroLead
      anchors.left: parent.left
      anchors.right: countdownText.left
      anchors.rightMargin: horizonRoot.host.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: horizonRoot.host.sp(3)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: {
          var label = host.isArabic ? "التالي" : "NEXT"
          if (host.nextPrayer && host.todayDay
              && host.nextPrayer.date !== host.todayDay.date)
            label += host.isArabic ? " غدًا" : " · TOMORROW"
          return label
        }
        color: host.faint
        font.family: host.nameFontFamily
        font.pixelSize: horizonRoot.host.fCaption
        font.letterSpacing: 1.5
        elide: Text.ElideRight
      }

      Row {
        width: parent.width
        spacing: horizonRoot.host.sp(8)

        Text {
          textFormat: Text.PlainText
          id: heroPrayerName
          width: Math.min(implicitWidth,
            parent.width - heroClock.implicitWidth - parent.spacing)
          text: host.nextPrayer
            ? Model.label(host.nextPrayer.name, host.language)
            : (host.isArabic ? "مواقيت الصلاة" : "Prayers")
          color: host.foreground
          font.family: host.nameFontFamily
          font.pixelSize: horizonRoot.host.fTitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          id: heroClock
          text: host.nextPrayer
            ? Model.formatClock(host.nextPrayer.time, host.timeFormat)
            : ""
          color: host.dim
          font.family: host.fontFamily
          font.pixelSize: horizonRoot.host.fBody
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: horizonRoot.heroIqama !== null
        width: parent.width
        text: horizonRoot.heroIqama
          ? Model.uiLabel(horizonRoot.heroIqamaLabel, host.language) + " "
            + Model.formatClock(horizonRoot.heroIqama.time, host.timeFormat)
          : ""
        color: host.faint
        font.family: host.nameFontFamily
        font.pixelSize: horizonRoot.host.fCaption
        elide: Text.ElideRight
      }
    }

    Text {
      textFormat: Text.PlainText
      id: countdownText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: host.nextPrayer
        ? Model.remaining(host.nextPrayer, host.nowTick, host.language)
        : ""
      color: Theme.accent
      font.family: host.nameFontFamily
      font.pixelSize: horizonRoot.host.fDisplay
      font.bold: true
    }
  }

  Rectangle {
    id: dayStrip

    visible: host.daySegments.length > 0
    width: parent.width
    height: horizonRoot.host.sp(38)
    radius: Theme.radius
    color: horizonRoot.host.alpha(host.foreground, 0)
    border.width: 1
    border.color: horizonRoot.host.alpha(host.foreground, 0.15)
    clip: true

    Repeater {
      model: host.daySegments

      Rectangle {
        id: stripSegment

        required property var modelData
        readonly property bool isNight: modelData.name === "Maghrib"
          || modelData.name === "Isha"
        readonly property bool isCurrent: horizonRoot.containsNow(modelData)

        x: horizonRoot.firstSegment ? horizonRoot.place(
          (modelData.start - horizonRoot.firstSegment.start) / 1440, width
        ) : 0
        width: dayStrip.width * modelData.length / 1440
        height: dayStrip.height
        color: isCurrent
          ? horizonRoot.host.alpha(Theme.accent, 0.16)
          : (isNight
            ? horizonRoot.host.alpha(host.foreground, 0.11)
            : horizonRoot.host.alpha(host.foreground, 0.06))

        Canvas {
          anchors.fill: parent
          visible: stripSegment.isNight

          property color hatchColor: horizonRoot.host.alpha(host.foreground, 0.14)
          property real step: horizonRoot.host.sp(6)

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = hatchColor
            ctx.lineWidth = 1
            for (var lineX = -height; lineX < width; lineX += step) {
              ctx.beginPath()
              ctx.moveTo(lineX, height)
              ctx.lineTo(lineX + height, 0)
              ctx.stroke()
            }
          }
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onHatchColorChanged: requestPaint()
        }

        Rectangle {
          anchors.left: parent.left
          width: 1
          height: parent.height
          color: horizonRoot.host.alpha(host.foreground, 0.16)
        }

        Text {
          textFormat: Text.PlainText
          visible: stripSegment.width > horizonRoot.host.sp(host.isArabic ? 52 : 46)
          anchors.left: parent.left
          anchors.leftMargin: horizonRoot.host.sp(5)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - horizonRoot.host.sp(10)
          text: {
            var value = Model.label(stripSegment.modelData.name, host.language)
            return host.isArabic ? value : value.toUpperCase()
          }
          color: stripSegment.isCurrent ? host.foreground : host.dim
          font.family: host.nameFontFamily
          font.pixelSize: horizonRoot.host.fCaption
          font.bold: stripSegment.isCurrent
          elide: Text.ElideRight
        }
      }
    }

    Rectangle {
      id: dayNeedle

      x: horizonRoot.place(host.dayFraction, width)
      width: horizonRoot.host.sp(2)
      height: parent.height
      color: Theme.accent

      Behavior on x {
        NumberAnimation { duration: 400 }
      }

      Rectangle {
        anchors.top: parent.top
        anchors.topMargin: -horizonRoot.host.sp(3)
        anchors.horizontalCenter: parent.horizontalCenter
        width: horizonRoot.host.sp(6)
        height: horizonRoot.host.sp(6)
        color: Theme.accent
        rotation: 45
      }
    }
  }

  Item {
    visible: host.daySegments.length > 0
    width: parent.width
    height: visible ? Math.max(scaleStart.implicitHeight, scaleTitle.implicitHeight) : 0

    Text {
      textFormat: Text.PlainText
      id: scaleStart
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: horizonRoot.fajrTiming
        ? Model.formatClock(horizonRoot.fajrTiming.time, host.timeFormat)
        : ""
      color: host.faint
      font.family: host.fontFamily
      font.pixelSize: horizonRoot.host.fCaption
    }

    Text {
      textFormat: Text.PlainText
      id: scaleTitle
      anchors.centerIn: parent
      text: host.isArabic ? "طول النوافذ" : "WINDOW LENGTHS"
      color: host.faint
      font.family: host.nameFontFamily
      font.pixelSize: horizonRoot.host.fCaption
      font.letterSpacing: 1.1
    }

    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: scaleStart.text
      color: host.faint
      font.family: host.fontFamily
      font.pixelSize: horizonRoot.host.fCaption
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: host.statusMessage !== ""
    width: parent.width
    text: host.statusMessage
    color: host.lastError !== "" && !host.schedule ? host.urgent : host.faint
    font.family: host.fontFamily
    font.pixelSize: horizonRoot.host.fBodySmall
    wrapMode: Text.WordWrap
  }

  Rectangle {
    visible: host.daySegments.length > 0
    width: parent.width
    height: horizonRoot.host.hairline
    color: horizonRoot.host.alpha(host.foreground, 0.16)
  }

  Column {
    id: dayTable

    visible: host.daySegments.length > 0
    width: parent.width
    spacing: 0

    Repeater {
      model: host.daySegments

      Item {
        id: tableRow

        required property var modelData
        readonly property bool isCurrent: horizonRoot.containsNow(modelData)
        readonly property bool isNext: host.nextPrayer !== null && host.todayDay !== null
          && host.nextPrayer.name === modelData.name
          && host.nextPrayer.date === host.todayDay.date
        readonly property bool past: horizonRoot.isPast(modelData)
        readonly property var imsakTiming: modelData.name === "Fajr"
          ? Model.timing(host.todayDay, "Imsak")
          : null
        readonly property color tone: isNext ? Theme.accent
          : (isCurrent ? host.foreground : (past ? host.faint : host.foreground))

        readonly property var iqama: Model.iqamaFor(host.todayDay, modelData.name, host.iqamaOffsets)

        readonly property var istijabahCaption: modelData.name === "Maghrib"
          && horizonRoot.istijabah !== null ? horizonRoot.istijabah : null

        width: dayTable.width
        height: Math.max(horizonRoot.host.sp(23),
          tableClock.implicitHeight
            + (iqama !== null ? tableIqama.implicitHeight : 0)
            + (istijabahCaption !== null ? tableIstijabah.implicitHeight : 0)
            + horizonRoot.host.sp(9)
            + (iqama !== null && istijabahCaption !== null ? horizonRoot.host.sp(3) : 0))

        Item {
          id: tableNameSlot
          anchors.left: parent.left
          anchors.right: tableClock.left
          anchors.rightMargin: horizonRoot.host.sp(8)
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          Text {
            textFormat: Text.PlainText
            id: tableName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - (imsakName.visible
              ? imsakName.implicitWidth + imsakClock.implicitWidth + horizonRoot.host.sp(8)
              : 0))
            text: Model.label(tableRow.modelData.name, host.language)
            color: tableRow.tone
            font.family: host.nameFontFamily
            font.pixelSize: horizonRoot.host.fBodySmall
            font.bold: tableRow.isCurrent || tableRow.isNext
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            id: imsakName
            visible: tableRow.imsakTiming !== null
            anchors.left: tableName.right
            anchors.leftMargin: horizonRoot.host.sp(5)
            anchors.baseline: tableName.baseline
            text: host.isArabic ? "إمساك" : "imsak"
            color: host.faint
            font.family: host.nameFontFamily
            font.pixelSize: horizonRoot.host.fCaption
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            id: imsakClock
            visible: tableRow.imsakTiming !== null
            anchors.left: imsakName.right
            anchors.leftMargin: horizonRoot.host.sp(3)
            anchors.baseline: tableName.baseline
            text: tableRow.imsakTiming
              ? Model.formatClock(tableRow.imsakTiming.time, host.timeFormat)
              : ""
            color: host.faint
            font.family: host.fontFamily
            font.pixelSize: horizonRoot.host.fCaption
          }
        }

        Text {
          textFormat: Text.PlainText
          id: tableClock
          anchors.right: windowSlot.left
          anchors.rightMargin: horizonRoot.host.sp(9)
          anchors.verticalCenter: parent.verticalCenter
          width: horizonRoot.host.sp(54)
          text: Model.formatClock(tableRow.modelData.value.time, host.timeFormat)
          color: tableRow.tone
          font.family: host.fontFamily
          font.pixelSize: horizonRoot.host.fBodySmall
          font.bold: tableRow.isCurrent || tableRow.isNext
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenterOffset: {
            var below = (tableRow.iqama !== null ? tableIqama.implicitHeight : 0)
              + (tableRow.istijabahCaption !== null ? tableIstijabah.implicitHeight : 0)
              + (tableRow.iqama !== null && tableRow.istijabahCaption !== null ? horizonRoot.host.sp(3) : 0)
            return below > 0 ? -Math.round(below / 2) : 0
          }
        }

        Text {
          textFormat: Text.PlainText
          id: tableIstijabah
          visible: tableRow.istijabahCaption !== null
          anchors.right: tableClock.right
          anchors.top: tableIqama.visible ? tableIqama.bottom : tableClock.bottom
          anchors.topMargin: horizonRoot.host.sp(1)
          text: tableRow.istijabahCaption
            ? Model.uiLabel("istijabah", host.language) + " "
              + Model.formatClock(tableRow.istijabahCaption.time, host.timeFormat)
            : ""
          color: host.faint
          font.family: host.nameFontFamily
          font.pixelSize: horizonRoot.host.fCaption
        }

        Text {
          textFormat: Text.PlainText
          id: tableIqama
          visible: tableRow.iqama !== null
          anchors.right: tableClock.right
          anchors.top: tableClock.bottom
          anchors.topMargin: horizonRoot.host.sp(1)
          text: tableRow.iqama
            ? Model.uiLabel(tableRow.iqama.label || "iqama", host.language) + " "
              + Model.formatClock(tableRow.iqama.time, host.timeFormat)
            : ""
          color: host.faint
          font.family: host.fontFamily
          font.pixelSize: horizonRoot.host.fCaption
        }

        Item {
          id: windowSlot
          anchors.right: tableDuration.left
          anchors.rightMargin: horizonRoot.host.sp(9)
          anchors.verticalCenter: parent.verticalCenter
          width: tableRow.width * 0.22
          height: horizonRoot.host.sp(3)

          Rectangle {
            anchors.fill: parent
            radius: 2
            color: horizonRoot.host.alpha(host.foreground, 0.13)

            Rectangle {
              width: horizonRoot.longestSegment
                ? parent.width * tableRow.modelData.length / horizonRoot.longestSegment.length
                : 0
              height: parent.height
              radius: 2
              color: tableRow.isCurrent
                ? Theme.accent
                : horizonRoot.host.alpha(host.foreground, 0.42)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          id: tableDuration
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: horizonRoot.host.sp(58)
          text: Model.windowLabel(tableRow.modelData, host.language)
          color: host.faint
          font.family: host.nameFontFamily
          font.pixelSize: horizonRoot.host.fCaption
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideNone
        }
      }
    }
  }

  Column {
    visible: host.daySegments.length > 0 && host.nightBand !== null
    width: parent.width
    spacing: horizonRoot.host.sp(4)

    Rectangle {
      id: nightBand

      width: parent.width
      height: horizonRoot.host.sp(15)
      radius: Theme.radius
      color: horizonRoot.host.alpha(host.foreground, 0.06)
      border.width: 1
      border.color: horizonRoot.host.alpha(host.foreground, 0.15)
      clip: true

      Canvas {
        anchors.fill: parent

        property color hatchColor: horizonRoot.host.alpha(host.foreground, 0.14)
        property real step: horizonRoot.host.sp(6)

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = hatchColor
          ctx.lineWidth = 1
          for (var lineX = -height; lineX < width; lineX += step) {
            ctx.beginPath()
            ctx.moveTo(lineX, height)
            ctx.lineTo(lineX + height, 0)
            ctx.stroke()
          }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onHatchColorChanged: requestPaint()
      }

      Repeater {
        model: host.nightBand ? host.nightBand.marks : []

        Rectangle {
          required property var modelData

          x: horizonRoot.place(modelData.fraction, width)
          width: 1
          height: nightBand.height
          color: horizonRoot.host.alpha(host.foreground, 0.45)
        }
      }

      Rectangle {
        visible: horizonRoot.nightNowFraction >= 0
        x: horizonRoot.place(horizonRoot.nightNowFraction, width)
        width: horizonRoot.host.sp(2)
        height: parent.height
        color: Theme.accent
      }
    }

    Row {
      id: nightLabels

      readonly property real fillerWidth: Math.max(0, (width
        - maghribLabel.implicitWidth - firstThirdLabel.implicitWidth
        - lastThirdLabel.implicitWidth - fajrLabel.implicitWidth) / 3)

      width: parent.width
      spacing: 0

      NightLabel {
        id: maghribLabel
        markerName: "Maghrib"
        includeClock: false
      }

      Item { width: nightLabels.fillerWidth; height: 1 }

      NightLabel {
        id: firstThirdLabel
        markerName: "Firstthird"
        includeClock: true
      }

      Item { width: nightLabels.fillerWidth; height: 1 }

      NightLabel {
        id: lastThirdLabel
        markerName: "Lastthird"
        includeClock: true
      }

      Item { width: nightLabels.fillerWidth; height: 1 }

      NightLabel {
        id: fajrLabel
        markerName: "Fajr"
        includeClock: false
      }
    }
  }

  Rectangle {
    width: parent.width
    height: horizonRoot.host.hairline
    color: horizonRoot.host.alpha(host.foreground, 0.16)
  }

  PanelDisplay {
    host: horizonRoot.host
  }
}
