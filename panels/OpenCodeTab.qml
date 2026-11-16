// Aba de agentes do Control Center: prompt com streaming estruturado (API
// local do OpenCode ou ACP do Copilot), em abas independentes (cada uma com
// provedor, sessão, pasta e modelo próprios). Ctrl+T nova aba; Ctrl+W fecha;
// Ctrl+Tab alterna. /cd <pasta> muda o diretório e /model <nome> troca o
// modelo. Enter envia; ↑/↓ navegam o histórico da aba atual.

import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

ColumnLayout {
    id: root

    property real shiftX: 0
    property int histIdx: 0
    property real clockNow: Date.now()

    transform: Translate { x: root.shiftX }
    spacing: 6

    readonly property var tab: OpenCode.current

    Timer {
        interval: 1000
        repeat: true
        running: OpenCode.runningNow
        onTriggered: root.clockNow = Date.now()
    }

    function submit() {
        const text = input.text.trim();
        if (text === "" || root.tab === null || root.tab.running)
            return;
        input.text = "";
        root.histIdx = 0;
        OpenCode.send(text);
    }

    function histUp() {
        if (root.tab === null)
            return;
        const history = root.tab.history;
        if (root.histIdx >= history.length)
            return;
        root.histIdx++;
        input.text = history[history.length - root.histIdx];
        input.cursorPosition = input.text.length;
    }

    function histDown() {
        if (root.tab === null || root.histIdx <= 0)
            return;
        root.histIdx--;
        input.text = root.histIdx === 0 ? "" : root.tab.history[root.tab.history.length - root.histIdx];
        input.cursorPosition = input.text.length;
    }

    // Atalhos de terminal, ativos só quando a página do OpenCode está aberta.
    Shortcut {
        sequence: "Ctrl+T"
        enabled: ControlCenter.open && ControlCenter.tab === 3
        onActivated: OpenCode.newTab()
    }

    Shortcut {
        sequence: "Ctrl+W"
        enabled: ControlCenter.open && ControlCenter.tab === 3
        onActivated: OpenCode.closeTab(OpenCode.currentTab)
    }

    Shortcut {
        sequence: "Ctrl+Tab"
        enabled: ControlCenter.open && ControlCenter.tab === 3 && OpenCode.tabs.length > 1
        onActivated: OpenCode.selectTab((OpenCode.currentTab + 1) % OpenCode.tabs.length)
    }

    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        enabled: ControlCenter.open && ControlCenter.tab === 3 && OpenCode.tabs.length > 1
        onActivated: OpenCode.selectTab((OpenCode.currentTab - 1 + OpenCode.tabs.length) % OpenCode.tabs.length)
    }

    Connections {
        target: OpenCode

        function onCurrentTabChanged() {
            root.histIdx = 0;
            Qt.callLater(() => output.positionViewAtEnd());
        }
    }

    // ---------- abas ----------
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        ListView {
            id: tabStrip

            Layout.fillWidth: true
            Layout.preferredHeight: 24
            implicitHeight: 24
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            model: OpenCode.tabs
            currentIndex: OpenCode.currentTab
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Contain))
            onCountChanged: if (currentIndex >= 0) Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Contain))

            WheelHandler {
                onWheel: (wheel) => {
                    tabStrip.contentX = Math.max(0, Math.min(
                        tabStrip.contentWidth - tabStrip.width,
                        tabStrip.contentX - wheel.angleDelta.y));
                }
            }

            delegate: Rectangle {
                id: tabItem

                required property var modelData
                required property int index

                readonly property bool active: tabItem.index === OpenCode.currentTab

                implicitWidth: Math.min(180, Math.max(78, tabRow.implicitWidth + 14))
                implicitHeight: 24
                radius: 7
                color: tabItem.active
                    ? Theme.withAlpha(Theme.accent, 0.13)
                    : (tabHover.hovered ? Theme.surfaceHover : "transparent")
                border.width: 1
                border.color: tabItem.active
                    ? Theme.withAlpha(Theme.accent, 0.38)
                    : "transparent"

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.MiddleButton)
                            OpenCode.closeTab(tabItem.index);
                        else
                            OpenCode.selectTab(tabItem.index);
                    }
                }

                HoverHandler {
                    id: tabHover
                }

                Row {
                    id: tabRow

                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: tabItem.modelData.running ? Theme.accent : Theme.foregroundDim
                        opacity: tabItem.modelData.running ? 1 : 0.45
                    }

                    Text {
                        id: tabName

                        text: OpenCode.tabTitle(tabItem.modelData)
                        width: Math.min(104, implicitWidth)
                        elide: Text.ElideMiddle
                        color: tabItem.active ? Theme.foreground : Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: tabItem.modelData.running
                        text: OpenCode.clock((root.clockNow - tabItem.modelData.startedAt) / 1000)
                        color: Theme.accent
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: tabClose

                            anchors.centerIn: parent
                            text: "✕"
                            color: tabCloseArea.containsMouse ? Theme.urgent : Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            opacity: tabItem.active || tabHover.hovered ? 1 : 0
                        }

                        MouseArea {
                            id: tabCloseArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: OpenCode.closeTab(tabItem.index)
                        }
                    }
                }

                Rectangle {
                    visible: tabItem.active
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: 8
                        rightMargin: 8
                    }
                    height: 2
                    radius: 1
                    color: Theme.accent
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 7
            color: newTabArea.containsMouse ? Theme.surfaceHover : "transparent"
            border.width: 1
            border.color: newTabArea.containsMouse ? Theme.border : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\u{F0415}" // md-plus
                color: newTabArea.containsMouse ? Theme.accent : Theme.foregroundDim
                font.family: Theme.iconFont
                font.pixelSize: 12
            }

            MouseArea {
                id: newTabArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: OpenCode.newTab()
            }
        }

        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 7
            color: folderArea.containsMouse ? Theme.surfaceHover : "transparent"
            border.width: 1
            border.color: folderArea.containsMouse ? Theme.border : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\u{F024B}" // md-folder (abrir uma aba numa pasta)
                color: folderArea.containsMouse ? Theme.accent : Theme.foregroundDim
                font.family: Theme.iconFont
                font.pixelSize: 12
            }

            MouseArea {
                id: folderArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: OpenCode.chooseFolder()
            }
        }

        // Um clique abre uma aba nova no provedor escolhido.
        Repeater {
            model: Agents.providers

            delegate: Rectangle {
                required property var modelData

                Layout.preferredWidth: providerLabel.implicitWidth + 14
                Layout.preferredHeight: 24
                radius: 7
                color: providerArea.containsMouse
                    ? Theme.withAlpha(modelData.tint, 0.16)
                    : "transparent"
                border.width: 1
                border.color: providerArea.containsMouse ? Theme.border : "transparent"

                Text {
                    id: providerLabel

                    anchors.centerIn: parent
                    text: modelData.name
                    color: providerArea.containsMouse ? Theme.accent : Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: providerArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: OpenCode.newTab(modelData.id)
                }
            }
        }
    }

    // ---------- cartão da sessão (linguagem do Vorssaint) ----------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sessionCard.implicitHeight + 18
        radius: 10
        color: Theme.card
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.20)

        ColumnLayout {
            id: sessionCard

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 9
                rightMargin: 9
                topMargin: 9
            }
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                OpenCodeMark {
                    size: 16
                    working: root.tab !== null && root.tab.running
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.tab === null
                        ? "Agent"
                        : OpenCode.tabTitle(root.tab)
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // "Agora" / "Parado", como o chip de estado do Vorssaint
                Rectangle {
                    implicitWidth: statusRow.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: root.tab !== null && root.tab.running
                        ? Theme.withAlpha(Theme.accent, 0.16)
                        : Qt.rgba(1, 1, 1, 0.06)

                    Row {
                        id: statusRow

                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.tab !== null && root.tab.running
                                ? Theme.accent : Theme.foregroundDim
                        }

                        Text {
                            text: root.tab !== null && root.tab.running
                                ? I18n.tr("ocNow") : I18n.tr("ocIdle")
                            color: root.tab !== null && root.tab.running
                                ? Theme.accent : Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Text {
                    visible: root.tab !== null && root.tab.running
                    text: root.tab !== null
                        ? OpenCode.clock((root.clockNow - root.tab.startedAt) / 1000) : ""
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }

                Rectangle {
                    visible: root.tab !== null && root.tab.running
                    implicitWidth: stopLabel.implicitWidth + 14
                    implicitHeight: 16
                    radius: 8
                    color: Theme.withAlpha(Theme.accent, 0.16)

                    Text {
                        id: stopLabel

                        anchors.centerIn: parent
                        text: I18n.tr("ocStop")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: OpenCode.stop()
                    }
                }

                Text {
                    text: "\u{F00E2}" // md-broom (limpar o chat)
                    color: clearArea.containsMouse ? Theme.foreground : Theme.foregroundDim
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        id: clearArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: OpenCode.clearLines()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: {
                        const project = root.tab !== null ? OpenCode.projectName(root.tab) : "";
                        const model = root.tab !== null && OpenCode.modelFor(root.tab) !== ""
                            ? OpenCode.modelFor(root.tab)
                            : (root.tab !== null && root.tab.provider === "copilot"
                                ? I18n.tr("copilotDefaultModel") : I18n.tr("ocDefaultModel"));
                        const provider = root.tab !== null ? OpenCode.providerName(root.tab) : "OpenCode";
                        return provider + " · " + project + " · " + model;
                    }
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                // Chips no estilo dos cartões do Vorssaint
                Rectangle {
                    implicitWidth: readoutChip.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: readoutArea.containsMouse
                        ? Theme.withAlpha(Theme.accent, 0.22)
                        : Theme.withAlpha(Theme.accent, 0.14)

                    Text {
                        id: readoutChip

                        anchors.centerIn: parent
                        text: Agents.readoutLabel()
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: readoutArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Agents.cycleReadout()
                    }
                }

                Rectangle {
                    visible: root.tab !== null && OpenCode.tokensOf(root.tab) > 0
                    implicitWidth: tokensChip.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: Theme.withAlpha(Theme.accent, 0.14)

                    Text {
                        id: tokensChip

                        anchors.centerIn: parent
                        text: root.tab !== null
                            ? OpenCode.formatTokens(OpenCode.tokensOf(root.tab)) + " "
                              + I18n.tr("ocTokens") : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: root.tab !== null && OpenCode.tokensOf(root.tab) > 0
                    implicitWidth: costChip.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)

                    Text {
                        id: costChip

                        anchors.centerIn: parent
                        text: root.tab !== null
                            ? "API " + OpenCode.formatCost(OpenCode.costOf(root.tab)) : ""
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: root.tab !== null && OpenCode.cacheOf(root.tab) > 0
                    implicitWidth: cacheChip.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: Theme.withAlpha(Theme.accent, 0.14)

                    Text {
                        id: cacheChip

                        anchors.centerIn: parent
                        text: root.tab !== null
                            ? Math.round(OpenCode.cacheOf(root.tab) * 100) + "% "
                              + I18n.tr("ocCache") : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // ---------- saída ----------
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 8
        color: Theme.card
        clip: true

        ListView {
            id: output

            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            anchors.rightMargin: 14
            clip: true
            spacing: 4
            model: OpenCode.lines

            onContentHeightChanged: if (output.atYEnd) output.positionViewAtEnd()

            delegate: Item {
                id: line

                required property var modelData
                required property int index

                readonly property bool isUser: modelData.kind === "cmd"
                readonly property bool isModel: modelData.kind === "out"
                readonly property bool isTool: modelData.kind === "tool"
                readonly property var prev: index > 0 ? OpenCode.lines[index - 1] : null
                readonly property int gap: {
                    if (prev === null)
                        return 0;
                    if (isUser)
                        return 8;
                    if (prev.kind === "cmd")
                        return 6;
                    if (prev.kind === "out" && !isModel)
                        return 6;
                    if (prev.kind === "tool" && isModel)
                        return 6;
                    return 0;
                }
                readonly property real contentHeight: isUser ? userBubble.implicitHeight
                                                    : isModel ? modelBubble.implicitHeight
                                                    : textLine.implicitHeight

                width: output.width
                implicitHeight: gap + contentHeight

                // mensagem do usuário: balão à direita
                Rectangle {
                    id: userBubble

                    visible: line.isUser
                    anchors.right: parent.right
                    y: line.gap
                    width: Math.min(userText.implicitWidth + 20, parent.width * 0.8)
                    implicitHeight: userText.implicitHeight + 12
                    radius: 10
                    color: Theme.accent

                    Text {
                        id: userText

                        anchors.centerIn: parent
                        width: parent.width - 20
                        text: modelData.text.replace(/^❯ /, "")
                        color: Theme.accentInk
                        font.family: Theme.iconFont
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                    }
                }

                // resposta do modelo: balão neutro à esquerda
                Rectangle {
                    id: modelBubble

                    visible: line.isModel
                    anchors.left: parent.left
                    y: line.gap
                    width: Math.min(modelText.implicitWidth + 20, parent.width * 0.88)
                    implicitHeight: modelText.implicitHeight + 12
                    radius: 10
                    color: Theme.surfaceHover

                    Text {
                        id: modelText

                        anchors.centerIn: parent
                        width: parent.width - 20
                        text: Markdown.toHtml(modelData.text)
                        textFormat: Text.RichText
                        color: Theme.foreground
                        font.family: Theme.iconFont
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                    }
                }

                // ferramentas, erros e avisos do sistema
                Text {
                    id: textLine

                    visible: !line.isUser && !line.isModel
                    y: line.gap
                    x: line.isTool ? 10 : 0
                    width: parent.width - (line.isTool ? 10 : 0)
                    text: modelData.text === "" ? " " : modelData.text
                    color: modelData.kind === "err" ? Theme.urgent
                         : (modelData.kind === "tool" && modelData.status === "failed")
                             ? Theme.urgent : Theme.foregroundDim
                    font.family: Theme.iconFont
                    font.pixelSize: modelData.kind === "info" ? 9 : 11
                    horizontalAlignment: modelData.kind === "info" ? Text.AlignHCenter : Text.AlignLeft
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        // ---- barra de rolagem ----
        Rectangle {
            id: scrollTrack

            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                topMargin: 8
                bottomMargin: 8
                rightMargin: 4
            }
            width: 4
            radius: 2
            color: "transparent"
            visible: output.contentHeight > output.height + 1

            Rectangle {
                id: scrollHandle

                width: parent.width
                radius: 2
                color: Theme.foregroundDim
                opacity: scrollDrag.dragging || scrollDrag.containsMouse ? 0.9 : 0.35
                height: Math.max(24, scrollTrack.height * output.height / output.contentHeight)
                y: Math.max(0, Math.min(scrollTrack.height - height,
                       (scrollTrack.height - height) * output.contentY / Math.max(1, output.contentHeight - output.height)))

                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }
            }

            MouseArea {
                id: scrollDrag

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeVerCursor

                property bool dragging: false
                property real grabDy: 0

                function moveTo(y) {
                    const span = scrollTrack.height - scrollHandle.height;
                    if (span <= 0)
                        return;
                    const frac = Math.max(0, Math.min(1, (y - grabDy) / span));
                    output.contentY = frac * (output.contentHeight - output.height);
                }

                onPressed: (mouse) => {
                    dragging = true;
                    grabDy = (mouse.y >= scrollHandle.y && mouse.y <= scrollHandle.y + scrollHandle.height)
                           ? mouse.y - scrollHandle.y
                           : scrollHandle.height / 2;
                    moveTo(mouse.y);
                }
                onPositionChanged: (mouse) => {
                    if (dragging)
                        moveTo(mouse.y);
                }
                onReleased: dragging = false
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 60
            spacing: 8
            visible: root.tab === null || OpenCode.lines.length === 0

            OpenCodeBot {
                anchors.horizontalCenter: parent.horizontalCenter
                tint: Theme.accent
                opacity: 0.9
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("ocHint")
                color: Theme.foregroundDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }
        }
    }

    // ---------- entrada ----------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: Theme.surfaceHover
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
                text: "❯"
                color: Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 12
            }

            TextInput {
                id: input

                Layout.fillWidth: true
                clip: true
                focus: ControlCenter.tab === 3
                color: Theme.foreground
                selectionColor: Theme.accent
                selectedTextColor: Theme.background
                font.family: Theme.iconFont
                font.pixelSize: 11
                selectByMouse: true

                onAccepted: root.submit()

                Keys.onUpPressed: root.histUp()
                Keys.onDownPressed: root.histDown()
            }
        }
    }
}
