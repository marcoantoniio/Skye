pragma Singleton

// Estado global da ilha (pílula), compartilhado entre os monitores.
// O hover é escrito pela barra onde o mouse está (só em mudanças), e os
// painéis usam para fechar apenas quando o mouse sai de TUDO (ilha + painel),
// em qualquer tela.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool hovered: false

    // Quantos painéis estão com a janela na tela agora (inclui o que está
    // saindo). Na troca, o painel que entra detecta que já havia um e faz o
    // morph de tamanho em vez de crescer de novo.
    property int panelsShown: 0

    // Tamanho do último painel que saiu (a troca começa morfando daqui)
    property real lastPanelWidth: 0
    property real lastPanelHeight: 0

    // Tamanho alvo do morph (definido pelo painel que entra)
    property real switchTargetWidth: 0
    property real switchTargetHeight: 0

    // Largura atual da pílula (escrita pela barra): os painéis acompanham a
    // ilha — a moldura deles colapsa junto com ela no fechamento.
    property real pillWidth: 0

    // Sequência de trocas: o painel que entra incrementa; quem está saindo
    // acompanha o morph NA MESMA hora (sem atraso de frame, senão a janela
    // antiga deixa um "rastro" aparecendo em volta da nova).
    property int switchSeq: 0

    // Formato da ilha: false = pílula arredondada flutuando; true = quadrada,
    // colada no topo da tela. Persiste entre reinícios do shell.
    property bool square: false

    onSquareChanged: Quickshell.execDetached(["sh", "-c",
        "printf '%s' '" + (square ? "1" : "0") + "' > '" + Quickshell.stateDir + "/island_square.txt'"])

    Process {
        id: loadProc

        command: ["cat", Quickshell.stateDir + "/island_square.txt"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.square = text.trim() === "1"
        }
    }
}
