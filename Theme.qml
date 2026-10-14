pragma Singleton

// Tema central: cores, métricas e fontes.
// Mude tudo por aqui — nenhum componente tem cor hardcoded.

import Quickshell
import QtQuick

Singleton {
    // Cores (pílula preta com leve transparência + acentos quentes)
    // Formato Qt: #AARRGGBB — o AA controla a transparência (eb ≈ 92%)
    readonly property color background: "#eb000000"
    readonly property color surface: "#f0000000"
    readonly property color card: "#141414"
    readonly property color surfaceHover: "#2b2825"
    readonly property color foreground: "#efeceb"
    readonly property color foregroundDim: "#a09890"
    readonly property color accent: "#f4be9e"
    // Cor de conteúdo (ícones/texto) sobre o acento — o acento é claro, então escuro
    readonly property color accentInk: "#1f1a17"
    readonly property color accentAlt: "#e84070"
    readonly property color accentCool: "#40d8d8"
    readonly property color accentGreen: "#a6e3a1"
    readonly property color accentPurple: "#cba6f7"
    readonly property color urgent: "#e8836f"
    readonly property color recording: "#ff4b4b"
    readonly property color border: "#332f2c"
    // Linha de topo das molduras (bem escura)
    readonly property color edgeLine: "#000000"
    // Cor de conteúdo sobre `foreground` (ex.: pílula do dia de hoje)
    readonly property color foregroundInk: "#111111"

    // Métricas
    readonly property int barHeight: 40
    readonly property int barRadius: 20
    readonly property int barMargin: 6
    readonly property int pillPadding: 14
    readonly property int spacing: 8
    readonly property int radius: 14

    // Fontes (instaladas no sistema)
    readonly property string fontFamily: "Roboto"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    // Fonte do nome da música (ilha e painel), fora do tema geral
    readonly property string musicFontFamily: "Noto Sans"

    // Largura da ilha parada no formato quadrado (o relógio fica centralizado
    // nela; fixa, não varia com o texto do relógio) — 175 + 3px de cada lado
    readonly property int pillIdleWidth: 181

    // Larguras dos painéis (a ilha se adapta a elas quando abrem)
    readonly property int notificationPanelWidth: 380
    readonly property int controlCenterPanelWidth: 540
    readonly property int musicPanelWidth: 420
    readonly property int cameraPanelWidth: 440
    readonly property int recentPanelWidth: 420

    // Tamanho máximo da moldura no morph de troca: as janelas dos painéis têm
    // esse tamanho fixo (transparentes + máscara) — a moldura interna é que
    // cresce/diminui, sem ser cortada pela janela.
    readonly property int panelMorphWidth: 540
    readonly property int panelMorphHeight: 540
    // Alturas próprias dos painéis de altura fixa
    readonly property int controlCenterPanelHeight: 464
    readonly property int recentPanelHeight: 352

    // Tela do painel da câmera (nome do monitor: "DP-1", "HDMI-A-1", ...).
    // Se o nome não existir no seu setup, cai na primeira tela.
    readonly property string cameraScreenName: "DP-1"

    // Monitor onde a ilha dinâmica aparece (nome do monitor). Se não existir
    // no seu setup, cai no primeiro monitor.
    readonly property string barScreenName: "DP-1"
}
