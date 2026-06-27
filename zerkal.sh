#!/usr/bin/env bash
# zerkal — standalone quickshell overlay
#
#   zerkal.sh start    launch (autostart-friendly, exits immediately)
#   zerkal.sh toggle   show/hide the orbital (planet + ring) view
#   zerkal.sh show     force show
#   zerkal.sh hide     force hide
#   zerkal.sh stop     kill the shell
#
# Expects /tmp/lyrics.json to be kept fresh by the `lyrics --json` daemon
# (https://github.com/Rise-zen/lyrics). Without it the overlay still loads
# but stays empty.

ROOT="$(cd "$(dirname "$0")" && pwd)"
SHELL_QML="$ROOT/qml/shell.qml"

start() {
    if ! pgrep -f "quickshell -p $SHELL_QML" >/dev/null; then
        setsid quickshell -p "$SHELL_QML" </dev/null >/dev/null 2>&1 &
    fi
}

case "$1" in
    start)  start ;;
    toggle) start; quickshell -p "$SHELL_QML" ipc call zerkal toggle >/dev/null 2>&1 ;;
    show)   start; quickshell -p "$SHELL_QML" ipc call zerkal show   >/dev/null 2>&1 ;;
    hide)   quickshell -p "$SHELL_QML" ipc call zerkal hide >/dev/null 2>&1 ;;
    stop)   pkill -f "quickshell -p $SHELL_QML" ;;
    *) echo "usage: $0 {start|toggle|show|hide|stop}"; exit 1 ;;
esac
