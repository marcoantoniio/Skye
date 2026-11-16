pragma Singleton

// Formatação compartilhada de números dos agentes. Puro, sem estado — usado
// pela ilha, pelos cartões e pelos adaptadores de provedor.

import Quickshell

Singleton {
    id: root

    function tokens(value) {
        const n = Math.max(0, Number(value) || 0);
        if (n < 1000)
            return String(Math.floor(n));
        if (n < 1000000)
            return (n < 10000 ? (n / 1000).toFixed(1) : String(Math.floor(n / 1000))) + "K";
        if (n < 1000000000)
            return (n / 1000000).toFixed(1) + "M";
        return (n / 1000000000).toFixed(1) + "B";
    }

    function cost(value) {
        const n = Number(value);
        if (!isFinite(n) || n <= 0)
            return "$0.00";
        if (n >= 10000)
            return "$" + (n / 1000).toFixed(1) + "K";
        return "$" + n.toFixed(n >= 100 ? 0 : 2);
    }

    function clock(seconds) {
        const total = Math.max(0, Math.floor(seconds));
        const two = (n) => (n < 10 ? "0" : "") + n;
        if (total >= 3600)
            return Math.floor(total / 3600) + ":" + two(Math.floor(total / 60) % 60) + ":" + two(total % 60);
        return Math.floor(total / 60) + ":" + two(total % 60);
    }
}
