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
    property bool galaxyShown:  false

    // `zerkal` controls the orbital (planet + ring) view; `galaxy` controls
    // the perspective carousel through a star field. They're independent so
    // users can have both bound to different keys.
    IpcHandler {
        target: "zerkal"
        function toggle(): void { rootShell.orbitalShown = !rootShell.orbitalShown }
        function show(): void   { rootShell.orbitalShown = true }
        function hide(): void   { rootShell.orbitalShown = false }
    }
    IpcHandler {
        target: "galaxy"
        function toggle(): void { rootShell.galaxyShown = !rootShell.galaxyShown }
        function show(): void   { rootShell.galaxyShown = true }
        function hide(): void   { rootShell.galaxyShown = false }
    }

    // ---- poll the JSON state (200 ms is plenty for clock-orbit info) ----
    Process {
        id: reader
        command: ["cat", "/tmp/lyrics.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                if (txt === "") return;
                let d;
                try { d = JSON.parse(txt); } catch (e) { return; }

                rootShell.title  = d.title  || "";
                rootShell.artist = d.artist || "";
                if (d.accent) rootShell.accent = d.accent;
                rootShell.cover  = d.cover  || "";
                rootShell.recent = d.recent || [];
            }
        }
    }
    Timer {
        interval: 250; running: true; repeat: true; triggeredOnStart: true
        onTriggered: reader.running = true
    }

    // Keep the Loader active forever after first show, so toggling visibility
    // never tears down (and recreates) the heavy bubble/canvas scene. This
    // makes show/hide instant and lag-free regardless of how many recent
    // tracks have accumulated.
    property bool everOrbital: false
    property bool everGalaxy:  false
    onOrbitalShownChanged: if (orbitalShown) everOrbital = true
    onGalaxyShownChanged:  if (galaxyShown)  everGalaxy  = true

    Loader {
        active: rootShell.everOrbital
        sourceComponent: orbitalComp
    }
    Loader {
        active: rootShell.everGalaxy
        sourceComponent: galaxyComp
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
    Component {
        id: galaxyComp
        GalaxyView {
            visible: rootShell.galaxyShown
            accent:  rootShell.accent
            recent:  rootShell.recent
            onRequestClose: rootShell.galaxyShown = false
        }
    }
}
