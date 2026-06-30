//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// zerkal shell. Polls /tmp/lyrics.json (written by the `lyrics --json`
// daemon — https://github.com/Rise-zen/lyrics) for the current track's
// accent colour, cover path, and recent history, then drives the overlay.
// Toggled via:
//   quickshell -p shell.qml ipc call zerkal toggle
ShellRoot {
    id: rootShell

    // ----- shared state read from /tmp/lyrics.json -----
    property string title:  ""
    property string artist: ""
    property color  accent: "#89b4fa"
    property string cover:  ""
    property var    recent: []   // [{title, artist, cover, accent, uri}, ...]

    // toggled by IPC
    property bool orbitalShown: false

    IpcHandler {
        target: "zerkal"
        function toggle(): void { rootShell.orbitalShown = !rootShell.orbitalShown }
        function show(): void   { rootShell.orbitalShown = true }
        function hide(): void   { rootShell.orbitalShown = false }
    }

    // ---- read state on every write to /tmp/lyrics.json (no polling) ----
    FileView {
        path: "/tmp/lyrics.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const txt = text().trim();
            if (txt === "") return;
            let d;
            try { d = JSON.parse(txt); } catch (e) { return; }

            rootShell.title  = d.title  || "";
            rootShell.artist = d.artist || "";
            if (d.accent) rootShell.accent = d.accent;
            rootShell.cover  = d.cover  || "";
            const newRecent = d.recent || [];
            if (JSON.stringify(newRecent) !== JSON.stringify(rootShell.recent))
                rootShell.recent = newRecent;
        }
    }

    // Keep the Loader active forever after first show, so toggling visibility
    // never tears down (and recreates) the heavy bubble/canvas scene. This
    // makes show/hide instant and lag-free regardless of how many recent
    // tracks have accumulated.
    property bool everOrbital: false
    onOrbitalShownChanged: if (orbitalShown) everOrbital = true

    Loader {
        active: rootShell.everOrbital
        sourceComponent: orbitalComp
    }

    Component {
        id: orbitalComp
        OrbitalClock {
            visible:   rootShell.orbitalShown
            accent:    rootShell.accent
            recent:    rootShell.recent
            nowTitle:  rootShell.title
            nowArtist: rootShell.artist
            nowCover:  rootShell.cover
            onRequestClose: rootShell.orbitalShown = false
        }
    }
}
