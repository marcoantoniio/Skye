#!/usr/bin/env bash
# Verificação local: bridges Python + testes + qmllint (se instalado).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -m py_compile scripts/*.py
python3 -m unittest discover -s tests -v

if command -v qmllint >/dev/null 2>&1; then
    QMLLINT=qmllint
elif [ -x /usr/lib/qt6/bin/qmllint ]; then
    QMLLINT=/usr/lib/qt6/bin/qmllint
else
    QMLLINT=""
fi

if [ -n "$QMLLINT" ]; then
    "$QMLLINT" -I . \
        Bar.qml shell.qml \
        services/*.qml widgets/*.qml panels/*.qml \
        > /tmp/skye-qmllint.log 2>&1 || {
            cat /tmp/skye-qmllint.log
            exit 1
        }
    echo "qmllint: ok"
else
    echo "qmllint: não instalado, pulando"
fi
