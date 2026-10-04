import QtQuick
import qs.Haseen
import "Model.js" as Model

// Adapted from PanelCompact.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem Sayed); see
// LICENSE and UPSTREAM.md beside this file. Ported to qs.Haseen: `host` is
// the haseen.prayers service, Theme supplies colours and sizes.

Column {
  id: compactRoot

  property var host
  readonly property string leaderDots: "························································································································"

  width: parent ? parent.width : 0
  spacing: compactRoot.host.sp(10)

  Rectangle {
    width: parent.width
    height: compactRoot.host.hairline * 2
    color: compactRoot.host.alpha(host.foreground, 0.10)

    Rectangle {
      anchors.left: parent.left
      width: parent.width * host.dayFraction
      height: parent.height
      color: Theme.accent
      opacity: 0.85

      Behavior on width {
        NumberAnimation { duration: 400 }
      }
    }
  }

  Item {
    width: parent.width
    height: Math.max(locationText.implicitHeight, shortDateText.implicitHeight)

    Text {
      textFormat: Text.PlainText
      id: locationText
      anchors.left: parent.left
      anchors.right: shortDateText.left
      anchors.rightMargin: compactRoot.host.sp(10)
      anchors.baseline: shortDateText.baseline
      text: host.isArabic ? host.displayLocation : host.displayLocation.toUpperCase()
      color: host.foreground
      font.family: host.nameFontFamily
      font.pixelSize: compactRoot.host.fBodySmall
      font.bold: true
      font.letterSpacing: 1.4
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      id: shortDateText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!host.todayDay || !host.todayDay.date) return ""
        var parts = String(host.todayDay.date).split("-")
        if (parts.length < 3) return ""
        var stamp = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        if (isNaN(stamp.getTime())) return ""
        var formatted = stamp.toLocaleDateString(
          Qt.locale(host.isArabic ? "ar_EG" : "en_US"), "ddd d MMM"
        )
        formatted = Model.latinDigits(formatted)
        return host.isArabic ? formatted : formatted.toUpperCase()
      }
      color: host.faint
      font.family: host.nameFontFamily
      font.pixelSize: compactRoot.host.fCaption
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: host.hijriText !== ""
    width: parent.width
    text: host.hijriText
    color: host.faint
    font.family: host.nameFontFamily
    font.pixelSize: compactRoot.host.fCaption
    elide: Text.ElideRight
  }

  Item {
    width: parent.width
    height: compactRoot.host.sp(3)

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: compactRoot.host.hairline
      color: compactRoot.host.alpha(host.foreground, 0.42)
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: compactRoot.host.hairline
      color: compactRoot.host.alpha(host.foreground, 0.16)
    }
  }

  Column {
    visible: host.prayerRows.length > 0
    width: parent.width
    spacing: 0

    Repeater {
      model: host.prayerRows

      Item {
        id: prayerRow

        required property var modelData
        readonly property bool isNext: host.nextPrayer !== null && host.todayDay !== null
          && host.nextPrayer.name === modelData.name
          && host.nextPrayer.date === host.todayDay.date
        readonly property bool isCurrent: !isNext && host.currentPrayer !== null && host.todayDay !== null
          && host.currentPrayer.name === modelData.name
          && host.currentPrayer.date === host.todayDay.date
        readonly property double prayerEpoch: new Date(modelData.value.at).getTime()
        readonly property bool isPast: !isNext && !isCurrent && isFinite(prayerEpoch)
          && prayerEpoch <= host.nowTick.getTime()
        readonly property color tone: isNext ? Theme.accent
          : (isPast ? host.faint : host.foreground)

        readonly property bool hasIqama: modelData.iqama !== null && modelData.iqama !== undefined
        // Content-derived, not a fixed caption offset: at a larger font or UI
        // scale a fixed 38px row let the iqama line crowd the row beneath.
        readonly property real rowHeight: hasIqama
          ? prayerTime.implicitHeight + prayerIqama.implicitHeight + compactRoot.host.sp(11)
          : compactRoot.host.sp(25)

        width: parent.width
        height: Math.max(compactRoot.host.sp(25), rowHeight)

        Item {
          id: prayerGutter
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: compactRoot.host.sp(13)

          Rectangle {
            visible: prayerRow.isCurrent
            anchors.centerIn: parent
            width: compactRoot.host.sp(5)
            height: compactRoot.host.sp(5)
            color: host.foreground
          }

          Rectangle {
            visible: prayerRow.isNext
            anchors.centerIn: parent
            width: compactRoot.host.sp(2)
            height: compactRoot.host.sp(13)
            color: Theme.accent
          }
        }

        Text {
          textFormat: Text.PlainText
          id: prayerName
          anchors.left: prayerGutter.right
          anchors.baseline: prayerTime.baseline
          width: Math.min(implicitWidth, prayerRow.width * 0.34)
          text: Model.label(prayerRow.modelData.name, host.language)
          color: prayerRow.tone
          font.family: host.nameFontFamily
          font.pixelSize: compactRoot.host.fBody
          font.bold: prayerRow.isNext
          elide: Text.ElideRight
        }

        Item {
          anchors.left: prayerName.right
          anchors.leftMargin: compactRoot.host.sp(4)
          anchors.right: prayerTime.left
          anchors.rightMargin: compactRoot.host.sp(4)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          clip: true

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: compactRoot.host.sp(4)
            text: compactRoot.leaderDots
            color: prayerRow.isNext
              ? compactRoot.host.alpha(Theme.accent, 0.45)
              : compactRoot.host.alpha(host.foreground, 0.34)
            font.family: host.fontFamily
            font.pixelSize: compactRoot.host.fCaption
            wrapMode: Text.NoWrap
          }
        }

        Text {
          textFormat: Text.PlainText
          id: prayerTime
          anchors.right: countdownChip.visible ? countdownChip.left : parent.right
          anchors.rightMargin: countdownChip.visible ? compactRoot.host.sp(5) : 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: prayerRow.hasIqama
            ? -Math.round(prayerIqama.implicitHeight / 2) : 0
          text: Model.formatClock(prayerRow.modelData.value.time, host.timeFormat)
          color: prayerRow.tone
          font.family: host.fontFamily
          font.pixelSize: compactRoot.host.fBody
          font.bold: prayerRow.isNext
        }

        // The congregational start, under the adhan it follows. Derived from
        // the schedule (see Model.iqamaValue), never stored, so it moves with
        // the prayer times every day.
        Text {
          textFormat: Text.PlainText
          id: prayerIqama
          visible: prayerRow.hasIqama
          // Right-aligned to the time, not to the row: the next prayer's card
          // also carries the countdown chip on the row's right edge, and the
          // caption under the time used to run into it.
          anchors.right: prayerTime.right
          anchors.top: prayerTime.bottom
          anchors.topMargin: compactRoot.host.sp(1)
          // Sunrise has no iqama: the caption is hidden, but its binding still runs.
          text: prayerRow.hasIqama
            ? Model.uiLabel(prayerRow.modelData.iqama.label || "iqama", host.language) + " "
              + Model.formatClock(prayerRow.modelData.iqama.time, host.timeFormat)
            : ""
          color: host.faint
          font.family: host.fontFamily
          font.pixelSize: compactRoot.host.fCaption
        }

        Rectangle {
          id: countdownChip
          visible: prayerRow.isNext
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: countdownText.implicitWidth + compactRoot.host.sp(8)
          height: compactRoot.host.sp(18)
          radius: Theme.radius
          color: compactRoot.host.alpha(Theme.accent, 0.17)

          Text {
            textFormat: Text.PlainText
            id: countdownText
            anchors.centerIn: parent
            text: Model.remaining(host.nextPrayer, host.nowTick, host.language)
            color: Theme.accent
            font.family: host.nameFontFamily
            font.pixelSize: compactRoot.host.fCaption
            font.bold: true
          }
        }
      }
    }
  }

  Item {
    id: tomorrowRow

    visible: host.tomorrowPrayerText !== ""
    width: parent.width
    height: visible ? compactRoot.host.sp(25) : 0

    Item {
      id: tomorrowGutter
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: compactRoot.host.sp(13)

      Rectangle {
        anchors.centerIn: parent
        width: compactRoot.host.sp(2)
        height: compactRoot.host.sp(13)
        color: Theme.accent
      }
    }

    Text {
      textFormat: Text.PlainText
      id: tomorrowTag
      anchors.left: tomorrowGutter.right
      anchors.baseline: tomorrowTime.baseline
      text: host.isArabic ? "غدًا" : "TOMORROW"
      color: Theme.accent
      font.family: host.nameFontFamily
      font.pixelSize: compactRoot.host.fCaption
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      id: tomorrowName
      anchors.left: tomorrowTag.right
      anchors.leftMargin: compactRoot.host.sp(6)
      anchors.baseline: tomorrowTime.baseline
      width: Math.min(implicitWidth, tomorrowRow.width * 0.25)
      text: host.nextPrayer ? Model.label(host.nextPrayer.name, host.language) : ""
      color: Theme.accent
      font.family: host.nameFontFamily
      font.pixelSize: compactRoot.host.fBodySmall
      font.bold: true
      elide: Text.ElideRight
    }

    Item {
      anchors.left: tomorrowName.right
      anchors.leftMargin: compactRoot.host.sp(4)
      anchors.right: tomorrowTime.left
      anchors.rightMargin: compactRoot.host.sp(4)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      clip: true

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: compactRoot.host.sp(4)
        text: compactRoot.leaderDots
        color: compactRoot.host.alpha(Theme.accent, 0.45)
        font.family: host.fontFamily
        font.pixelSize: compactRoot.host.fCaption
        wrapMode: Text.NoWrap
      }
    }

    Text {
      textFormat: Text.PlainText
      id: tomorrowTime
      anchors.right: tomorrowCountdown.left
      anchors.rightMargin: compactRoot.host.sp(5)
      anchors.verticalCenter: parent.verticalCenter
      text: host.nextPrayer ? Model.formatClock(host.nextPrayer.time, host.timeFormat) : ""
      color: Theme.accent
      font.family: host.fontFamily
      font.pixelSize: compactRoot.host.fBodySmall
      font.bold: true
    }

    Rectangle {
      id: tomorrowCountdown
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: tomorrowCountdownText.implicitWidth + compactRoot.host.sp(8)
      height: compactRoot.host.sp(18)
      radius: Theme.radius
      color: compactRoot.host.alpha(Theme.accent, 0.17)

      Text {
        textFormat: Text.PlainText
        id: tomorrowCountdownText
        anchors.centerIn: parent
        text: host.nextPrayer
          ? Model.remaining(host.nextPrayer, host.nowTick, host.language)
          : ""
        color: Theme.accent
        font.family: host.nameFontFamily
        font.pixelSize: compactRoot.host.fCaption
        font.bold: true
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: host.statusMessage !== ""
    width: parent.width
    text: host.statusMessage
    color: host.lastError !== "" && !host.schedule ? host.urgent : host.faint
    font.family: host.fontFamily
    font.pixelSize: compactRoot.host.fBodySmall
    wrapMode: Text.WordWrap
  }

  Rectangle {
    visible: host.nightRows.length > 0
    width: parent.width
    height: compactRoot.host.hairline
    color: compactRoot.host.alpha(host.foreground, 0.16)
  }

  Grid {
    id: nightGrid

    visible: host.nightRows.length > 0
    width: parent.width
    columns: 2
    columnSpacing: compactRoot.host.sp(14)
    rowSpacing: compactRoot.host.sp(5)

    Repeater {
      model: host.nightRows

      Item {
        id: nightCell

        required property var modelData

        width: (nightGrid.width - nightGrid.columnSpacing) / 2
        height: Math.max(nightName.implicitHeight, nightTime.implicitHeight)

        Text {
          textFormat: Text.PlainText
          id: nightName
          anchors.left: parent.left
          anchors.right: nightTime.left
          anchors.rightMargin: compactRoot.host.sp(5)
          anchors.baseline: nightTime.baseline
          text: Model.label(nightCell.modelData.name, host.language)
          color: host.faint
          font.family: host.nameFontFamily
          font.pixelSize: compactRoot.host.fCaption
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          id: nightTime
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Model.formatClock(nightCell.modelData.value.time, host.timeFormat)
          color: host.faint
          font.family: host.fontFamily
          font.pixelSize: compactRoot.host.fCaption
        }
      }
    }
  }

  Rectangle {
    width: parent.width
    height: compactRoot.host.hairline
    color: compactRoot.host.alpha(host.foreground, 0.16)
  }

  PanelDisplay {
    host: compactRoot.host
  }
}
