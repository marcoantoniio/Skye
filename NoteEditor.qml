// Editor de notas com o modelo do Helix (seleção primeiro, modos normal/select).
//
// A seleção é um intervalo [âncora, cabeça) — como no Helix, o fim é exclusivo
// e um "cursor" é um ponto (âncora == cabeça) desenhado como um bloco de 1
// caractere. No modo NORMAL os movimentos SUBSTITUEM a seleção:
//   - h j k l, gh gl gs gg ge G: viram um cursor no destino;
//   - w b e W B E, f F t T: selecionam do cursor até o destino (sem incluir
//     o caractere de destino nos movimentos de palavra).
// `v` entra no modo SELECT: aí os mesmos movimentos ESTENDEM a seleção (a
// âncora fica fixa e só a cabeça anda), igual ao "v" do Helix.
// `;` recolhe, `Alt-;` inverte as pontas. Esc: no select volta ao normal;
// no normal recolhe a seleção; com um cursor só, sai da edição.
//
// Inserção: digita como um editor comum. Esc/Ctrl+c voltam ao normal
// selecionando o caractere anterior ao cursor. Enter continua listas;
// Shift+Enter quebra a linha.
//
// NORMAL / SELECT
//   h j k l            mover                  w b e / W B E    palavras / WORDs
//   f F t T <char>     achar no documento      gh gl gs         início/fim/1º texto
//   gg ge              topo / fim             G                ir para linha <n> (só com contagem)
//   setas Home End     0 $                    (0/$ são extras, não são do Helix)
//   d c y              apagar/alterar/copiar  p P              colar depois/antes
//   r <char>           trocar caractere       R                colar por cima
//   x X                linha / limites        %                tudo
//   ; Alt-;            recolher / inverter    ~ ` Alt-`        caixa
//   J                  juntar linhas          > <              indentar/dedentar
//   u U Ctrl+r         desfazer/refazer       / ? n N *        busca (regex)
//   i a I A o O        inserção               v                modo select
//   m i / m a <obj>    objetos de texto       m s / m d / m r  surround
//   m m                bracket                Alt-d / Alt-c    apagar/alterar sem copiar
//   contagens: 3j 5w 2f( 42G ...
//
// Sem suporte (não se aplicam a um editor embutido de notas): multi-seleção
// (s, S, C, K), LSP/tree-sitter, macros (Q/q), registradores (") e shell (| ! $).

import QtQuick

