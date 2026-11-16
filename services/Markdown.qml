pragma Singleton

// Markdown mínimo para o chat: converte o subconjunto que os agentes usam
// (negrito, itálico, código, listas, títulos, tabelas e réguas) para o HTML
// que o Text em modo RichText entende. Puro, sem estado.

import Quickshell
import QtQuick

Singleton {
    id: root

    function escapeHtml(value) {
        return String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function colorHex(color) {
        const two = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0");
        return "#" + two(color.r * 255) + two(color.g * 255) + two(color.b * 255);
    }

    function inline(value) {
        let text = root.escapeHtml(value);
        const codes = [];
        // Código inline primeiro, com marcador, para não sofrer negrito/itálico.
        text = text.replace(/`([^`]+)`/g, (match, code) => {
            codes.push(code);
            return "\u0001" + (codes.length - 1) + "\u0001";
        });
        text = text.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        text = text.replace(/__([^_]+)__/g, "<b>$1</b>");
        text = text.replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<i>$2</i>");
        text = text.replace(/(^|[^_])_([^_\n]+)_/g, "$1<i>$2</i>");
        text = text.replace(/~~([^~]+)~~/g, "<s>$1</s>");
        text = text.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
        text = text.replace(/\u0001(\d+)\u0001/g, (match, index) => {
            return "<code>" + codes[Number(index)] + "</code>";
        });
        return text;
    }

    function splitRow(line) {
        let value = String(line).trim();
        if (value.startsWith("|"))
            value = value.slice(1);
        if (value.endsWith("|"))
            value = value.slice(0, -1);
        return value.split("|").map((cell) => cell.trim());
    }

    function isTableSeparator(line) {
        if (line === undefined || line.indexOf("|") < 0)
            return false;
        const cells = root.splitRow(line);
        if (cells.length === 0)
            return false;
        for (let i = 0; i < cells.length; ++i)
            if (!/^:?-{3,}:?$/.test(cells[i]))
                return false;
        return true;
    }

    function tableHtml(header, rows) {
        const border = root.colorHex(Theme.border);
        const head = root.colorHex(Theme.surfaceHover);
        let html = '<table border="1" cellspacing="0" cellpadding="4" style="border-color:' + border + '">';
        html += "<tr>";
        for (let i = 0; i < header.length; ++i)
            html += '<th align="left" bgcolor="' + head + '">' + root.inline(header[i]) + "</th>";
        html += "</tr>";
        for (let r = 0; r < rows.length; ++r) {
            html += "<tr>";
            for (let c = 0; c < header.length; ++c)
                html += "<td>" + root.inline(rows[r][c] || "") + "</td>";
            html += "</tr>";
        }
        return html + "</table>";
    }

    function isBlockStart(lines, index) {
        const line = lines[index];
        if (/^\s*```/.test(line))
            return true;
        if (/^\s*(#{1,6})\s+/.test(line))
            return true;
        if (/^\s*([-*_])\s*(\1\s*){2,}$/.test(line))
            return true;
        if (/^\s*>\s?/.test(line))
            return true;
        if (/^\s*([-*+]|\d+\.)\s+/.test(line))
            return true;
        if (line.indexOf("|") >= 0 && root.isTableSeparator(lines[index + 1]))
            return true;
        return false;
    }

    function toHtml(markdown) {
        const source = String(markdown === undefined || markdown === null ? "" : markdown)
            .replace(/\r\n/g, "\n");
        const lines = source.split("\n");
        const html = [];
        let i = 0;

        while (i < lines.length) {
            const line = lines[i];

            // Bloco de código ```
            if (/^\s*```/.test(line)) {
                i++;
                const code = [];
                while (i < lines.length && !/^\s*```/.test(lines[i])) {
                    code.push(lines[i]);
                    i++;
                }
                if (i < lines.length)
                    i++;
                html.push("<pre><code>" + root.escapeHtml(code.join("\n")) + "</code></pre>");
                continue;
            }

            // Tabela: cabeçalho + linha de separadores
            if (line.indexOf("|") >= 0 && root.isTableSeparator(lines[i + 1])) {
                const header = root.splitRow(line);
                i += 2;
                const rows = [];
                while (i < lines.length && lines[i].trim() !== "" && lines[i].indexOf("|") >= 0) {
                    rows.push(root.splitRow(lines[i]));
                    i++;
                }
                html.push(root.tableHtml(header, rows));
                continue;
            }

            // Título
            const heading = line.match(/^\s*(#{1,6})\s+(.*)$/);
            if (heading) {
                html.push("<p><b>" + root.inline(heading[2]) + "</b></p>");
                i++;
                continue;
            }

            // Régua horizontal
            if (/^\s*([-*_])\s*(\1\s*){2,}$/.test(line)) {
                html.push("<hr>");
                i++;
                continue;
            }

            // Citação
            if (/^\s*>\s?/.test(line)) {
                const quote = [];
                while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
                    quote.push(lines[i].replace(/^\s*>\s?/, ""));
                    i++;
                }
                html.push("<blockquote>" + root.toHtml(quote.join("\n")) + "</blockquote>");
                continue;
            }

            // Lista
            if (/^\s*([-*+]|\d+\.)\s+/.test(line)) {
                const ordered = /^\s*\d+\./.test(line);
                html.push(ordered ? "<ol>" : "<ul>");
                while (i < lines.length && /^\s*([-*+]|\d+\.)\s+/.test(lines[i])) {
                    const item = lines[i].replace(/^\s*([-*+]|\d+\.)\s+/, "");
                    html.push("<li>" + root.inline(item) + "</li>");
                    i++;
                }
                html.push(ordered ? "</ol>" : "</ul>");
                continue;
            }

            // Linha em branco
            if (line.trim() === "") {
                i++;
                continue;
            }

            // Parágrafo (até uma linha em branco ou início de bloco)
            const paragraph = [];
            while (i < lines.length && lines[i].trim() !== ""
                    && !root.isBlockStart(lines, i)) {
                paragraph.push(root.inline(lines[i]));
                i++;
            }
            html.push("<p>" + paragraph.join("<br>") + "</p>");
        }

        return html.join("");
    }
}
