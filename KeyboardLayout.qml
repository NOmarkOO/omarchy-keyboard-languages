import "KeyboardLayoutModel.js" as Model
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Quattro-native keyboard language indicator and manager. The bar label stays
// terse; the panel makes the managed layouts and their switching rule explicit.
Panel {
    id: root

    property string typedKeyboardName: ""
    property string keyboardName: ""
    property string layoutFull: ""
    property int activeLayoutIndex: 0
    property int keyboardCount: 0
    property bool keyboardUnresolved: false
    property bool refreshPending: false
    property bool stateReady: false
    property var managedState: ({
        "version": 1,
        "layouts": [{
            "layout": "us",
            "variant": "",
            "latin": true
        }],
        "switchOption": "grp:alt_shift_toggle",
        "nonGroupOptions": ["compose:caps", "shift:both_capslock_cancel"]
    })
    property var catalog: ({
        "layouts": [],
        "shortcuts": []
    })
    property string view: "main"
    property string selectedLayout: ""
    property string selectedVariant: ""
    property string selectedShortcut: ""
    property int cursorIndex: 0
    property int pendingDeleteIndex: -1
    property string statusText: ""
    property bool statusError: false
    property int phraseIndex: 0
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color dim: Qt.darker(foreground, 1.45)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property string helperCommand: {
        var resolved = String(Qt.resolvedUrl("bin/nomarkoo-keyboard-layout"));
        return decodeURIComponent(resolved.replace(/^file:\/\//, ""));
    }
    readonly property int pickerControlHeight: Math.max(Style.spacing.controlHeight, Style.font.body + Style.spacing.inputPaddingY * 2 + Style.space(6))
    readonly property int pickerPopupRowHeight: Math.max(Style.spacing.popupRowHeight, pickerControlHeight + Style.space(4))
    readonly property var heroPhrases: Model.heroPhrases()
    readonly property string heroPhrase: heroPhrases.length > 0 ? heroPhrases[phraseIndex % heroPhrases.length] : ""
    readonly property var configuredLayouts: {
        var value = Model.normalizeLayouts(managedState.layouts);
        return value.length > 0 ? value : [{
            "layout": "us",
            "variant": "",
            "latin": true
        }];
    }
    readonly property string switchOption: String(managedState.switchOption || "grp:alt_shift_toggle")
    readonly property var nonGroupOptions: {
        var value = managedState.nonGroupOptions;
        return Array.isArray(value) ? value : [];
    }
    readonly property string layoutLabel: {
        var item = configuredLayouts[Math.max(0, Math.min(activeLayoutIndex, configuredLayouts.length - 1))];
        return item ? Model.labelFor(catalog, item.layout, item.variant) : "KB";
    }
    readonly property string activeDescription: {
        var item = configuredLayouts[Math.max(0, Math.min(activeLayoutIndex, configuredLayouts.length - 1))];
        return item ? Model.descriptionFor(catalog, item.layout, item.variant) : layoutFull;
    }
    readonly property bool editorOpen: view !== "main"

    function shortcutLabel(value) {
        var found = catalog.shortcuts.find(function(item) {
            return item.value === value;
        });
        return found ? found.label : value;
    }

    function typedKeyboards(keyboards) {
        return keyboards.filter(function(keyboard) {
            return Model.isTypedKeyboard(keyboard.name);
        });
    }

    function refresh() {
        if (queryProc.running) {
            refreshPending = true;
            return ;
        }
        refreshPending = false;
        queryProc.running = true;
    }

    function refreshState() {
        if (!stateProc.running && !applyProc.pending) {
            if (!stateReady && opened) {
                statusError = false;
                statusText = "Loading keyboard settings…";
            }
            stateProc.running = true;
        }
    }

    function acceptState(text) {
        var parsed;
        try {
            parsed = JSON.parse(String(text || "").trim());
        } catch (error) {
            return false;
        }
        if (!parsed || Model.normalizeLayouts(parsed.layouts).length === 0)
            return false;
        managedState = parsed;
        stateReady = true;
        return true;
    }

    function openMain() {
        resetPhraseRotation(true);
        view = "main";
        resetAddEditor();
        selectedShortcut = switchOption;
        statusText = "";
        cursorIndex = Math.max(0, Math.min(cursorIndex, configuredLayouts.length + 1));
        Qt.callLater(function() {
            keyCatcher.forceActiveFocus();
        });
    }

    function startShortcut() {
        resetPhraseRotation(true);
        view = "shortcut";
        selectedShortcut = switchOption;
        shortcutPicker.resetSearch();
        shortcutPicker.setCurrentValue(selectedShortcut);
        statusText = "";
    }

    function startAdd() {
        resetPhraseRotation(true);
        view = "add";
        resetAddEditor();
        statusText = "";
    }

    function resetAddEditor() {
        languagePicker.resetSearch();
        variantPicker.resetSearch();
        selectedLayout = "";
        selectedVariant = "";
    }

    function resetPhraseRotation(resetIndex) {
        phraseSwap.stop();
        if (resetIndex)
            phraseIndex = 0;
        hero.metaOpacity = 1;
    }

    function runAction(actionArguments, message, loadingMessage) {
        if (applyProc.pending)
            return ;
        if (stateProc.running || !stateReady) {
            statusError = true;
            statusText = "Keyboard settings are still loading. Try again in a moment.";
            return ;
        }
        statusError = false;
        statusText = loadingMessage || "Applying keyboard settings…";
        applyProc.successMessage = message;
        applyProc.command = [root.helperCommand].concat(actionArguments);
        applyProc.pending = true;
        applyTimeout.restart();
        applyProc.running = true;
    }

    function switchLayout(index) {
        if (!stateReady || index < 0 || index >= configuredLayouts.length || !keyboardName || !bar)
            return ;

        runAction(["set", String(index)], "Keyboard language switched.");
    }

    function cycleLayout() {
        if (configuredLayouts.length < 2)
            return ;
        switchLayout((activeLayoutIndex + 1) % configuredLayouts.length);
    }

    function requestDelete(index) {
        var verdict = Model.canDelete(configuredLayouts, index);
        if (!verdict.ok) {
            statusError = true;
            statusText = verdict.reason;
            return ;
        }
        pendingDeleteIndex = index;
        deleteDialog.opened = true;
    }

    function deletePending() {
        var index = pendingDeleteIndex;
        deleteDialog.opened = false;
        pendingDeleteIndex = -1;
        runAction(["remove", String(index)], "Keyboard language removed.");
    }

    function addSelected() {
        if (!selectedLayout) {
            statusError = true;
            statusText = "Choose a keyboard language first.";
            return ;
        }
        if (Model.duplicate(configuredLayouts, selectedLayout, selectedVariant)) {
            statusError = true;
            statusText = "That language and variant is already available.";
            return ;
        }
        runAction(["add", selectedLayout, selectedVariant], "Keyboard language added.", "Checking keyboard compatibility…");
    }

    function saveShortcut() {
        if (!selectedShortcut) {
            statusError = true;
            statusText = "Choose a supported switching shortcut.";
            return ;
        }
        runAction(["shortcut", selectedShortcut], "Switching shortcut updated.");
    }

    function activateCursor() {
        if (view !== "main")
            return ;

        if (cursorIndex < configuredLayouts.length)
            switchLayout(cursorIndex);
        else if (cursorIndex === configuredLayouts.length)
            startShortcut();
        else
            startAdd();
    }

    function moveCursor(dy) {
        if (view !== "main" || dy === 0)
            return ;

        cursorIndex = Math.max(0, Math.min(configuredLayouts.length + 1, cursorIndex + dy));
    }

    moduleName: "nomarkoo.keyboard-layout"
    ipcTarget: "nomarkoo.keyboard-layout"
    Component.onCompleted: {
        catalogProc.running = true;
        refreshState();
        refresh();
    }

    // Read-only maintainer surface used by demo/capture.sh. These methods only
    // navigate the panel; they never invoke the keyboard helper.
    IpcHandler {
        target: "nomarkoo.keyboard-layout.demo"

        function showMain() {
            root.open();
            Qt.callLater(root.openMain);
        }

        function showAdd() {
            root.open();
            Qt.callLater(root.startAdd);
        }

        function showShortcut() {
            root.open();
            Qt.callLater(root.startShortcut);
        }

        function showRemoval() {
            root.open();
            Qt.callLater(function() {
                root.openMain();
                if (root.configuredLayouts.length > 1)
                    root.requestDelete(1);
            });
        }
    }
    onOpenedChanged: {
        if (opened) {
            openMain();
            refreshState();
            refresh();
        } else {
            resetAddEditor();
            resetPhraseRotation(true);
        }
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Connections {
        function onRawEvent(event) {
            if (!event || !event.name)
                return ;

            var name = String(event.name);
            if (name === "activelayout") {
                var named = Model.eventKeyboardName(event);
                if (named)
                    root.typedKeyboardName = named;

            }
            if (name.indexOf("activelayout") !== -1 || name === "configreloaded")
                root.refresh();

        }

        target: Hyprland
    }

    Process {
        id: queryProc

        command: ["hyprctl", "-j", "devices"]
        onRunningChanged: {
            if (running) {
                stallTimer.restart();
            } else {
                stallTimer.stop();
                if (root.refreshPending)
                    root.refresh();

            }
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var listed;
                try {
                    listed = JSON.parse(text || "{}").keyboards;
                } catch (error) {
                    return ;
                }
                if (!Array.isArray(listed))
                    return ;

                var typed = root.typedKeyboards(listed);
                var keyboard = Model.selectKeyboard(typed, root.typedKeyboardName);
                if (!keyboard || !keyboard.active_keymap) {
                    root.keyboardUnresolved = true;
                    if (typed.length === 0) {
                        root.layoutFull = "";
                        root.keyboardName = "";
                    }
                    return ;
                }
                root.keyboardUnresolved = false;
                root.keyboardCount = typed.length;
                root.keyboardName = String(keyboard.name || "");
                root.layoutFull = String(keyboard.active_keymap || "");
                root.activeLayoutIndex = Number(keyboard.active_layout_index || 0);
            }
        }

    }

    Process {
        id: catalogProc

        command: [root.helperCommand, "available"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.catalog = Model.parseCatalog(text)
        }

    }

    Process {
        id: applyProc

        property string successMessage: ""
        property bool pending: false

        onExited: function(exitCode) {
            if (!pending)
                return ;
            pending = false;
            applyTimeout.stop();
            if (exitCode === 0 && root.acceptState(applyStdout.text)) {
                root.statusError = false;
                root.openMain();
                refreshTimer.restart();
            } else {
                root.statusError = true;
                root.statusText = String(applyStderr.text || "Keyboard settings could not be applied. Your previous settings are still active.").trim();
            }
        }

        stdout: StdioCollector {
            id: applyStdout

            waitForEnd: true
        }

        stderr: StdioCollector {
            id: applyStderr

            waitForEnd: true
        }

    }

    Process {
        id: stateProc

        command: [root.helperCommand, "status"]
        onExited: function(exitCode) {
            if (exitCode === 0 && root.acceptState(stateStdout.text)) {
                if (root.statusText === "Loading keyboard settings…")
                    root.statusText = "";
                if (!root.opened)
                    return ;
            } else if (root.opened) {
                root.statusError = true;
                root.statusText = String(stateStderr.text || "Keyboard settings could not be loaded. Close and reopen this panel to retry.").trim();
            }
        }

        stdout: StdioCollector {
            id: stateStdout

            waitForEnd: true
        }

        stderr: StdioCollector {
            id: stateStderr

            waitForEnd: true
        }

    }

    Timer {
        id: applyTimeout

        interval: 10000
        onTriggered: {
            if (!applyProc.pending)
                return ;
            applyProc.pending = false;
            if (applyProc.running)
                applyProc.running = false;
            root.statusError = true;
            root.statusText = "Keyboard helper did not respond. Restart the Omarchy shell and try again.";
        }
    }

    Timer {
        id: refreshTimer

        interval: 600
        onTriggered: root.refresh()
    }

    Timer {
        id: stallTimer

        interval: 5000
        onTriggered: {
            queryProc.running = false;
            refreshTimer.restart();
        }
    }

    Timer {
        interval: 10000
        running: !root.keyboardName || root.keyboardUnresolved || root.keyboardCount > 1
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: phraseTimer

        interval: 2800
        running: root.opened && root.view === "main" && root.heroPhrases.length > 0
        repeat: true
        triggeredOnStart: false
        onTriggered: phraseSwap.restart()
    }

    SequentialAnimation {
        id: phraseSwap

        PropertyAnimation {
            target: hero
            property: "metaOpacity"
            to: 0
            duration: 180
            easing.type: Easing.OutQuad
        }

        ScriptAction {
            script: {
                var count = root.heroPhrases.length;
                if (count > 0)
                    root.phraseIndex = (root.phraseIndex + 1) % count;
            }
        }

        PropertyAnimation {
            target: hero
            property: "metaOpacity"
            to: 1
            duration: 260
            easing.type: Easing.InQuad
        }
    }

    WidgetButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: root.layoutLabel
        fontSize: Style.font.caption
        horizontalMargin: Style.space(6)
        tooltipText: root.activeDescription + " — left-click switches, right-click manages"
        onPressed: function(button) {
            if (button === Qt.LeftButton)
                root.cycleLayout();
            else if (button === Qt.RightButton)
                root.toggle();
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(420))
        contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            blocked: languagePicker.popupOpen || variantPicker.popupOpen || shortcutPicker.popupOpen
            onMoveRequested: function(dx, dy) {
                if (deleteDialog.opened) {
                    if (dx !== 0 || dy !== 0)
                        deleteDialog.selectedIndex = deleteDialog.selectedIndex === 0 ? 1 : 0;

                } else {
                    root.moveCursor(dy);
                }
            }
            onActivateRequested: {
                if (deleteDialog.opened) {
                    if (deleteDialog.selectedIndex === 0)
                        deleteDialog.canceled();
                    else
                        deleteDialog.confirmed();
                } else {
                    root.activateCursor();
                }
            }
            onCloseRequested: {
                if (deleteDialog.opened)
                    deleteDialog.canceled();
                else if (root.view !== "main")
                    root.openMain();
                else
                    root.close();
            }
            onTabRequested: function(direction) {
                if (deleteDialog.opened)
                    deleteDialog.selectedIndex = deleteDialog.selectedIndex === 0 ? 1 : 0;
                else if (root.view === "main")
                    root.switchPanel(direction);
            }
            onTextKey: function(text) {
                if ((text === "d" || text === "D") && root.view === "main" && root.cursorIndex < root.configuredLayouts.length)
                    root.requestDelete(root.cursorIndex);

            }

            Flickable {
                id: panelFlick

                anchors.fill: parent
                contentWidth: width
                contentHeight: panelColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: panelColumn

                    width: panelFlick.width
                    spacing: Style.space(12)

                    PanelHero {
                        id: hero

                        width: parent.width
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        title: root.view === "main" ? root.activeDescription : (root.view === "shortcut" ? "Switch languages" : "Add a language")
                        meta: root.view === "main" ? root.heroPhrase : (root.view === "shortcut" ? "XKB-supported shortcuts" : "Installed XKB layouts")
                        detail: root.view === "main" ? root.layoutLabel : ""

                        iconComponent: Component {
                            Text {
                                text: root.view === "main" ? "󰌌" : (root.view === "shortcut" ? "󰁔" : "󰐕")
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.display
                            }

                        }

                    }

                    PanelSeparator {
                        width: parent.width
                        foreground: root.foreground
                    }

                    Column {
                        visible: root.view === "main"
                        width: parent.width
                        spacing: Style.space(6)

                        PanelSectionHeader {
                            text: "Available languages"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Repeater {
                            model: root.configuredLayouts

                            CursorSurface {
                                required property int index
                                required property var modelData

                                width: parent.width
                                implicitHeight: languageRow.implicitHeight + Style.spacing.md * 2
                                current: index === root.activeLayoutIndex
                                hasCursor: root.view === "main" && root.cursorIndex === index
                                foreground: root.foreground
                                accent: Color.accent

                                HoverHandler {
                                    onHoveredChanged: {
                                        if (hovered)
                                            root.cursorIndex = index;

                                    }
                                }

                                TapHandler {
                                    onTapped: root.switchLayout(index)
                                }

                                Row {
                                    id: languageRow

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(10)
                                    anchors.rightMargin: Style.space(10)
                                    spacing: Style.space(12)

                                    BorderSurface {
                                        width: Style.space(34)
                                        height: Style.space(28)
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "transparent"
                                        borderSpec: Border.controlSpec(index === root.activeLayoutIndex ? "selected" : "normal", root.foreground, Color.accent)
                                        radius: Style.cornerRadius

                                        Text {
                                            anchors.centerIn: parent
                                            text: Model.labelFor(root.catalog, modelData.layout, modelData.variant)
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            font.bold: true
                                        }

                                    }

                                    Column {
                                        width: Math.max(0, parent.width - Style.space(34) - deleteButton.width - parent.spacing * 2)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.space(1)

                                        Text {
                                            width: parent.width
                                            text: Model.descriptionFor(root.catalog, modelData.layout, modelData.variant)
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.body
                                            font.bold: index === root.activeLayoutIndex
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: modelData.layout.toUpperCase() + (modelData.variant ? " · " + modelData.variant : " · DEFAULT")
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }

                                    }

                                    PanelActionButton {
                                        id: deleteButton

                                        readonly property var deleteVerdict: Model.canDelete(root.configuredLayouts, index)

                                        anchors.verticalCenter: parent.verticalCenter
                                        iconText: "󰅙"
                                        tooltipText: deleteVerdict.ok ? "Remove language" : deleteVerdict.reason
                                        foreground: root.foreground
                                        hoverColor: root.urgent
                                        fontFamily: root.fontFamily
                                        enabled: root.stateReady && deleteVerdict.ok && !applyProc.pending && !stateProc.running
                                        onClicked: root.requestDelete(index)
                                    }

                                }

                            }

                        }

                        Item {
                            width: 1
                            height: Style.space(4)
                        }

                        PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                        }

                        Button {
                            width: parent.width
                            text: "Switch shortcut"
                            iconText: "󰁔"
                            leftAlign: true
                            focusable: true
                            enabled: root.stateReady && !applyProc.pending && !stateProc.running
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            hasCursor: root.cursorIndex === root.configuredLayouts.length
                            onHovered: function(hovered) {
                                if (hovered)
                                    root.cursorIndex = root.configuredLayouts.length;

                            }
                            onClicked: root.startShortcut()
                        }

                        Text {
                            width: parent.width
                            leftPadding: Style.spacing.controlPaddingX
                            text: root.shortcutLabel(root.switchOption)
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                        }

                        Button {
                            width: parent.width
                            text: "Add language"
                            iconText: "󰐕"
                            leftAlign: true
                            focusable: true
                            enabled: root.stateReady && !applyProc.pending && !stateProc.running
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            hasCursor: root.cursorIndex === root.configuredLayouts.length + 1
                            onHovered: function(hovered) {
                                if (hovered)
                                    root.cursorIndex = root.configuredLayouts.length + 1;

                            }
                            onClicked: root.startAdd()
                        }

                    }

                    Column {
                        visible: root.view === "shortcut"
                        width: parent.width
                        spacing: Style.space(12)

                        Text {
                            width: parent.width
                            text: "Choose how the installed languages cycle. Cancel keeps " + root.shortcutLabel(root.switchOption) + "."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                        }

                        KeyboardSearchableDropdown {
                            id: shortcutPicker

                            width: parent.width
                            label: "Keyboard shortcut"
                            placeholderText: "Search supported shortcuts…"
                            emptyText: "No supported shortcut matches"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            rowHeight: root.pickerControlHeight
                            popupRowHeight: root.pickerPopupRowHeight
                            options: root.catalog.shortcuts
                            onChanged: function(value) {
                                root.selectedShortcut = value;
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: Style.space(8)

                            Button {
                                text: "Cancel"
                                focusable: true
                                bordered: true
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: root.openMain()
                            }

                            Button {
                                text: applyProc.pending ? "Applying…" : "Apply"
                                focusable: true
                                bordered: true
                                enabled: root.stateReady && !applyProc.pending && !stateProc.running && root.selectedShortcut !== ""
                                foreground: root.foreground
                                accent: Color.accent
                                fontFamily: root.fontFamily
                                onClicked: root.saveShortcut()
                            }

                        }

                    }

                    Column {
                        visible: root.view === "add"
                        width: parent.width
                        spacing: Style.space(12)

                        Text {
                            width: parent.width
                            text: "Add an XKB language and optional variant. The new language becomes active immediately."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                        }

                        KeyboardSearchableDropdown {
                            id: languagePicker

                            width: parent.width
                            label: "Language"
                            placeholderText: "Search languages…"
                            emptyText: "No language matches"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            rowHeight: root.pickerControlHeight
                            popupRowHeight: root.pickerPopupRowHeight
                            options: Model.baseLayoutOptions(root.catalog, root.configuredLayouts)
                            onChanged: function(value) {
                                root.selectedLayout = value;
                                variantPicker.resetSearch();
                                var variants = Model.variantOptions(root.catalog, value, root.configuredLayouts);
                                root.selectedVariant = variants.length > 0 ? variants[0].value : "";
                                variantPicker.setCurrentValue(root.selectedVariant);
                            }
                        }

                        KeyboardSearchableDropdown {
                            id: variantPicker

                            width: parent.width
                            label: "Variant"
                            placeholderText: root.selectedLayout ? "Search variants…" : "Choose a language first"
                            emptyText: "No unused variants"
                            enabled: root.selectedLayout !== ""
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            rowHeight: root.pickerControlHeight
                            popupRowHeight: root.pickerPopupRowHeight
                            options: Model.variantOptions(root.catalog, root.selectedLayout, root.configuredLayouts)
                            triggerLabel: root.selectedLayout ? "Default" : ""
                            onChanged: function(value) {
                                root.selectedVariant = value;
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: Style.space(8)

                            Button {
                                text: "Cancel"
                                focusable: true
                                bordered: true
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: root.openMain()
                            }

                            Button {
                                text: applyProc.pending ? "Adding…" : "Add"
                                focusable: true
                                bordered: true
                                enabled: root.stateReady && !applyProc.pending && !stateProc.running && root.selectedLayout !== ""
                                foreground: root.foreground
                                accent: Color.accent
                                fontFamily: root.fontFamily
                                onClicked: root.addSelected()
                            }

                        }

                    }

                    Text {
                        visible: root.statusError && root.statusText !== ""
                        width: parent.width
                        text: root.statusText
                        color: root.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                }

                QQC.ScrollBar.vertical: QQC.ScrollBar {
                    policy: QQC.ScrollBar.AsNeeded
                }

            }

            ConfirmDialog {
                id: deleteDialog

                anchors.fill: parent
                message: root.pendingDeleteIndex >= 0 && root.pendingDeleteIndex < root.configuredLayouts.length ? "Remove " + Model.descriptionFor(root.catalog, root.configuredLayouts[root.pendingDeleteIndex].layout, root.configuredLayouts[root.pendingDeleteIndex].variant) + "?" : "Remove this keyboard language?"
                cancelText: "Keep"
                confirmText: "Remove"
                background: Color.popups.background
                foreground: root.foreground
                fontFamily: root.fontFamily
                onCanceled: {
                    opened = false;
                    root.pendingDeleteIndex = -1;
                    keyCatcher.forceActiveFocus();
                }
                onConfirmed: root.deletePending()
            }

        }

    }

}
