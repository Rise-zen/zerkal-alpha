import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Fullscreen Wayland overlay (layer-shell) with a planet at the centre and
// recently-played covers orbiting it.
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

    // reveal 0→1 drives the bloom-in on show. Close is instant: the window
    // unmaps the moment `visible` flips, so the fade-out is never seen.
    property real reveal: visible ? 1.0 : 0.0
    Behavior on reveal {
        NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
    }

    Keys.onEscapePressed: panel.requestClose()

    // All visuals live in `world` so the reveal fades + zooms the scene as one.
    Item {
        id: world
        anchors.fill: parent
        opacity: panel.reveal
        scale: 0.96 + panel.reveal * 0.04
        transformOrigin: Item.Center

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
    }

    // Scroll input (userOffset, snaps per slot) and continuous drift
    // (autoOffset) are summed so they never fight.
    property real userOffset: 0
    property real autoOffset: 0
    property real rotationOffset: userOffset + autoOffset

    Behavior on userOffset {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    // One revolution per 30s; paused while the overlay is hidden.
    NumberAnimation on autoOffset {
        from: 0; to: Math.PI * 2
        duration: 30000
        loops: Animation.Infinite
        running: panel.visible
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

    // Orbit stage. Geometry comes from Screen because PanelWindow width/height
    // read 0 during early binding evaluation.
    Item {
        id: stage
        parent: world           // ride the reveal fade + scale
        anchors.fill: parent
        property real sw: Screen.width
        property real sh: Screen.height
        // Shared ellipse geometry for the ring and the bubbles.
        property real rx: Math.min(sw, sh) * 0.42
        property real ry: Math.min(sw, sh) * 0.30

        // Glowing orbit ring: an inner radial wash plus an additive-blended
        // ("lighter") stack of ellipse strokes that fakes HDR bloom on 8-bit.
        Canvas {
            id: ringCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = stage.sw / 2;
                const cy = stage.sh / 2;
                const rx = stage.rx;
                const ry = stage.ry;

                ctx.globalCompositeOperation = "source-over";

                // Inner wash: brightest at the rim, fading to the centre.
                const innerGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, rx);
                innerGrad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.0));
                innerGrad.addColorStop(0.55, Qt.rgba(1, 1, 1, 0.04));
                innerGrad.addColorStop(0.85, Qt.rgba(1, 1, 1, 0.14));
                innerGrad.addColorStop(1.0, Qt.rgba(1, 1, 1, 0.28));
                ctx.fillStyle = innerGrad;
                ctx.beginPath();
                ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
                ctx.fill();

                // Additive glow stack — overlapping strokes accumulate to a
                // bright core from low per-layer alphas.
                ctx.globalCompositeOperation = "lighter";

                // [extraRadius, lineWidth, alphaTop, alphaBottom]
                const layers = [
                    [40, 50, 0.04, 0.015],   // farthest soft halo
                    [28, 36, 0.06, 0.025],
                    [20, 26, 0.08, 0.035],
                    [14, 18, 0.12, 0.05],
                    [ 9, 13, 0.18, 0.08],
                    [ 6,  9, 0.26, 0.12],
                    [ 4,  6, 0.36, 0.18],
                    [ 2,  4, 0.55, 0.28],
                    [ 1,  3, 0.85, 0.45],
                    [ 0,  3, 1.00, 0.70],    // hot core
                    [-1, 1.5, 0.90, 0.60],   // inner sheen pass
                ];

                for (let i = 0; i < layers.length; i++) {
                    const [er, lw, aT, aB] = layers[i];
                    const grad = ctx.createLinearGradient(0, cy - ry - er, 0, cy + ry + er);
                    grad.addColorStop(0.0, Qt.rgba(1, 1, 1, aT));
                    grad.addColorStop(0.5, Qt.rgba(1, 1, 1, (aT + aB) / 2));
                    grad.addColorStop(1.0, Qt.rgba(1, 1, 1, aB));
                    ctx.strokeStyle = grad;
                    ctx.lineWidth = lw;
                    ctx.beginPath();
                    ctx.ellipse(cx - rx - er, cy - ry - er, (rx + er) * 2, (ry + er) * 2);
                    ctx.stroke();
                }

                // back to normal blending for anything painted later
                ctx.globalCompositeOperation = "source-over";
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

                // Highlight the bubble nearest the top slot (gets the label).
                property real normalizedAngle: {
                    let a = (angle + Math.PI / 2) % (Math.PI * 2);
                    if (a < 0) a += Math.PI * 2;
                    return a;
                }
                property bool isTop: Math.min(normalizedAngle, Math.PI * 2 - normalizedAngle) < 0.20

                // Per-track accent (parsed once), falling back to the panel accent.
                property color ringColor: modelData.accent ? modelData.accent : panel.accent

                width: 100
                height: 100
                antialiasing: true
                // Moved every frame from the angle math; no x/y Behavior (it
                // would lag the continuous auto-rotation and stutter).
                x: cx + stage.rx * Math.cos(angle) - width / 2
                y: cy + stage.ry * Math.sin(angle) - height / 2
                z: isTop ? 10 : 1

                // permanent thin accent ring on every cover
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    border.width: bubble.isTop ? 2 : 1
                    border.color: Qt.rgba(bubble.ringColor.r, bubble.ringColor.g,
                                          bubble.ringColor.b, bubble.isTop ? 0.85 : 0.40)
                    Behavior on border.width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
                }

                // Round cover via MultiEffect mask (clip+radius is bbox-only).
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: bubbleMask }
                    Image {
                        anchors.fill: parent
                        source: modelData.cover ? "file://" + modelData.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width:  200
                        sourceSize.height: 200
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: true
                    }
                }
                Item {
                    id: bubbleMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "black"; antialiasing: true }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: bubble.modelData.uri ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        mouse.accepted = true;
                        const uri = bubble.modelData.uri || "";
                        if (uri !== "") {
                            // Pin to spotify: a spotify:track: URI is meaningless
                            // to whatever else playerctld may have made "current".
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

    // Central planet — accent-coloured glow that follows the current track.
    Item {
        id: centerPlanet
        parent: world           // ride the reveal fade + scale
        anchors.centerIn: stage
        width: 220
        height: 220

        // Pulsing halo: stacked circles approximate a radial gradient.
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
                running: panel.visible; loops: Animation.Infinite
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

        // Center logo — layer.enabled caches the PNG as a texture so the
        // rotation is a near-free GPU transform.
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
            layer.smooth: true
            antialiasing: true
            transformOrigin: Item.Center

            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 24000
                loops: Animation.Infinite
                running: panel.visible
            }
        }

    }

}
