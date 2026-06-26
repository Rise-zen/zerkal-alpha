import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// A floating clock surrounded by an elliptical orbit of recently-played
// album covers. The orbit angle is driven by the mouse wheel: scroll left
// rotates one slot counter-clockwise, scroll right the other way.
PanelWindow {
    id: panel

    // ----- inputs (bound from shell.qml) -----
    property color  accent: "#89b4fa"
    property var    recent: []   // [{title, artist, cover, accent, uri}, ...]
    property string nowTitle: ""
    property string nowArtist: ""
    /// path to the currently-playing cover; used as the blurred backdrop
    property string nowCover: ""

    signal requestClose()

    // ----- window setup -----
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "orbital-clock"

    // ----- live clock (no Timer when only animating once per second) -----
    property string clockHHMM: ""
    property string clockSS: ""
    property string clockDate: ""
    function updateClock() {
        const d = new Date();
        const pad = n => (n < 10 ? "0" + n : "" + n);
        panel.clockHHMM = pad(d.getHours()) + ":" + pad(d.getMinutes());
        panel.clockSS = pad(d.getSeconds());
        panel.clockDate = d.toLocaleDateString(Qt.locale("en_US"), "dddd, MMMM d");
    }
    Timer {
        interval: 250; running: true; repeat: true; triggeredOnStart: true
        onTriggered: panel.updateClock()
    }

    // ----- cached blurred cover backdrop -----
    Rectangle { anchors.fill: parent; color: "#0a0b10" }
    Item {
        anchors.fill: parent
        layer.enabled: true   // blur rasterised once per cover change, then cached
        layer.smooth: true

        Image {
            id: backdropSrc
            anchors.fill: parent
            source: panel.nowCover ? "file://" + panel.nowCover : ""
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
            cache: true
        }
        MultiEffect {
            anchors.fill: parent
            source: backdropSrc
            visible: backdropSrc.status === Image.Ready
            blurEnabled: true
            blurMax: 96
            blur: 1.0
            opacity: 0.45
            brightness: -0.25
            saturation: 0.35
        }
    }
    // accent wash on top of the cached blur
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.10) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.65) }
        }
    }
    // catch-all close — instant requestClose on left-click anywhere off-bubble
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: panel.requestClose()
    }

    Keys.onEscapePressed: panel.requestClose()

    // ----- orbit angle -----
    // Two separate offsets are summed so the user's scroll input never fights
    // with the slow continuous auto-rotation. `userOffset` snaps in 1-slot
    // steps; `autoOffset` drifts smoothly forever.
    property real userOffset: 0
    property real autoOffset: 0
    property real rotationOffset: userOffset + autoOffset

    Behavior on userOffset {
        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
    }

    // Slow drift, one full revolution per minute. The user can still scroll
    // to nudge the active bubble — that lands on top of this baseline.
    NumberAnimation on autoOffset {
        from: 0; to: Math.PI * 2
        duration: 60000
        loops: Animation.Infinite
        running: true
    }

    // Scroll catcher: covers the orbit area but lets bubble clicks through.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onWheel: (wheel) => {
            const step = Math.PI * 2 / Math.max(panel.recent.length, 8);
            panel.userOffset += (wheel.angleDelta.y > 0 ? 1 : -1) * step;
            wheel.accepted = true;
        }
    }

    // ----- explicit orbit stage -----
    // PanelWindow's own width/height return 0 during early binding evaluation,
    // so we anchor a plain Item to it AND fall back to Screen dimensions for
    // geometry. Canvas + bubbles live inside this stage so their `parent` is
    // unambiguous.
    Item {
        id: stage
        anchors.fill: parent
        // Tracked, robust dimensions for orbit math. Screen is the most
        // reliable source — width/height update reactively.
        property real sw: Screen.width
        property real sh: Screen.height
        // Shared ellipse geometry — same values used by ring and bubbles.
        property real rx: Math.min(sw, sh) * 0.42
        property real ry: Math.min(sw, sh) * 0.30

        // ----- orbit ring (dashed ellipse, drawn behind the bubbles) -----
        Canvas {
            id: ringCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = stage.sw / 2;
                const cy = stage.sh / 2;
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10);
                ctx.lineWidth = 1.5;
                ctx.setLineDash([6, 8]);
                ctx.beginPath();
                ctx.ellipse(cx - stage.rx, cy - stage.ry, stage.rx * 2, stage.ry * 2);
                ctx.stroke();
            }
            Connections {
                target: stage
                function onSwChanged() { ringCanvas.requestPaint(); }
                function onShChanged() { ringCanvas.requestPaint(); }
            }
        }

        // ----- orbiting cover bubbles -----
        Repeater {
            model: panel.recent
            delegate: Item {
                id: bubble
                required property int index
                required property var modelData

                property int slots: Math.max(panel.recent.length, 8)
                property real baseAngle: -Math.PI / 2
                property real angle: baseAngle + bubble.index * (Math.PI * 2 / bubble.slots) + panel.rotationOffset

                // Same ellipse as the dashed ring so bubbles ride along it.
                property real cx: stage.sw / 2
                property real cy: stage.sh / 2

                // Closeness to the top slot, only used to highlight which one
                // gets the title label. No size/scale/opacity changes.
                property real normalizedAngle: {
                    let a = (angle + Math.PI / 2) % (Math.PI * 2);
                    if (a < 0) a += Math.PI * 2;
                    return a;
                }
                property bool isTop: Math.min(normalizedAngle, Math.PI * 2 - normalizedAngle) < 0.20

                width: 100
                height: 100
                x: cx + stage.rx * Math.cos(angle) - width / 2
                y: cy + stage.ry * Math.sin(angle) - height / 2
                z: isTop ? 10 : 1

                // No animation on x/y — the angle changes continuously via the
                // auto-rotation NumberAnimation, so a Behavior would lag behind
                // and stutter. We move every frame from the math.

                // permanent thin accent ring on every cover
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    radius: width / 2
                    color: "transparent"
                    border.width: bubble.isTop ? 2 : 1
                    border.color: Qt.rgba(
                        bubble.modelData.accent ? Qt.color(bubble.modelData.accent).r : panel.accent.r,
                        bubble.modelData.accent ? Qt.color(bubble.modelData.accent).g : panel.accent.g,
                        bubble.modelData.accent ? Qt.color(bubble.modelData.accent).b : panel.accent.b,
                        bubble.isTop ? 0.85 : 0.40)
                    Behavior on border.width { NumberAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                }

                // circular cover
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: bubbleMask }
                    Image {
                        anchors.fill: parent
                        source: modelData.cover ? "file://" + modelData.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
                Item {
                    id: bubbleMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: bubble.modelData.uri ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        mouse.accepted = true;
                        const uri = bubble.modelData.uri || "";
                        if (uri !== "") {
                            // Explicit --player=spotify: spotify:track:XXX
                            // URIs only mean anything to Spotify itself, and
                            // playerctld may have promoted another player to
                            // "current" (chromium, mpv) which would silently
                            // discard the open command.
                            Quickshell.execDetached(["playerctl", "--player=spotify", "open", uri]);
                        }
                    }
                    onPressed: bubble.scale = 0.92
                    onReleased: bubble.scale = 1.0
                    onCanceled: bubble.scale = 1.0
                }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                // title label, shown only on the top bubble
                Column {
                    anchors.top: parent.bottom
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
                    opacity: bubble.isTop ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: bubble.modelData.title || ""
                        color: "white"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        width: 220
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: bubble.modelData.artist ? bubble.modelData.artist.toUpperCase() : ""
                        color: Qt.rgba(1,1,1,0.55)
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 2
                        elide: Text.ElideRight
                        width: 220
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // ----- central planet -----
    // A glowing accent-coloured sphere with a soft outer corona, slow inner
    // shimmer, and a faint orbital aura ring. Colour follows panel.accent so
    // it changes with the currently-playing track's cover.
    Item {
        id: centerPlanet
        anchors.centerIn: stage
        width: 220
        height: 220

        // ----- outermost halo (very wide, very soft, pulsing) -----
        // Stack of progressively smaller, more opaque circles emulates a radial
        // gradient since Qt6 needs QtQuick.Shapes for true RadialGradient and
        // that boilerplate is heavy. 5 layers reads as a smooth glow.
        Repeater {
            model: 5
            delegate: Rectangle {
                anchors.centerIn: parent
                width:  460 - modelData * 40
                height: 460 - modelData * 40
                radius: width / 2
                color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b,
                               0.04 + modelData * 0.05)
            }
        }
        // slow heartbeat pulse on the whole halo group
        Item {
            anchors.fill: parent
            SequentialAnimation on scale {
                running: true; loops: Animation.Infinite
                NumberAnimation { from: 0.95; to: 1.08; duration: 2400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.08; to: 0.95; duration: 2400; easing.type: Easing.InOutSine }
            }
        }

        // ----- mid corona ring -----
        Rectangle {
            anchors.centerIn: parent
            width: 280; height: 280
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.30)
        }

        // ----- center logo (Tux) -----
        // Static Image, no rotation and no MultiEffect — layer.enabled caches
        // it to a texture so there's zero per-frame cost (the earlier lag came
        // from live colorization + rotation, not from drawing an image).
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.8
            height: parent.height * 0.8
            source: "center.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            cache: true
            asynchronous: true
            layer.enabled: true
        }

        // tiny title label below the planet so the user still sees what's playing
        Column {
            anchors.top: parent.bottom
            anchors.topMargin: 32
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            opacity: panel.nowTitle ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel.nowTitle
                color: Qt.rgba(1, 1, 1, 0.85)
                font.family: "JetBrains Mono"
                font.pixelSize: 15
                font.weight: Font.Bold
                elide: Text.ElideRight
                width: 380
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel.nowArtist.toUpperCase()
                color: Qt.rgba(1, 1, 1, 0.50)
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 2.5
                elide: Text.ElideRight
                width: 380
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

}
