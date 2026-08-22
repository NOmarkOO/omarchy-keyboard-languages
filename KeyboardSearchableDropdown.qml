import "KeyboardLayoutModel.js" as Model
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui

// Quattro's searchable picker, scoped to this plugin and made screen-aware.
// The popup is reparented to the shell window so panel clipping and every bar
// orientation share one bounded placement path.
Item {
    id: root

    property string label: ""
    property string value: ""
    property var options: []
    property string placeholderText: "Search..."
    property string emptyText: "No matches"
    property string triggerLabel: ""
    property color foreground: Color.popups.text
    property color background: Color.popups.background
    property color popupBorder: Color.popups.border
    property color accent: Color.accent
    readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
    property string fontFamily: Style.font.family
    property int rowHeight: Style.spacing.controlHeight
    property int popupRowHeight: Style.spacing.popupRowHeight
    property int popupMinHeight: Style.spacing.searchablePopupMinHeight
    property bool showLabel: true
    property bool hasCursor: false
    readonly property bool popupOpen: popup.opened
    property var filtered: options

    signal changed(string value)
    signal hovered(bool isHovered)

    function open() {
        popup.open();
    }

    function close() {
        popup.close();
    }

    function resetSearch() {
        popup.close();
        searchField.text = "";
        filtered = options;
        resultList.currentIndex = -1;
        value = "";
    }

    function setCurrentValue(nextValue) {
        value = String(nextValue || "");
    }

    function toggle() {
        popup.opened ? popup.close() : popup.open();
    }

    function optionValue(option) {
        return option && typeof option === "object" ? String(option.value) : String(option);
    }

    function optionLabel(option) {
        return option && typeof option === "object" ? String(option.label) : String(option);
    }

    function optionDescription(option) {
        return option && typeof option === "object" && option.description ? String(option.description) : "";
    }

    function currentLabel() {
        for (var i = 0; i < options.length; i++) {
            if (optionValue(options[i]) === value)
                return optionLabel(options[i]);
        }
        return value;
    }

    function recomputeFiltered() {
        var query = searchField.text.toLowerCase();
        if (!query) {
            filtered = options;
            return ;
        }
        var matches = [];
        for (var i = 0; i < options.length; i++) {
            var optionLabelText = optionLabel(options[i]).toLowerCase();
            var optionDescriptionText = optionDescription(options[i]).toLowerCase();
            if (optionLabelText.indexOf(query) !== -1 || optionDescriptionText.indexOf(query) !== -1)
                matches.push(options[i]);
        }
        filtered = matches;
    }

    onOptionsChanged: recomputeFiltered()
    implicitWidth: Style.spacing.searchableDropdownWidth
    implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

    Column {
        anchors.fill: parent
        spacing: Style.spacing.labelGap

        Text {
            visible: root.showLabel && root.label !== ""
            text: root.label
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        BorderSurface {
            id: trigger

            width: parent.width
            height: root.rowHeight
            radius: Style.cornerRadius
            readonly property bool _focused: trigger.activeFocus
            readonly property bool _hot: triggerHover.hovered || root.hasCursor
            readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)
            color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
            borderSpec: _borderSpec
            activeFocusOnTab: true

            HoverHandler {
                id: triggerHover
                onHoveredChanged: root.hovered(hovered)
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
                    popup.opened ? popup.close() : popup.open();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape && popup.opened) {
                    popup.close();
                    event.accepted = true;
                }
            }

            Text {
                anchors.left: parent.left
                anchors.right: chevron.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
                anchors.rightMargin: trigger.borderRight + Style.spacing.md
                text: root.currentLabel() || root.triggerLabel || root.placeholderText
                color: root.currentLabel() || root.triggerLabel ? root.foreground : Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
            }

            Text {
                id: chevron

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
                text: "󰅀"
                color: Qt.darker(root.foreground, 1.2)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    trigger.forceActiveFocus();
                    popup.opened ? popup.close() : popup.open();
                }
            }

            QQC.Popup {
                id: popup

                parent: trigger.Window.window ? trigger.Window.window.contentItem : trigger
                property var placement: ({
                    "x": 0,
                    "y": 0,
                    "width": trigger.width,
                    "height": 0,
                    "above": false
                })
                readonly property real windowWidth: parent ? parent.width : 0
                readonly property real windowHeight: parent ? parent.height : 0
                readonly property real idealContentHeight: resultList.contentHeight + Style.space(50)
                readonly property real maxRowsHeight: root.popupRowHeight * 6 + 5 * Style.spacing.labelGap + Style.space(50)
                readonly property real desiredHeight: Math.max(root.popupMinHeight, Math.min(idealContentHeight, maxRowsHeight))

                function reposition() {
                    if (!parent || windowWidth <= 0 || windowHeight <= 0)
                        return ;
                    var point = trigger.mapToItem(parent, 0, 0);
                    placement = Model.popupPlacement(point.x, point.y, trigger.width, trigger.height, windowWidth, windowHeight, desiredHeight, Style.space(12), Style.spacing.xxs);
                }

                x: placement.x
                y: placement.y
                width: placement.width
                implicitHeight: placement.height
                padding: Style.spacing.hairline
                leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
                rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
                topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
                bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
                focus: true
                onAboutToShow: reposition()
                onOpened: {
                    searchField.text = "";
                    root.recomputeFiltered();
                    reposition();
                    Qt.callLater(function() {
                        popup.reposition();
                        searchField.forceActiveFocus();
                    });
                }
                onClosed: searchField.text = ""
                onDesiredHeightChanged: {
                    if (opened)
                        reposition();
                }

                Connections {
                    target: popup.parent

                    function onWidthChanged() {
                        if (popup.opened)
                            popup.reposition();
                    }

                    function onHeightChanged() {
                        if (popup.opened)
                            popup.reposition();
                    }
                }

                background: BorderSurface {
                    color: root.background
                    borderSpec: root.popupBorderSpec
                    radius: Style.cornerRadius
                }

                contentItem: Column {
                    spacing: 0

                    Item {
                        id: searchHeader

                        width: parent.width
                        height: root.popupRowHeight + Style.spacing.controlPaddingX

                        TextField {
                            id: searchField

                            anchors.fill: parent
                            anchors.margins: Style.spacing.md
                            placeholderText: root.placeholderText
                            foreground: root.foreground
                            accent: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            onTextChanged: {
                                root.recomputeFiltered();
                                if (resultList.count > 0)
                                    resultList.currentIndex = 0;
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    popup.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (resultList.count > 0) {
                                        resultList.currentIndex = 0;
                                        resultList.forceActiveFocus();
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (resultList.count > 0) {
                                        resultList.currentIndex = 0;
                                        resultList.selectCurrent();
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Util.alpha(root.foreground, 0.10)
                    }

                    Item {
                        width: parent.width
                        height: Math.max(0, popup.height - searchHeader.height - Style.spacing.xxs - 1)

                        Text {
                            anchors.centerIn: parent
                            visible: resultList.count === 0
                            text: root.emptyText
                            color: Qt.darker(root.foreground, 1.6)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                        }

                        ListView {
                            id: resultList

                            anchors.fill: parent
                            spacing: Style.spacing.labelGap
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.filtered
                            currentIndex: -1
                            keyNavigationEnabled: false
                            onContentHeightChanged: {
                                if (popup.opened)
                                    popup.reposition();
                            }

                            function selectCurrent() {
                                if (currentIndex < 0 || currentIndex >= root.filtered.length)
                                    return ;
                                var selectedValue = root.optionValue(root.filtered[currentIndex]);
                                root.setCurrentValue(selectedValue);
                                root.changed(selectedValue);
                                popup.close();
                            }

                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    popup.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down || event.text === "j") {
                                    if (resultList.currentIndex < resultList.count - 1)
                                        resultList.currentIndex++;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up || event.text === "k") {
                                    if (resultList.currentIndex <= 0)
                                        searchField.forceActiveFocus();
                                    else
                                        resultList.currentIndex--;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    resultList.selectCurrent();
                                    event.accepted = true;
                                }
                            }

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: resultList.width
                                height: Math.max(root.popupRowHeight, rowContent.implicitHeight + Style.spacing.rowPaddingX)
                                color: index === resultList.currentIndex ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

                                Column {
                                    id: rowContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.spacing.controlPaddingX
                                    anchors.rightMargin: Style.spacing.controlPaddingX
                                    spacing: Style.spacing.xxs

                                    Text {
                                        width: parent.width
                                        text: root.optionLabel(modelData)
                                        color: index === resultList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        visible: text !== ""
                                        text: root.optionDescription(modelData)
                                        color: Qt.darker(root.foreground, 1.5)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: resultList.currentIndex = parent.index
                                    onClicked: resultList.selectCurrent()
                                }
                            }
                        }
                    }
                }
            }

            TransformWatcher {
                a: popup.parent
                b: trigger
                onTransformChanged: {
                    if (popup.opened)
                        popup.reposition();
                }
            }
        }
    }
}