FocusScope {
    id: root

    // ---- estado ----
    property string mode: "insert" // "insert" | "normal" | "select"
    property string pending: ""    // prefixo pendente (g, m, mi, ma, ms, md, mr, mr2, f, F, t, T, r)
    property string pendingChar: "" // primeiro char do mr
    property int count: 0          // contagem de movimento/ação
    property int goalCol: -1       // coluna desejada para j/k (persiste entre verticais)
    property string register: ""   // texto copiado (y/d/c)
    property string lastSearch: ""
    property bool searchBackward: false
    property bool searching: false
    property bool syncing: false
    property bool _loading: false

    // seleção como limites: [anchor, head) — âncora e cabeça
    property int anchor: 0
    property int head: 0

    readonly property alias text: editor.text
    readonly property string modeLabel: mode === "insert"
        ? "INS"
        : (mode === "select" ? "SEL" : (pending !== "" ? "NOR " + pending : "NOR"))

    signal edited(string text)
    signal done()

    // sai da edição quando o foco deixa o editor (painel fechou, clique fora...)
    onActiveFocusChanged: {
        if (!activeFocus) {
            Qt.callLater(function () {
                if (!root.activeFocus) {
                    searching = false;
                    done();
                }
            });
        }
    }

    onSearchingChanged: {
        if (searching) {
            searchField.text = "";
            Qt.callLater(function () { searchField.forceActiveFocus(); });
        } else {
            editor.forceActiveFocus();
            syncSel();
        }
    }

    // ---- ciclo de vida ----
    function load(t) {
        _loading = true;
        editor.text = t;
        _loading = false;
        mode = "insert";
        pending = "";
        count = 0;
        goalCol = -1;
        anchor = 0;
        head = editor.length;
        editor.deselect();
        editor.cursorPosition = editor.length;
    }

    function begin() {
        mode = "insert";
        pending = "";
        count = 0;
        goalCol = -1;
        editor.forceActiveFocus();
        editor.deselect();
        editor.cursorPosition = editor.length;
        anchor = 0;
        head = editor.length;
    }

    // ---- posições ----
    function from() {
        return Math.min(anchor, head);
    }

    function to() {
        return Math.max(anchor, head);
    }

    function isPoint() {
        return anchor === head;
    }

    // caractere sob o cursor (bloco de 1)
    function cursorChar() {
        if (editor.length === 0)
            return 0;
        const p = head > anchor ? head - 1 : head;
        return Math.max(0, Math.min(editor.length - 1, p));
    }

    function clampChar(p) {
        if (editor.length === 0)
            return 0;
        return Math.max(0, Math.min(editor.length - 1, p));
    }

    function clampB(p) {
        return Math.max(0, Math.min(editor.length, p));
    }

    function lineStart(pos) {
        if (pos <= 0)
            return 0;
        const i = editor.text.lastIndexOf("\n", pos - 1);
        return i + 1;
    }

    function lineEnd(pos) {
        const i = editor.text.indexOf("\n", pos);
        return i === -1 ? editor.text.length : i;
    }

    // último caractere "de conteúdo" da linha
    function lineEndInclusive(pos) {
        const s = lineStart(pos);
        const e = lineEnd(pos);
        return e > s ? e - 1 : s;
    }

    // ---- seleção ----
    function syncSel() {
        anchor = clampB(anchor);
        head = clampB(head);
        if (editor.length === 0) {
            anchor = 0;
            head = 0;
            syncing = true;
            editor.deselect();
            editor.cursorPosition = 0;
            syncing = false;
            return;
        }
        syncing = true;
        if (to() > from()) {
            editor.select(from(), to());
        } else if (from() < editor.length) {
            editor.select(from(), from() + 1); // cursor em bloco de 1
        } else {
            editor.deselect();
            editor.cursorPosition = editor.length;
        }
        syncing = false;
    }

    function setRange(a, b) {
        goalCol = -1;
        anchor = clampB(a);
        head = clampB(b);
        syncSel();
    }

    function pointAt(p) {
        const b = clampB(p);
        goalCol = -1;
        anchor = b;
        head = b;
        syncSel();
    }

    // faixa efetiva da seleção para operadores (ponto = 1 caractere)
    function opStart() {
        return from();
    }

    function opEnd() {
        const a = from();
        const b = to();
        if (b > a)
            return b;
        return Math.min(editor.length, a + 1);
    }

    function takeCount() {
        const n = count > 0 ? count : 1;
        count = 0;
        return n;
    }

    function resetPending() {
        pending = "";
        pendingChar = "";
        count = 0;
    }

    // ---- mutações (preservam o undo do TextEdit) ----
    function rem(start, end) {
        if (start >= end)
            return;
        syncing = true;
        editor.remove(start, end);
        syncing = false;
    }

    function ins(pos, str) {
        if (str === "")
            return;
        syncing = true;
        editor.insert(pos, str);
        syncing = false;
    }

    function replaceRange(start, end, str) {
        rem(start, end);
        ins(start, str);
    }

    // ---- classificação de caracteres ----
    function isSpace(c) {
        return c === " " || c === "\t" || c === "\n" || c === "\r";
    }

    function isWordChar(c) {
        return /[A-Za-z0-9_À-ÿ]/.test(c);
    }

    function classOf(c) {
        return isSpace(c) ? 0 : (isWordChar(c) ? 1 : 2);
    }

    // a cabeça (limite) está no início de uma palavra? (regra de âncora do b/B)
    function headAtWordStart() {
        const t = editor.text;
        const hb = head;
        if (hb <= 0)
            return true;
        if (hb >= t.length)
            return false;
        if (isSpace(t[hb]))
            return true;
        if (isSpace(t[hb - 1]))
            return true;
        return classOf(t[hb - 1]) !== classOf(t[hb]);
    }

    // ---- movimentos de caractere ----
    function moveChar(delta) {
        if (editor.length === 0)
            return;
        const c = cursorChar();
        const t = c + delta;
        if (delta > 0 ? t >= editor.length : t < 0)
            return;
        if (mode !== "select") {
            pointAt(t);
            return;
        }
        if (delta > 0) {
            head = isPoint() ? Math.min(editor.length, c + 2)
                             : Math.min(editor.length, head + 1);
        } else {
            if (isPoint()) {
                anchor = Math.min(editor.length, c + 1);
                head = Math.max(0, c - 1);
            } else {
                head = Math.max(0, head - 1);
            }
        }
        goalCol = -1;
        syncSel();
    }

    // movimento para um caractere (gh/gl/gg/ge/G/Home/End/0/$...)
    function moveTo(target, includeForward) {
        if (editor.length === 0)
            return;
        const t = clampChar(target);
        if (mode !== "select") {
            pointAt(t);
            return;
        }
        const c = cursorChar();
        if (isPoint()) {
            if (t >= c) {
                head = Math.min(editor.length, t + (includeForward ? 1 : 0));
            } else {
                anchor = Math.min(editor.length, c + 1);
                head = t;
            }
        } else {
            head = t >= c
                ? Math.min(editor.length, t + (includeForward ? 1 : 0))
                : t;
        }
        goalCol = -1;
        syncSel();
    }

    // ---- movimentos verticais ----
    function moveVertical(dir, n) {
        if (editor.length === 0)
            return;
        const c0 = cursorChar();
        if (goalCol < 0)
            goalCol = c0 - lineStart(c0);
        let p = c0;
        for (let i = 0; i < n; i++) {
            if (dir > 0) {
                const le = lineEnd(p);
                if (le >= editor.length)
                    break;
                const ns = le + 1;
                p = Math.min(ns + goalCol, lineEndInclusive(ns));
            } else {
                const ls = lineStart(p);
                if (ls === 0)
                    break;
                const ps = lineStart(ls - 1);
                p = Math.min(ps + goalCol, lineEndInclusive(ps));
            }
        }
        if (p === c0)
            return;
        if (mode !== "select") {
            pointAt(p);
            return;
        }
        const c = cursorChar();
        if (isPoint()) {
            if (p >= c) {
                head = Math.min(editor.length, p + 1);
            } else {
                anchor = Math.min(editor.length, c + 1);
                head = p;
            }
        } else {
            head = p >= c ? Math.min(editor.length, p + 1) : p;
        }
        syncSel();
    }

    function firstNonBlankPos() {
        const s = lineStart(selChar());
        const e = lineEnd(selChar());
        let p = s;
        while (p < e && (editor.text[p] === " " || editor.text[p] === "\t"))
            p++;
        return p;
    }

    function selChar() {
        return cursorChar();
    }

    function gotoLineChar(n) {
        let p = 0;
        for (let i = 1; i < n; i++) {
            const e = lineEnd(p);
            if (e >= editor.length)
                break;
            p = e + 1;
        }
        return p;
    }

    function lastLineStart() {
        const t = editor.text;
        if (t.length === 0)
            return 0;
        let end = t.length;
        if (t[end - 1] === "\n")
            end -= 1;
        if (end === 0)
            return 0;
        return lineStart(end - 1);
    }

    // ---- movimentos de palavra ----
    function nextWordStart(p, big) {
        const t = editor.text;
        const n = t.length;
        if (n === 0)
            return 0;
        if (p >= n)
            return n;
        let q = p;
        if (!isSpace(t[q])) {
            const c = classOf(t[q]);
            while (q < n && !isSpace(t[q]) && (big || classOf(t[q]) === c))
                q++;
        }
        while (q < n && isSpace(t[q]))
            q++;
        return q; // limite após o início da palavra (pode ser n)
    }

    function prevWordStart(p, big) {
        const t = editor.text;
        const n = t.length;
        if (n === 0)
            return 0;
        let q = Math.min(p, n - 1) - 1;
        while (q > 0 && isSpace(t[q]))
            q--;
        if (q < 0)
            return 0;
        if (big) {
            while (q > 0 && !isSpace(t[q - 1]))
                q--;
        } else {
            const c = classOf(t[q]);
            while (q > 0 && !isSpace(t[q - 1]) && classOf(t[q - 1]) === c)
                q--;
        }
        return q;
    }

    function nextWordEnd(p, big) {
        const t = editor.text;
        const n = t.length;
        if (n === 0)
            return 0;
        if (p >= n - 1)
            return n - 1;
        let q = p + 1;
        while (q < n && isSpace(t[q]))
            q++;
        if (q >= n)
            return n - 1;
        if (big) {
            while (q < n - 1 && !isSpace(t[q + 1]))
                q++;
        } else {
            const c = classOf(t[q]);
            while (q < n - 1 && !isSpace(t[q + 1]) && classOf(t[q + 1]) === c)
                q++;
        }
        return q;
    }

    function wordMove(kind, n) {
        if (editor.length === 0)
            return;
        const len = editor.length;
        const c = cursorChar();
        const forward = kind === "w" || kind === "e" || kind === "W" || kind === "E";
        let target;
        if (forward) {
            let p = Math.min(len, c + 1);
            for (let i = 0; i < n; i++) {
                let q;
                if (kind === "w")
                    q = nextWordStart(p, false);
                else if (kind === "e")
                    q = Math.min(len, nextWordEnd(p, false) + 1);
                else if (kind === "W")
                    q = nextWordStart(p, true);
                else
                    q = Math.min(len, nextWordEnd(p, true) + 1);
                if (q === p)
                    break;
                p = q;
            }
            target = p;
        } else {
            let p = c;
            for (let i = 0; i < n; i++) {
                const q = prevWordStart(p, kind === "B");
                if (q === p)
                    break;
                p = q;
            }
            target = p;
        }
        if (target === head)
            return;

        if (mode === "select") {
            if (isPoint() && !forward)
                anchor = headAtWordStart() ? head : Math.min(len, head + 1);
            head = target;
            goalCol = -1;
            syncSel();
            return;
        }

        // normal: nova seleção a partir do cursor (mantém a direção)
        let a;
        if (forward) {
            a = c;
            if (isSpace(editor.text[c]) && c + 1 < len && !isSpace(editor.text[c + 1]))
                a = c + 1;
        } else {
            a = headAtWordStart() ? head : Math.min(len, head + 1);
        }
        anchor = a;
        head = target;
        goalCol = -1;
        syncSel();
    }

    // f/F = até o caractere; t/T = antes/depois dele (documento todo, sem wrap)
    function findChar(ch, forward, till, n) {
        const t = editor.text;
        const len = t.length;
        if (len === 0)
            return;
        const c = cursorChar();
        let start = c + (forward ? 1 : -1);
        if (till)
            start += forward ? 1 : -1;
        let found = -1;
        for (let i = 0; i < n; i++) {
            found = -1;
            if (forward) {
                for (let q = start; q < len; q++) {
                    if (t[q] === ch) {
                        found = q;
                        break;
                    }
                }
            } else {
                for (let q = start; q >= 0; q--) {
                    if (t[q] === ch) {
                        found = q;
                        break;
                    }
                }
            }
            if (found === -1)
                break;
            start = forward ? found + 1 : found - 1;
        }
        if (found === -1)
            return;
        const target = forward
            ? (till ? found : found + 1)
            : (till ? found + 1 : found);
        if (mode === "select") {
            head = target;
            goalCol = -1;
            syncSel();
            return;
        }
        anchor = c;
        head = target;
        goalCol = -1;
        syncSel();
    }

    // ---- linhas ----
    function extendLine() {
        if (editor.length === 0)
            return;
        const c = cursorChar();
        const ls = lineStart(c);
        const le = lineEnd(c);
        let end = le < editor.length ? le + 1 : le;
        if (from() === ls && to() >= end && end < editor.length) {
            const le2 = lineEnd(end);
            end = le2 < editor.length ? le2 + 1 : le2;
        }
        setRange(ls, end);
    }

    function extendToLineBounds() {
        if (editor.length === 0)
            return;
        const a = lineStart(from());
        const b = lineEnd(clampChar(Math.max(from(), to() - 1)));
        setRange(a, b);
    }

    // ---- edição ----
    function deleteSelection(yank) {
        if (editor.length === 0)
            return;
        const a = opStart();
        const b = opEnd();
        if (yank !== false)
            register = editor.text.slice(a, b);
        replaceRange(a, b, "");
        if (editor.length === 0) {
            pointAt(0);
            return;
        }
        pointAt(Math.min(a, editor.length - 1));
    }

    function changeSelection(yank) {
        if (editor.length === 0) {
            enterInsert(0);
            return;
        }
        const a = opStart();
        const b = opEnd();
        if (yank !== false)
            register = editor.text.slice(a, b);
        replaceRange(a, b, "");
        enterInsert(Math.min(a, editor.length));
    }

    function yankSelection() {
        if (editor.length === 0)
            return;
        register = editor.text.slice(opStart(), opEnd());
    }

    function pasteSelection(after) {
        if (register === "")
            return;
        const len = editor.length;
        let pos;
        if (after)
            pos = isPoint() ? Math.min(len, cursorChar() + 1) : to();
        else
            pos = from();
        ins(pos, register);
        setRange(pos, Math.min(editor.length, pos + register.length));
    }

    function replaceWithRegister() {
        if (register === "")
            return;
        const a = opStart();
        replaceRange(a, opEnd(), register);
        setRange(a, Math.min(editor.length, a + register.length));
    }

    function replaceChars(ch) {
        if (editor.length === 0)
            return;
        const a = opStart();
        const b = opEnd();
        let out = "";
        for (let i = a; i < b; i++)
            out += editor.text[i] === "\n" ? "\n" : ch;
        replaceRange(a, b, out);
        setRange(a, Math.min(editor.length, a + out.length));
    }

    function changeCase(up) {
        if (editor.length === 0)
            return;
        const a = opStart();
        const b = opEnd();
        let out = "";
        for (let i = a; i < b; i++) {
            const c = editor.text[i];
            out += up ? c.toUpperCase() : c.toLowerCase();
        }
        replaceRange(a, b, out);
        setRange(a, Math.min(editor.length, a + out.length));
    }

    function toggleCase() {
        if (editor.length === 0)
            return;
        const a = opStart();
        const b = opEnd();
        let out = "";
        for (let i = a; i < b; i++) {
            const c = editor.text[i];
            const lo = c.toLowerCase();
            const up = c.toUpperCase();
            out += (lo === up) ? c : (c === up ? lo : up);
        }
        replaceRange(a, b, out);
        setRange(a, Math.min(editor.length, a + out.length));
    }

    // junta as linhas da seleção (ou a linha atual com a seguinte)
    function joinLines() {
        if (editor.length === 0)
            return;
        const first = lineStart(from());
        let last = lineStart(clampChar(Math.max(from(), to() - 1)));
        if (last <= first) {
            const le = lineEnd(first);
            if (le >= editor.length)
                return;
            last = le + 1;
        }
        const lines = [];
        let p = first;
        while (true) {
            lines.push(p);
            if (p >= last)
                break;
            const le = lineEnd(p);
            if (le >= editor.length)
                break;
            p = le + 1;
        }
        for (let i = lines.length - 1; i >= 1; i--) {
            let q = lines[i];
            while (q < editor.length && (editor.text[q] === " " || editor.text[q] === "\t"))
                q++;
            replaceRange(lines[i] - 1, q, " ");
        }
        setRange(first, Math.min(editor.length, lineEnd(first) >= editor.length
            ? editor.length : lineEndInclusive(first) + 1));
    }

    function indentSelection(dedent) {
        if (editor.length === 0)
            return;
        const first = lineStart(from());
        const lastLine = lineStart(clampChar(Math.max(from(), to() - 1)));
        const starts = [];
        let p = first;
        while (true) {
            starts.push(p);
            if (p >= lastLine)
                break;
            const le = lineEnd(p);
            if (le >= editor.length)
                break;
            p = le + 1;
        }
        for (let i = starts.length - 1; i >= 0; i--) {
            const s2 = starts[i];
            if (dedent) {
                let nn = 0;
                while (nn < 2 && editor.text[s2 + nn] === " ")
                    nn++;
                rem(s2, s2 + nn);
            } else {
                ins(s2, "  ");
            }
        }
        let ne = first;
        for (let i = 1; i < starts.length; i++) {
            const le = lineEnd(ne);
            if (le >= editor.length)
                break;
            ne = le + 1;
        }
        setRange(first, Math.min(editor.length, lineEndInclusive(ne) + 1));
    }

    // ---- objetos de texto ----
    function wordBounds(pos) {
        const t = editor.text;
        if (t.length === 0)
            return null;
        let p = pos;
        if (isSpace(t[p])) {
            while (p < t.length && isSpace(t[p]))
                p++;
            if (p >= t.length)
                return null;
        }
        const c = classOf(t[p]);
        let s = p;
        let e = p;
        while (s > 0 && !isSpace(t[s - 1]) && classOf(t[s - 1]) === c)
            s--;
        while (e < t.length - 1 && !isSpace(t[e + 1]) && classOf(t[e + 1]) === c)
            e++;
        return { s: s, e: e };
    }

    function aroundWordBounds(pos) {
        const wb = wordBounds(pos);
        if (!wb)
            return null;
        const t = editor.text;
        let s = wb.s;
        let e = wb.e;
        let ee = e;
        while (ee < t.length - 1 && (t[ee + 1] === " " || t[ee + 1] === "\t"))
            ee++;
        if (ee === e) {
            while (s > 0 && (t[s - 1] === " " || t[s - 1] === "\t"))
                s--;
        } else {
            e = ee;
        }
        return { s: s, e: e };
    }

    function quoteBounds(pos, q, around) {
        const t = editor.text;
        const ls = lineStart(pos);
        const le = lineEnd(pos);
        const positions = [];
        for (let i = ls; i < le; i++) {
            if (t[i] !== q)
                continue;
            let bs = 0;
            let j = i - 1;
            while (j >= ls && t[j] === "\\") {
                bs++;
                j--;
            }
            if (bs % 2 === 0)
                positions.push(i);
        }
        for (let i = 0; i + 1 < positions.length; i += 2) {
            const a = positions[i];
            const b = positions[i + 1];
            if (pos >= a && pos <= b) {
                return around
                    ? { s: a, e: b }
                    : { s: a + 1, e: b - 1 };
            }
        }
        return null;
    }

    function bracketBounds(pos, open, close, around) {
        const t = editor.text;
        let depth = 0;
        for (let i = pos; i >= 0; i--) {
            if (t[i] === close) {
                if (i !== pos)
                    depth++;
            } else if (t[i] === open) {
                if (depth === 0) {
                    let d = 0;
                    for (let j = i + 1; j < t.length; j++) {
                        if (t[j] === open) {
                            d++;
                        } else if (t[j] === close) {
                            if (d === 0) {
                                return around
                                    ? { s: i, e: j }
                                    : { s: i + 1, e: j - 1 };
                            }
                            d--;
                        }
                    }
                    return null;
                }
                depth--;
            }
        }
        return null;
    }

    function textObjectBounds(kind, ch) {
        if (editor.length === 0)
            return null;
        const around = kind === "a";
        const p = cursorChar();
        if (ch === "w" || ch === "W")
            return around ? aroundWordBounds(p) : wordBounds(p);
        if (ch === '"' || ch === "'" || ch === "`")
            return quoteBounds(p, ch, around);
        if (ch === "(" || ch === ")" || ch === "b")
            return bracketBounds(p, "(", ")", around);
        if (ch === "[" || ch === "]")
            return bracketBounds(p, "[", "]", around);
        if (ch === "{" || ch === "}" || ch === "B")
            return bracketBounds(p, "{", "}", around);
        if (ch === "<" || ch === ">")
            return bracketBounds(p, "<", ">", around);
        return null;
    }

    function matchBracket() {
        if (editor.length === 0)
            return;
        const t = editor.text;
        const p = cursorChar();
        const c = t[p];
        const opens = { "(": ")", "[": "]", "{": "}", "<": ">" };
        const closes = { ")": "(", "]": "[", "}": "{", ">": "<" };
        if (opens[c]) {
            let d = 0;
            for (let j = p + 1; j < t.length; j++) {
                if (t[j] === c) {
                    d++;
                } else if (t[j] === opens[c]) {
                    if (d === 0) {
                        setRange(p, j + 1);
                        return;
                    }
                    d--;
                }
            }
        } else if (closes[c]) {
            let d = 0;
            for (let j = p - 1; j >= 0; j--) {
                if (t[j] === c) {
                    d++;
                } else if (t[j] === closes[c]) {
                    if (d === 0) {
                        setRange(j, p + 1);
                        return;
                    }
                    d--;
                }
            }
        } else {
            const bb = bracketBounds(p, "(", ")", true)
                || bracketBounds(p, "[", "]", true)
                || bracketBounds(p, "{", "}", true);
            if (bb)
                setRange(bb.s, bb.e + 1);
        }
    }

    // ---- surround ----
    function surroundPair(ch) {
        switch (ch) {
        case "(":
        case ")":
            return ["(", ")"];
        case "[":
        case "]":
            return ["[", "]"];
        case "{":
        case "}":
            return ["{", "}"];
        case "<":
        case ">":
            return ["<", ">"];
        default:
            return [ch, ch];
        }
    }

    function surroundAdd(ch) {
        if (editor.length === 0 || ch.length !== 1)
            return;
        const pair = surroundPair(ch);
        const a = opStart();
        const b = opEnd();
        ins(b, pair[1]);
        ins(a, pair[0]);
        setRange(a + 1, b + 1);
    }

    function surroundDelete(ch) {
        if (editor.length === 0 || ch.length !== 1)
            return;
        const pair = surroundPair(ch);
        const a = opStart();
        const b = opEnd();
        if (a > 0 && b < editor.length
                && editor.text[a - 1] === pair[0] && editor.text[b] === pair[1]) {
            rem(b, b + 1);
            rem(a - 1, a);
            setRange(a - 1, b - 1);
        }
    }

    function surroundReplace(fromCh, toCh) {
        if (editor.length === 0 || fromCh.length !== 1 || toCh.length !== 1)
            return;
        const oldPair = surroundPair(fromCh);
        const newPair = surroundPair(toCh);
        const a = opStart();
        const b = opEnd();
        if (a > 0 && b < editor.length
                && editor.text[a - 1] === oldPair[0] && editor.text[b] === oldPair[1]) {
            rem(b, b + 1);
            rem(a - 1, a);
            ins(a - 1, newPair[0]);
            ins(b, newPair[1]);
            setRange(a, b);
        }
    }

    // ---- busca (regex, smart case) ----
    function escapeRegex(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    function searchRegex() {
        const smart = lastSearch !== lastSearch.toUpperCase();
        try {
            return new RegExp(lastSearch, smart ? "gi" : "g");
        } catch (e) {
            return new RegExp(escapeRegex(lastSearch), smart ? "gi" : "g");
        }
    }

    function searchNext(backward) {
        if (lastSearch === "")
            return;
        const t = editor.text;
        if (t.length === 0)
            return;
        const re = searchRegex();
        const matches = [];
        let m;
        while ((m = re.exec(t)) !== null) {
            matches.push([m.index, m.index + m[0].length]);
            if (m[0].length === 0)
                re.lastIndex++;
        }
        if (matches.length === 0)
            return;
        let idx = -1;
        if (backward) {
            for (let i = matches.length - 1; i >= 0; i--) {
                if (matches[i][0] < from()) {
                    idx = i;
                    break;
                }
            }
            if (idx === -1)
                idx = matches.length - 1;
        } else {
            for (let i = 0; i < matches.length; i++) {
                if (matches[i][0] >= to()) {
                    idx = i;
                    break;
                }
            }
            if (idx === -1)
                idx = 0;
        }
        setRange(matches[idx][0], matches[idx][1]);
    }

    function searchSelection() {
        if (editor.length === 0)
            return;
        let needle = editor.text.slice(opStart(), opEnd());
        if (needle.length <= 1 || /^\W+$/.test(needle)) {
            const b = wordBounds(cursorChar());
            if (b)
                needle = editor.text.slice(b.s, b.e + 1);
        }
        needle = needle.replace(/\n/g, " ");
        if (needle === "")
            return;
        lastSearch = (isWordChar(needle[0]) ? "\\b" : "")
            + escapeRegex(needle)
            + (isWordChar(needle[needle.length - 1]) ? "\\b" : "");
        searchNext(false);
    }

    function beginSearch(backward) {
        searchBackward = backward;
        searching = true;
    }

    function commitSearch() {
        const q = searchField.text;
        searching = false;
        if (q !== "") {
            lastSearch = q;
            searchNext(searchBackward);
        }
        syncSel();
    }

    function cancelSearch() {
        searching = false;
        syncSel();
    }

    // ---- inserção ----
    function enterInsert(pos) {
        const p = Math.max(0, Math.min(editor.length, pos));
        mode = "insert";
        pending = "";
        count = 0;
        goalCol = -1;
        anchor = p;
        head = p;
        syncing = true;
        editor.deselect();
        editor.cursorPosition = p;
        syncing = false;
        editor.forceActiveFocus();
    }

    function enterNormal() {
        mode = "normal";
        pending = "";
        count = 0;
        goalCol = -1;
        const p = editor.cursorPosition;
        pointAt(editor.length === 0 ? 0 : Math.max(0, Math.min(editor.length - 1, p > 0 ? p - 1 : 0)));
    }

    function openLine(below) {
        if (below) {
            const le = lineEnd(cursorChar());
            if (le < editor.length) {
                ins(le + 1, "\n");
                enterInsert(le + 1);
            } else {
                ins(editor.length, "\n");
                enterInsert(editor.length);
            }
        } else {
            const s = lineStart(cursorChar());
            ins(s, "\n");
            enterInsert(s);
        }
    }

    // Enter em lista: cria o próximo item (4 → 5; "- item" → "- ")
    function autoContinueList() {
        const pos = editor.cursorPosition;
        const before = editor.text.slice(0, pos);
        const lineStartPos = before.lastIndexOf("\n") + 1;
        const line = before.slice(lineStartPos);

        let m = line.match(/^(\s*)(\d+)([.)])\s+(.*)$/);
        if (m) {
            if (m[4].trim() === "") {
                rem(lineStartPos, pos);
                ins(lineStartPos, "\n");
                editor.cursorPosition = lineStartPos + 1;
            } else {
                const next = "\n" + m[1] + (Number(m[2]) + 1) + m[3] + " ";
                ins(pos, next);
                editor.cursorPosition = pos + next.length;
            }
            return;
        }

        m = line.match(/^(\s*)([-*])\s+(.*)$/);
        if (m) {
            if (m[3].trim() === "") {
                rem(lineStartPos, pos);
                ins(lineStartPos, "\n");
                editor.cursorPosition = lineStartPos + 1;
            } else {
                const next = "\n" + m[1] + m[2] + " ";
                ins(pos, next);
                editor.cursorPosition = pos + next.length;
            }
            return;
        }

        ins(pos, "\n");
        editor.cursorPosition = pos + 1;
    }

    // ---- resolução de prefixos ----
    function resolvePending(k, ch) {
        const p = pending;

        if (k === Qt.Key_Escape) {
            resetPending();
            return;
        }

        if (p === "g") {
            if (ch === "g")
                moveTo(0, false);
            else if (ch === "e")
                moveTo(lastLineStart(), true);
            else if (ch === "h")
                moveTo(lineStart(cursorChar()), true);
            else if (ch === "l")
                moveTo(lineEndInclusive(cursorChar()), true);
            else if (ch === "s")
                moveTo(firstNonBlankPos(), true);
            resetPending();
            return;
        }

        if (p === "m") {
            if (ch === "i") {
                pending = "mi";
                return;
            }
            if (ch === "a") {
                pending = "ma";
                return;
            }
            if (ch === "s") {
                pending = "ms";
                return;
            }
            if (ch === "d") {
                pending = "md";
                return;
            }
            if (ch === "r") {
                pending = "mr";
                return;
            }
            if (ch === "m") {
                matchBracket();
                resetPending();
                return;
            }
            resetPending();
            return;
        }

        if (p === "mi" || p === "ma") {
            const b = textObjectBounds(p === "mi" ? "i" : "a", ch);
            if (b && b.e >= b.s)
                setRange(b.s, b.e + 1);
            resetPending();
            return;
        }

        if (p === "ms") {
            surroundAdd(ch);
            resetPending();
            return;
        }

        if (p === "md") {
            surroundDelete(ch);
            resetPending();
            return;
        }

        if (p === "mr") {
            if (ch.length === 1) {
                pendingChar = ch;
                pending = "mr2";
                return;
            }
            resetPending();
            return;
        }

        if (p === "mr2") {
            surroundReplace(pendingChar, ch);
            resetPending();
            return;
        }

        if (p === "f" || p === "F" || p === "t" || p === "T") {
            if (ch.length === 1)
                findChar(ch, p === "f" || p === "t", p === "t" || p === "T", takeCount());
            resetPending();
            return;
        }

        if (p === "r") {
            if (ch.length === 1 && ch !== "\n")
                replaceChars(ch);
            resetPending();
            return;
        }

        resetPending();
    }

    // ---- teclado ----
    function handleKey(event) {
        const k = event.key;
        const ch = event.text;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

        if (mode === "insert") {
            if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_C)) {
                enterNormal();
                event.accepted = true;
                return;
            }
            if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !shift) {
                autoContinueList();
                event.accepted = true;
            }
            return; // restante: o TextEdit digita normalmente
        }

        // ---- normal / select ----
        if (k === Qt.Key_Escape) {
            resetPending();
            if (mode === "select") {
                mode = "normal";
            } else if (!isPoint()) {
                pointAt(cursorChar());
            } else {
                done();
            }
            event.accepted = true;
            return;
        }

        if (alt && (ch === ";" || k === Qt.Key_Semicolon)) {
            const a = anchor;
            anchor = head;
            head = a;
            syncSel();
            resetPending();
            event.accepted = true;
            return;
        }

        if (pending !== "") {
            resolvePending(k, ch);
            event.accepted = true;
            return;
        }

        if (ctrl && k === Qt.Key_R) {
            editor.redo();
            event.accepted = true;
            return;
        }

        if (ctrl && k === Qt.Key_C) {
            event.accepted = true;
            return;
        }

        // contagem (0 sozinho é início de linha)
        if (ch >= "0" && ch <= "9" && !alt && !ctrl) {
            const d = Number(ch);
            if (!(d === 0 && count === 0)) {
                count = count * 10 + d;
                event.accepted = true;
                return;
            }
        }

        if (k === Qt.Key_Left) {
            moveChar(-takeCount());
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Right) {
            moveChar(takeCount());
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Up) {
            moveVertical(-1, takeCount());
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Down) {
            moveVertical(1, takeCount());
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Home) {
            moveTo(lineStart(cursorChar()), true);
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_End) {
            moveTo(lineEndInclusive(cursorChar()), true);
            event.accepted = true;
            return;
        }

        if (alt && (ch === "d" || k === Qt.Key_D)) {
            deleteSelection(false);
            resetPending();
            event.accepted = true;
            return;
        }
        if (alt && (ch === "c" || k === Qt.Key_C)) {
            changeSelection(false);
            resetPending();
            event.accepted = true;
            return;
        }
        if (alt && (ch === "`" || k === Qt.Key_QuoteLeft)) {
            changeCase(true);
            resetPending();
            event.accepted = true;
            return;
        }

        if (ch.length !== 1) {
            event.accepted = true;
            return;
        }

        switch (ch) {
        case "h":
            moveChar(-takeCount());
            break;
        case "l":
            moveChar(takeCount());
            break;
        case "j":
            moveVertical(1, takeCount());
            break;
        case "k":
            moveVertical(-1, takeCount());
            break;
        case "w":
            wordMove("w", takeCount());
            break;
        case "b":
            wordMove("b", takeCount());
            break;
        case "e":
            wordMove("e", takeCount());
            break;
        case "W":
            wordMove("W", takeCount());
            break;
        case "B":
            wordMove("B", takeCount());
            break;
        case "E":
            wordMove("E", takeCount());
            break;
        case "0":
            moveTo(lineStart(cursorChar()), true);
            break;
        case "$":
            moveTo(lineEndInclusive(cursorChar()), true);
            break;
        case "g":
            pending = "g";
            event.accepted = true;
            return;
        case "m":
            pending = "m";
            event.accepted = true;
            return;
        case "f":
            pending = "f";
            event.accepted = true;
            return;
        case "F":
            pending = "F";
            event.accepted = true;
            return;
        case "t":
            pending = "t";
            event.accepted = true;
            return;
        case "T":
            pending = "T";
            event.accepted = true;
            return;
        case "r":
            pending = "r";
            event.accepted = true;
            return;
        case "v":
            mode = mode === "select" ? "normal" : "select";
            resetPending();
            event.accepted = true;
            return;
        case "G":
            if (count > 0)
                moveTo(gotoLineChar(takeCount()), true);
            break;
        case "d":
            deleteSelection(true);
            break;
        case "c":
            changeSelection(true);
            break;
        case "y":
            yankSelection();
            break;
        case "p":
            pasteSelection(true);
            break;
        case "P":
            pasteSelection(false);
            break;
        case "R":
            replaceWithRegister();
            break;
        case "~":
            toggleCase();
            break;
        case "`":
            changeCase(false);
            break;
        case "J":
            joinLines();
            break;
        case ">":
            indentSelection(false);
            break;
        case "<":
            indentSelection(true);
            break;
        case "u":
            editor.undo();
            break;
        case "U":
            editor.redo();
            break;
        case ";":
            pointAt(cursorChar());
            break;
        case "x":
            extendLine();
            break;
        case "X":
            extendToLineBounds();
            break;
        case "%":
            setRange(0, editor.length);
            break;
        case "*":
            searchSelection();
            break;
        case "/":
            beginSearch(false);
            break;
        case "?":
            beginSearch(true);
            break;
        case "n":
            searchNext(false);
            break;
        case "N":
            searchNext(true);
            break;
        case "i":
            enterInsert(from());
            break;
        case "a":
            enterInsert(isPoint() ? Math.min(editor.length, cursorChar() + 1) : to());
            break;
        case "I":
            enterInsert(lineStart(cursorChar()));
            break;
        case "A":
            enterInsert(lineEnd(cursorChar()));
            break;
        case "o":
            openLine(true);
            break;
        case "O":
            openLine(false);
            break;
        default:
            event.accepted = true;
            return;
        }
        resetPending();
        event.accepted = true;
    }

    // ---- editor ----
    TextEdit {
        id: editor

        anchors.fill: parent
        color: Theme.foreground
        selectionColor: Theme.accent
        selectedTextColor: Theme.background
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: TextEdit.Wrap
        selectByMouse: root.mode === "insert"
        clip: true
        onTextChanged: {
            if (!root._loading)
                root.edited(text);
        }
        onCursorPositionChanged: {
            if (root.syncing || root.mode === "insert" || editor.length === 0)
                return;
            const p = Math.max(0, Math.min(editor.length - 1, cursorPosition));
            if (p === root.cursorChar())
                return;
            root.pointAt(p);
        }
        Keys.onPressed: (event) => root.handleKey(event)
    }

    // ---- barra de busca (/ e ?) ----
    Rectangle {
        id: searchBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24
        visible: root.searching
        z: 20
        color: Theme.card
        border.width: 1
        border.color: Theme.border
        radius: 6

        Text {
            id: searchSlash

            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.searchBackward ? "?" : "/"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
        }

        TextInput {
            id: searchField

            anchors.left: searchSlash.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.foreground
            selectionColor: Theme.accent
            selectedTextColor: Theme.background
            font.family: Theme.fontFamily
            font.pixelSize: 12
            clip: true

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitSearch();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.cancelSearch();
                    event.accepted = true;
                }
            }
        }

        Text {
            anchors.left: searchSlash.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text === ""
            text: "search"
            color: Theme.foregroundDim
            font: searchField.font
        }
    }
}
