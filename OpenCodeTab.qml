// Aba OpenCode do Control Center: prompt com streaming das respostas do
// `opencode run`, numa sessão dedicada (OpenCode.qml). /cd <pasta> muda o
// diretório e /model <nome> troca o modelo. Enter envia; ↑/↓ navegam o
// histórico.

import Quickshell
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property real shiftX: 0
    property int histIdx: 0

    transform: Translate { x: root.shiftX }
    spacing: 6

    readonly property string shortDir: {
        const home = Quickshell.env("HOME");
        return OpenCode.workingDir.startsWith(home)
            ? "~" + OpenCode.workingDir.slice(home.length)
            : OpenCode.workingDir;
    }

    function submit() {
        const text = input.text.trim();
        if (text === "" || OpenCode.running)
            return;
        input.text = "";
        root.histIdx = 0;
        OpenCode.send(text);
    }

    function histUp() {
        if (root.histIdx >= OpenCode.history.length)
            return;
        root.histIdx++;
        input.text = OpenCode.history[OpenCode.history.length - root.histIdx];
        input.cursorPosition = input.text.length;
    }

    function histDown() {
        if (root.histIdx <= 0)
            return;
        root.histIdx--;
        input.text = root.histIdx === 0 ? "" : OpenCode.history[OpenCode.history.length - root.histIdx];
        input.cursorPosition = input.text.length;
    }

    // ---------- cabeçalho: pasta · modelo + parar + nova ----------
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        OpenCodeBot {
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            text: root.shortDir + (OpenCode.model !== "" ? " · " + OpenCode.model : "")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideLeft
        }

        Text {
            visible: OpenCode.running
            text: "● " + I18n.tr("ocWorking")
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        Text {
            visible: OpenCode.running
            text: I18n.tr("ocStop")
            color: stopArea.containsMouse ? Theme.foreground : Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 10

            MouseArea {
                id: stopArea
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

        Text {
            text: "\u{F0415}" // md-plus (nova sessão)
            color: newArea.containsMouse ? Theme.foreground : Theme.foregroundDim
            font.family: Theme.iconFont
            font.pixelSize: 13
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                id: newArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: OpenCode.newSession()
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
                        text: modelData.text
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
                         : Theme.foregroundDim
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

        Text {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: OpenCode.lines.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("ocHint")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.Wrap
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
