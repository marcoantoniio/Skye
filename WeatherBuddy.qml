// Bonequinho do card de clima: troca de roupa conforme o tempo atual —
// quente (camiseta, shorts e oculos), chuva (capa e guarda-chuva), frio
// (casaco, gorro e cachecol), neve (casaco e gorro) e ameno (moletom).

import QtQuick

Item {
    id: root

    implicitWidth: 34
    implicitHeight: 48

    readonly property string outfit: {
        if (!Weather.available)
            return "mild";
        const code = Weather.descCode;
        if (code >= 51 && code <= 67 || code >= 80 && code <= 82 || code >= 95)
            return "rain";
        if (code >= 71 && code <= 77 || code === 85 || code === 86)
            return "snow";
        if (Weather.tempC >= 29)
            return "hot";
        if (Weather.tempC <= 14)
            return "cold";
        return "mild";
    }

    readonly property bool raining: outfit === "rain"
    readonly property bool hatted: outfit === "cold" || outfit === "snow"
    readonly property color topColor: {
        if (outfit === "hot")
            return Theme.accent;
        if (outfit === "rain")
            return Theme.accentCool;
        if (outfit === "cold" || outfit === "snow")
            return Theme.accentPurple;
        return Theme.foregroundDim;
    }
    readonly property color armColor: outfit === "hot" ? Theme.skin : topColor
    readonly property color legColor: outfit === "hot" ? Theme.skin : Theme.pants

    // Guarda-chuva (so na chuva)
    Rectangle {
        visible: root.raining
        x: 3
        y: 0
        width: 28
        height: 11
        topLeftRadius: 14
        topRightRadius: 14
        color: Theme.accentAlt
    }

    Rectangle {
        visible: root.raining
        x: 26
        y: 11
        width: 2.5
        height: 14
        color: Theme.accentInk
    }

    // Capuz (chuva), atras da cabeca
    Rectangle {
        visible: root.raining
        x: 8
        y: 6
        width: 17
        height: 11
        topLeftRadius: 8.5
        topRightRadius: 8.5
        color: Theme.accentCool
    }

    // Cabeca
    Rectangle {
        x: 10
        y: 8
        width: 14
        height: 14
        radius: 7
        color: Theme.skin
    }

    // Gorro (frio/neve)
    Rectangle {
        visible: root.hatted
        x: 10
        y: 6
        width: 14
        height: 6
        topLeftRadius: 7
        topRightRadius: 7
        color: root.outfit === "snow" ? Theme.accentCool : Theme.accent
    }

    // Olhos (somem quando ha oculos)
    Rectangle {
        visible: root.outfit !== "hot"
        x: 13
        y: 14
        width: 2
        height: 2
        radius: 1
        color: Theme.accentInk
    }

    Rectangle {
        visible: root.outfit !== "hot"
        x: 19
        y: 14
        width: 2
        height: 2
        radius: 1
        color: Theme.accentInk
    }

    // Oculos de sol (quente)
    Rectangle {
        visible: root.outfit === "hot"
        x: 11.5
        y: 13
        width: 11
        height: 3
        radius: 1.5
        color: Theme.accentInk
    }

    // Cachecol (frio/neve)
    Rectangle {
        visible: root.hatted
        x: 8.5
        y: 21.5
        width: 17
        height: 4
        radius: 2
        color: root.outfit === "snow" ? Theme.accent : Theme.accentAlt
    }

    // Tronco (camiseta/casaco/moletom/capa)
    Rectangle {
        x: 8.5
        y: 22.5
        width: 17
        height: 15
        radius: 5
        color: root.topColor
    }

    // Shorts (quente, por cima do topo das pernas)
    Rectangle {
        visible: root.outfit === "hot"
        x: 8.5
        y: 37
        width: 17
        height: 6
        radius: 2
        color: Theme.pants
    }

    // Bracos (com costura fina em relacao ao tronco)
    Rectangle {
        x: 3.5
        y: 24
        width: 4.5
        height: 13
        radius: 2.25
        color: root.armColor
    }

    Rectangle {
        x: 26
        y: 24
        width: 4.5
        height: 13
        radius: 2.25
        color: root.armColor
    }

    // Pernas
    Rectangle {
        x: 10.5
        y: 39
        width: 4.5
        height: 7.5
        radius: 2
        color: root.legColor
    }

    Rectangle {
        x: 19
        y: 39
        width: 4.5
        height: 7.5
        radius: 2
        color: root.legColor
    }

    // Sapatos
    Rectangle {
        x: 9
        y: 45
        width: 7
        height: 3
        radius: 1.5
        color: Theme.foregroundDim
    }

    Rectangle {
        x: 18
        y: 45
        width: 7
        height: 3
        radius: 1.5
        color: Theme.foregroundDim
    }
}
