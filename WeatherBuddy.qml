// Bonequinho do card de clima: troca de personagem conforme o tempo atual —
// quente (surfista), chuva (capa e guarda-chuva), frio (casaco), neve
// (boneco de neve) e ameno (andando de fone). Arte: ilustrações unDraw
// recortadas (licença livre, sem atribuição obrigatória).

import QtQuick

Item {
    id: root

    implicitWidth: 38
    implicitHeight: 52

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
        if (Weather.tempC <= 19)
            return "cold";
        return "mild";
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/buddy-" + root.outfit + ".png")
        sourceSize.height: 104
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: false
    }
}
