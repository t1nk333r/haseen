import QtQuick
import qs.Haseen
import "Model.js" as Model

// Adapted from PanelDisplay.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem Sayed); see
// LICENSE and UPSTREAM.md beside this file. Ported to qs.Haseen: `host` is
// the haseen.prayers service, Theme supplies colours and sizes.

// The panel footer and the display controls that fold out of it. Both layouts
// end with this element, so the settings read and behave identically in Horizon
// and Compact.
//
// Every control writes through host.persistSettings(), which applies the value
// to the running shell and writes it to ~/.config/haseen/shell.json on the
// same click. Calculation changes also feed host.configKey, so the local engine
// recomputes after the same short debounce used by location commits.
Column {
  id: displayRoot

  property var host
  property bool editingTune: false
  readonly property var currentTuneValues: Model.tuneValues(host.tune)
  readonly property string currentTuneSummary: Model.tuneSummary(
    currentTuneValues, host.language
  )
  readonly property bool hasEditableTune: {
    for (var i = 0; i < Model.TUNE_EDITABLE.length; i++) {
      var index = Model.TUNE_ORDER.indexOf(Model.TUNE_EDITABLE[i])
      if (currentTuneValues[index] !== 0) return true
    }
    return false
  }

  width: parent ? parent.width : 0
  spacing: displayRoot.host.sp(9)

  // Cycle buttons name their *next* value rather than their current one, so the
  // tooltip answers "what does clicking this do" instead of restating the panel.
  function nextTip(ring, current) {
    return Model.uiLabel("nextTip", host.language) + " "
      + Model.optionLabel(Model.nextInRing(ring, current), host.language)
  }

  function writeTune(name, value) {
    var values = Model.tuneValues(host.tune)
    var index = Model.TUNE_ORDER.indexOf(name)
    if (index < 0) return
    values[index] = value
    host.setSetting("tune", Model.tuneText(values))
  }

  function resetEditableTune() {
    var values = Model.tuneValues(host.tune)
    for (var i = 0; i < Model.TUNE_EDITABLE.length; i++) {
      var index = Model.TUNE_ORDER.indexOf(Model.TUNE_EDITABLE[i])
      values[index] = 0
    }
    host.setSetting("tune", Model.tuneText(values))
  }

  function tuneFieldFocused() {
    for (var i = 0; i < tuneRepeater.count; i++) {
      var item = tuneRepeater.itemAt(i)
      if (item && item.fieldFocused) return true
    }
    return false
  }

  function syncCalculationFocus() {
    host.keysBlocked = methodPicker.popupOpen
      || (editingTune && tuneFieldFocused())
  }

  function finishTuneEditing() {
    editingTune = false
    for (var i = 0; i < tuneRepeater.count; i++) {
      var item = tuneRepeater.itemAt(i)
      if (item) item.clearFocus()
    }
    syncCalculationFocus()
  }

  function closeCalculationEditors() {
    methodPicker.close()
    finishTuneEditing()
    host.keysBlocked = false
  }

  Connections {
    target: displayRoot.host

    function onMethodPickerRequested() {
      Qt.callLater(function() { methodPicker.open() })
    }

    function onDisplaySettingsOpenChanged() {
      if (!displayRoot.host.displaySettingsOpen)
        displayRoot.closeCalculationEditors()
    }
  }

  // Footer affordance in the same idiom as the calendar panel's week-start
  // button: a glyph that swaps one setting, with a tooltip for what it means.
  component CycleButton: Rectangle {
    id: cycleButton

    required property string glyph
    required property string tip
    property bool held: false

    signal activated()

    width: displayRoot.host.sp(20)
    height: displayRoot.host.sp(20)
    radius: Theme.radius
    color: cycleMouse.containsMouse || held
      ? displayRoot.host.alpha(displayRoot.host.foreground, 0.13)
      : "transparent"

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: cycleButton.glyph
      color: cycleMouse.containsMouse
        ? Theme.accent
        : (cycleButton.held ? displayRoot.host.foreground : displayRoot.host.faint)
      font.family: displayRoot.host.fontFamily
      font.pixelSize: displayRoot.host.fCaption
    }

    MouseArea {
      id: cycleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cycleButton.activated()
    }

    PrayerToolTip {
      visible: cycleMouse.containsMouse
      text: cycleButton.tip
      fontFamily: displayRoot.host.fontFamily
    }
  }

  // Leading label for a settings row. Kept as its own element rather than a
  // whole row component: a component that wrapped both label and control would
  // need a default property alias, and that would swallow the label too.
  component RowLabel: Text {
    textFormat: Text.PlainText
    color: displayRoot.host.dim
    font.family: displayRoot.host.nameFontFamily
    font.pixelSize: displayRoot.host.fBodySmall
    elide: Text.ElideRight
  }

  component Choice: PrayerChoice {
    foreground: displayRoot.host.foreground
    fontFamily: displayRoot.host.nameFontFamily
    fontSize: displayRoot.host.fCaption
  }

  component SettingSwitch: PrayerSwitch {
    foreground: displayRoot.host.foreground
    trackHeight: displayRoot.host.sp(18)
  }

  Item {
    width: parent.width
    height: Math.max(footerLabel.implicitHeight, footerButtons.implicitHeight)

    Text {
      textFormat: Text.PlainText
      id: footerLabel
      anchors.left: parent.left
      anchors.right: footerButtons.left
      anchors.rightMargin: displayRoot.host.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      text: displayRoot.host.footerText
      color: displayRoot.host.faint
      font.family: displayRoot.host.fontFamily
      font.pixelSize: displayRoot.host.fCaption
      wrapMode: Text.WordWrap
    }

    Row {
      id: footerButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: displayRoot.host.sp(2)

      CycleButton {
        glyph: "\uf0db"
        tip: displayRoot.nextTip(Model.PANEL_STYLES, displayRoot.host.panelStyle)
        onActivated: displayRoot.host.cyclePanelStyle()
      }

      CycleButton {
        glyph: "\uf0c9"
        tip: displayRoot.nextTip(Model.BAR_DISPLAYS, displayRoot.host.barDisplay)
        onActivated: displayRoot.host.cycleBarDisplay()
      }

      CycleButton {
        glyph: "\uf013"
        tip: Model.uiLabel("settingsTip", displayRoot.host.language)
        held: displayRoot.host.displaySettingsOpen
        onActivated: displayRoot.host.toggleDisplaySettings()
      }
    }
  }

  Column {
    id: displaySection

    visible: displayRoot.host.displaySettingsOpen
    width: parent.width
    spacing: displayRoot.host.sp(2)

    Rectangle {
      width: parent.width
      height: displayRoot.host.hairline
      color: displayRoot.host.alpha(displayRoot.host.foreground, 0.16)
    }

    // Location leads the fold because it is the setting a new install most
    // likely needs, and it stays visually apart from the calculation controls
    // whose defaults it may suggest.
    PrayerSectionHeader {
      textFormat: Text.PlainText
      text: Model.uiLabel("location", displayRoot.host.language)
      foreground: displayRoot.host.foreground
      fontFamily: displayRoot.host.nameFontFamily
      bottomPadding: displayRoot.host.sp(3)
    }

    PanelLocation {
      host: displayRoot.host
    }

    Item { width: 1; height: displayRoot.host.sp(6) }

    PrayerSectionHeader {
      textFormat: Text.PlainText
      text: Model.uiLabel("calculation", displayRoot.host.language)
      foreground: displayRoot.host.foreground
      fontFamily: displayRoot.host.nameFontFamily
      bottomPadding: displayRoot.host.sp(3)
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(30), methodPicker.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: methodPicker.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("method", displayRoot.host.language)
      }

      PrayerDropdown {
        searchable: true
        id: methodPicker
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: displayRoot.host.sp(210)
        showLabel: false
        placeholderText: Model.uiLabel("searchMethod", displayRoot.host.language)
        emptyText: Model.uiLabel("noMethod", displayRoot.host.language)
        foreground: displayRoot.host.foreground
        fontFamily: displayRoot.host.nameFontFamily
        options: Model.methodOptions(
          displayRoot.host.language, displayRoot.host.methodSettings
        )
        value: String(displayRoot.host.calculationMethod)
        onChanged: function(next) {
          displayRoot.host.setSetting("calculationMethod", parseInt(next, 10))
        }
        onPopupOpenChanged: displayRoot.syncCalculationFocus()
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), schoolChoice.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: schoolChoice.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("asr", displayRoot.host.language)
      }

      Choice {
        id: schoolChoice
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: Model.optionModel(Model.SCHOOLS, displayRoot.host.language)
        value: displayRoot.host.school === 1 ? "Hanafi" : "Shafi"
        onChanged: function(next) {
          displayRoot.host.setSetting("hanafi", next === "Hanafi")
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(28), tuningActions.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: tuningActions.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("tuning", displayRoot.host.language)
      }

      Row {
        id: tuningActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: displayRoot.host.sp(6)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, displayRoot.host.sp(142))
          text: displayRoot.currentTuneSummary !== ""
            ? displayRoot.currentTuneSummary
            : Model.uiLabel("none", displayRoot.host.language)
          color: displayRoot.host.faint
          font.family: displayRoot.host.nameFontFamily
          font.pixelSize: displayRoot.host.fCaption
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
        }

        PrayerButton {
          visible: !displayRoot.editingTune
          text: Model.uiLabel("edit", displayRoot.host.language)
          bordered: true
          foreground: displayRoot.host.foreground
          background: "transparent"
          fontFamily: displayRoot.host.nameFontFamily
          fontSize: displayRoot.host.fCaption
          verticalPadding: displayRoot.host.sp(2)
          onClicked: displayRoot.editingTune = true
        }
      }
    }

    Column {
      id: tuneEditor

      visible: displayRoot.editingTune
      width: parent.width
      spacing: displayRoot.host.sp(4)

      Rectangle {
        width: parent.width
        height: displayRoot.host.hairline
        color: displayRoot.host.alpha(displayRoot.host.foreground, 0.10)
      }

      Grid {
        id: tuneGrid

        width: parent.width
        columns: 2
        columnSpacing: displayRoot.host.sp(10)
        rowSpacing: displayRoot.host.sp(4)

        Repeater {
          id: tuneRepeater
          model: Model.TUNE_EDITABLE

          Item {
            id: tuneCell

            required property string modelData
            readonly property int tuneIndex: Model.TUNE_ORDER.indexOf(modelData)
            readonly property bool fieldFocused: tuneNumber.field.activeFocus

            width: (tuneGrid.width - tuneGrid.columnSpacing) / 2
            height: Math.max(displayRoot.host.sp(28), tuneNumber.height)

            onFieldFocusedChanged: displayRoot.syncCalculationFocus()

            function clearFocus() {
              tuneNumber.field.focus = false
            }

            RowLabel {
              anchors.left: parent.left
              anchors.right: tuneNumber.left
              anchors.rightMargin: displayRoot.host.sp(5)
              anchors.verticalCenter: parent.verticalCenter
              text: Model.label(tuneCell.modelData, displayRoot.host.language)
            }

            PrayerNumberField {
              id: tuneNumber
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: displayRoot.host.sp(88)
              from: -60
              to: 60
              stepSize: 1
              value: displayRoot.currentTuneValues[tuneCell.tuneIndex]
              foreground: displayRoot.host.foreground
              fontFamily: displayRoot.host.fontFamily
              fieldWidth: displayRoot.host.sp(88)
              onModified: function(next) {
                displayRoot.writeTune(tuneCell.modelData, next)
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: tuneEditorButtons.implicitHeight

        Row {
          id: tuneEditorButtons
          anchors.right: parent.right
          spacing: displayRoot.host.sp(5)

          PrayerButton {
            visible: displayRoot.hasEditableTune
            text: Model.uiLabel("reset", displayRoot.host.language)
            bordered: true
            foreground: displayRoot.host.foreground
            background: "transparent"
            fontFamily: displayRoot.host.nameFontFamily
            fontSize: displayRoot.host.fCaption
            verticalPadding: displayRoot.host.sp(2)
            onClicked: displayRoot.resetEditableTune()
          }

          PrayerButton {
            text: Model.uiLabel("done", displayRoot.host.language)
            bordered: true
            foreground: displayRoot.host.foreground
            background: "transparent"
            fontFamily: displayRoot.host.nameFontFamily
            fontSize: displayRoot.host.fCaption
            verticalPadding: displayRoot.host.sp(2)
            onClicked: displayRoot.finishTuneEditing()
          }
        }
      }

      Item { width: 1; height: displayRoot.host.sp(2) }
    }

    Item { width: 1; height: displayRoot.host.sp(4) }

    PrayerSectionHeader {
      textFormat: Text.PlainText
      text: Model.uiLabel("display", displayRoot.host.language)
      foreground: displayRoot.host.foreground
      fontFamily: displayRoot.host.nameFontFamily
      bottomPadding: displayRoot.host.sp(3)
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), layoutChoice.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: layoutChoice.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("layout", displayRoot.host.language)
      }

      Choice {
        id: layoutChoice
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: Model.optionModel(Model.PANEL_STYLES, displayRoot.host.language)
        value: displayRoot.host.panelStyle
        onChanged: function(next) { displayRoot.host.setSetting("panelStyle", next) }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), clockChoice.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: clockChoice.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("clock", displayRoot.host.language)
      }

      Choice {
        id: clockChoice
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: Model.optionModel(Model.TIME_FORMATS, displayRoot.host.language)
        value: displayRoot.host.timeFormat
        onChanged: function(next) { displayRoot.host.setSetting("timeFormat", next) }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), namesChoice.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: namesChoice.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("names", displayRoot.host.language)
      }

      Choice {
        id: namesChoice
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: Model.optionModel(Model.LANGUAGES, displayRoot.host.language)
        value: displayRoot.host.language
        onChanged: function(next) { displayRoot.host.setSetting("language", next) }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(30), barChoice.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: barChoice.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("barLabel", displayRoot.host.language)
      }

      // Five options do not fit a chip row in this panel's width, so the bar
      // label is the one setting that keeps a dropdown. While its popup is up
      // it owns j/k and Enter, so the panel's key catcher stands down.
      PrayerDropdown {
        id: barChoice
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: displayRoot.host.sp(150)
        showLabel: false
        fontFamily: displayRoot.host.nameFontFamily
        options: Model.optionModel(Model.BAR_DISPLAYS, displayRoot.host.language)
        value: Model.valueInRing(Model.BAR_DISPLAYS, displayRoot.host.barDisplay)
        onChanged: function(next) { displayRoot.host.setSetting("barDisplay", next) }
        onPopupOpenChanged: displayRoot.host.keysBlocked = popupOpen
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), sunriseSwitch.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: sunriseSwitch.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("sunrise", displayRoot.host.language)
      }

      SettingSwitch {
        id: sunriseSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: displayRoot.host.showSunrise
        onToggled: displayRoot.host.setSetting("showSunrise", !displayRoot.host.showSunrise)
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), nightSwitch.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: nightSwitch.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("nightMarkers", displayRoot.host.language)
      }

      SettingSwitch {
        id: nightSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: displayRoot.host.showNightMarkers
        onToggled: displayRoot.host.setSetting("showNightMarkers", !displayRoot.host.showNightMarkers)
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), notifySwitch.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: notifySwitch.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("notifications", displayRoot.host.language)
      }

      SettingSwitch {
        id: notifySwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: displayRoot.host.notificationsEnabled
        onToggled: displayRoot.host.setSetting("notifications", !displayRoot.host.notificationsEnabled)
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), chimeSwitch.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: chimeSwitch.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("chime", displayRoot.host.language)
      }

      SettingSwitch {
        id: chimeSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: displayRoot.host.notificationSoundEnabled
        onToggled: displayRoot.host.setSetting("notificationSound", !displayRoot.host.notificationSoundEnabled)
      }
    }

    // Only while the chime is on: a volume for a silent notification is noise
    // of another kind.
    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), chimeVolumeRow.height)
      visible: displayRoot.host.notificationSoundEnabled

      RowLabel {
        anchors.left: parent.left
        anchors.right: chimeVolumeRow.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("volume", displayRoot.host.language)
      }

      Row {
        id: chimeVolumeRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: displayRoot.host.sp(7)

        PrayerSlider {
          id: chimeVolumeSlider
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(96)
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          value: displayRoot.host.notificationSoundVolume
          onReleased: function(next) {
            displayRoot.host.setSetting("notificationSoundVolume", Math.round(next))
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(46)
          text: chimeVolumeSlider.liveValue <= 0
            ? Model.uiLabel("off", displayRoot.host.language)
            : Math.round(chimeVolumeSlider.liveValue) + "%"
          color: displayRoot.host.faint
          font.family: displayRoot.host.nameFontFamily
          font.pixelSize: displayRoot.host.fCaption
          elide: Text.ElideRight
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), istijabahSwitch.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: istijabahSwitch.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("istijabah", displayRoot.host.language)
      }

      SettingSwitch {
        id: istijabahSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: displayRoot.host.istijabahEnabled
        onToggled: displayRoot.host.setSetting("istijabah", !displayRoot.host.istijabahEnabled)
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), istijabahLeadRow.height)
      visible: displayRoot.host.istijabahEnabled

      RowLabel {
        anchors.left: parent.left
        anchors.right: istijabahLeadRow.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("istijabahNote", displayRoot.host.language)
      }

      Row {
        id: istijabahLeadRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: displayRoot.host.sp(7)

        PrayerSlider {
          id: istijabahLeadSlider
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(96)
          minimum: 0
          maximum: 180
          step: 5
          integer: true
          value: displayRoot.host.istijabahLead
          onReleased: function(next) {
            displayRoot.host.setSetting("istijabahLeadMinutes", Math.round(next))
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(46)
          text: Math.round(istijabahLeadSlider.liveValue) + " " + Model.uiLabel("minutes", displayRoot.host.language)
          color: displayRoot.host.faint
          font.family: displayRoot.host.nameFontFamily
          font.pixelSize: displayRoot.host.fCaption
          elide: Text.ElideRight
        }
      }
    }

    // Leave empty for the bundled chime. A path is typed rather than picked:
    // the panel has no file dialog, and the shell's own settings form takes
    // the same value.
    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(28), chimeFileField.height)
      visible: displayRoot.host.notificationSoundEnabled

      RowLabel {
        anchors.left: parent.left
        anchors.right: chimeFileField.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("chimeFile", displayRoot.host.language)
      }

      PrayerTextField {
        id: chimeFileField
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: displayRoot.host.sp(150)
        foreground: displayRoot.host.foreground
        placeholderText: Model.uiLabel("bundledChime", displayRoot.host.language)
        font.family: displayRoot.host.nameFontFamily
        font.pixelSize: displayRoot.host.fBodySmall
        text: displayRoot.host.notificationSoundFile
        // While the field owns the keys, the panel's single-letter shortcuts
        // would otherwise eat every character typed into it.
        onActiveFocusChanged: displayRoot.host.keysBlocked = activeFocus
        onEditingFinished: displayRoot.host.setSetting("notificationSoundFile", text.trim())
        Keys.onReturnPressed: function(event) {
          displayRoot.host.setSetting("notificationSoundFile", text.trim())
          focus = false
          event.accepted = true
        }
        Keys.onEscapePressed: function(event) {
          text = displayRoot.host.notificationSoundFile
          focus = false
          event.accepted = true
        }
      }
    }

    Item { width: 1; height: displayRoot.host.sp(4) }

    PrayerSectionHeader {
      textFormat: Text.PlainText
      text: Model.uiLabel("iqamaOffsets", displayRoot.host.language)
      foreground: displayRoot.host.foreground
      fontFamily: displayRoot.host.nameFontFamily
      bottomPadding: displayRoot.host.sp(3)
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), jumuahRow.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: jumuahRow.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("jumuah", displayRoot.host.language)
      }

      Row {
        id: jumuahRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: displayRoot.host.sp(7)

        PrayerSlider {
          id: jumuahSlider
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(96)
          minimum: 0
          // 0-60 like every row below it: same track width, same range, so a
          // handle position means the same number of minutes in all six rows.
          maximum: 60
          step: 5
          integer: true
          value: displayRoot.host.iqamaOffsets.Jumuah
          onReleased: function(next) {
            displayRoot.host.setSetting("iqamaJumuah", Math.round(next))
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(46)
          text: jumuahSlider.liveValue <= 0
            ? Model.uiLabel("off", displayRoot.host.language)
            : Math.round(jumuahSlider.liveValue) + " " + Model.uiLabel("minutes", displayRoot.host.language)
          color: displayRoot.host.faint
          font.family: displayRoot.host.nameFontFamily
          font.pixelSize: displayRoot.host.fCaption
          elide: Text.ElideRight
        }
      }
    }

    Repeater {
      model: Model.PRAYERS

      Item {
        id: iqamaCell

        required property string modelData
        readonly property int offset: Math.round(displayRoot.host.iqamaOffsets[modelData])

        width: parent.width
        height: Math.max(displayRoot.host.sp(26), iqamaRow.height)

        RowLabel {
          anchors.left: parent.left
          anchors.right: iqamaRow.left
          anchors.rightMargin: displayRoot.host.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          text: Model.label(modelData, displayRoot.host.language)
        }

        Row {
          id: iqamaRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: displayRoot.host.sp(7)

          PrayerSlider {
            id: iqamaSlider
            anchors.verticalCenter: parent.verticalCenter
            width: displayRoot.host.sp(96)
            minimum: 0
            maximum: 60
            step: 5
            integer: true
            value: iqamaCell.offset
            onReleased: function(next) {
              displayRoot.host.setSetting("iqama" + iqamaCell.modelData, Math.round(next))
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: displayRoot.host.sp(46)
            text: iqamaSlider.liveValue <= 0
              ? Model.uiLabel("off", displayRoot.host.language)
              : Math.round(iqamaSlider.liveValue) + " " + Model.uiLabel("minutes", displayRoot.host.language)
            color: displayRoot.host.faint
            font.family: displayRoot.host.nameFontFamily
            font.pixelSize: displayRoot.host.fCaption
            elide: Text.ElideRight
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(displayRoot.host.sp(26), accentRow.height)

      RowLabel {
        anchors.left: parent.left
        anchors.right: accentRow.left
        anchors.rightMargin: displayRoot.host.sp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.uiLabel("accentLead", displayRoot.host.language)
      }

      Row {
        id: accentRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: displayRoot.host.sp(7)

        // The slider reports continuously while dragging; only the release is
        // persisted so one drag is a single shell.json write.
        PrayerSlider {
          id: accentSlider
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(96)
          minimum: 0
          maximum: 60
          step: 5
          integer: true
          value: displayRoot.host.highlightBeforeMinutes
          onReleased: function(next) {
            displayRoot.host.setSetting("highlightBeforeMinutes", Math.round(next))
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: displayRoot.host.sp(46)
          text: accentSlider.liveValue <= 0
            ? Model.uiLabel("off", displayRoot.host.language)
            : Math.round(accentSlider.liveValue) + " "
              + Model.uiLabel("minutes", displayRoot.host.language)
          color: displayRoot.host.faint
          font.family: displayRoot.host.nameFontFamily
          font.pixelSize: displayRoot.host.fCaption
          elide: Text.ElideRight
        }
      }
    }
  }
}
