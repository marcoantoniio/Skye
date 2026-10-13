//@ pragma UseQApplication
// Skye — shell Quickshell para CachyOS (Umbriel opcional)
// Rode com: qs -c skye
//
// Este arquivo é o ponto de entrada. Ele cria a barra no monitor principal
// (Theme.barScreenName) e força a inicialização dos singletons de serviço.

import Quickshell

ShellRoot {
    // Referenciar os singletons aqui força a criação deles na inicialização,
    // mesmo antes de algum widget precisar deles.
    readonly property var _notifications: Notifications.trackedNotifications
    readonly property var _workspaces: Workspaces.displayItems
    readonly property var _umbriel: Umbriel.workspaces
    readonly property var _i18n: I18n.language
    readonly property var _discord: DiscordPresence.clientId

    // A ilha dinâmica só no monitor principal (Theme.barScreenName); se o nome
    // não existir no setup, cai no primeiro monitor.
    Variants {
        model: {
            const ss = Quickshell.screens;
            for (let i = 0; i < ss.length; ++i)
                if (ss[i].name === Theme.barScreenName)
                    return [ss[i]];
            return ss.length > 0 ? [ss[0]] : [];
        }

        Bar {
            screen: modelData
        }
    }
}
