import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Galaxy mode — recently played tracks float through a star field as planets.
// Mouse wheel scrolls the carousel; the planet closest to the camera is huge,
// neighbours shrink and dim with depth to fake 3D. No QtQuick3D, no shaders,
// just sized/scaled circles with z-order.
PanelWindow {
    id: gal

    // ----- inputs (bound from shell.qml) -----
    property color  accent: "#89b4fa"
    property var    recent: []   // [{title, artist, cover, accent, uri}]

    signal requestClose()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "zerkal-galaxy"

    // ----- the scrollable "camera" index, fractional so the carousel
    //       slides smoothly between two planets -----
    property real cameraIdx: 0
    Behavior on cameraIdx {
        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
    }

    // ===== background: gradient sky + parallax stars =====
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#02030a" }
            GradientStop { position: 0.55; color: Qt.rgba(gal.accent.r * 0.20, gal.accent.g * 0.20, gal.accent.b * 0.25, 1.0) }
            GradientStop { position: 1.0; color: "#01020a" }
        }
    }

    // soft nebula glow drifting behind the planets
    Rectangle {
        id: nebula
        width: parent.width * 1.1
        height: parent.height * 0.55
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        radius: height / 2
        opacity: 0.35
        color: gal.accent
        SequentialAnimation on opacity {
            running: true; loops: Animation.Infinite
            NumberAnimation { from: 0.30; to: 0.45; duration: 4200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.45; to: 0.30; duration: 4200; easing.type: Easing.InOutSine }
        }
    }

    // Star field — 140 procedurally placed dots, three "depth" layers that
    // drift sideways at different speeds for parallax.
    Repeater {
        model: 140
        delegate: Rectangle {
            required property int index
            // deterministic pseudo-random so stars don't re-roll every reload
            property real seed: (index * 9301 + 49297) % 233280 / 233280.0
            property real seed2: (index * 1103515245 + 12345) % 233280 / 233280.0
            property int depth: index % 3   // 0 = closest (fast, big), 2 = farthest (slow, tiny)

            width: depth === 0 ? 2.2 : depth === 1 ? 1.4 : 0.9
            height: width
            radius: width / 2
            color: "white"
            opacity: depth === 0 ? 0.85 : depth === 1 ? 0.55 : 0.30

            x: (seed * gal.width + drift) % gal.width
            y: seed2 * gal.height

            property real drift: 0
            NumberAnimation on drift {
                from: 0; to: gal.width
                duration: depth === 0 ? 60000 : depth === 1 ? 120000 : 200000
                loops: Animation.Infinite
                running: true
            }

            // slow twinkle on a fraction of stars
            SequentialAnimation on opacity {
                running: (seed * 100) % 7 < 1   // ~14% of stars twinkle
                loops: Animation.Infinite
                NumberAnimation { from: parent.opacity; to: 0.15; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.15; to: parent.opacity; duration: 1800; easing.type: Easing.InOutSine }
            }
        }
    }

    // ===== close handlers =====
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.NoButton
        propagateComposedEvents: true
        onClicked: gal.requestClose()
        onWheel: (wheel) => {
            const dir = wheel.angleDelta.y > 0 ? -1 : 1;
            const n = Math.max(1, gal.recent.length);
            gal.cameraIdx = ((gal.cameraIdx + dir) % n + n) % n;
            wheel.accepted = true;
        }
    }
    Keys.onEscapePressed: gal.requestClose()

    // ===== planet carousel =====
    // Each track is rendered as a planet at horizontal offset proportional to
    // (index - cameraIdx). Sphere closest to camera (offset ≈ 0) is biggest
    // and centered; siblings shrink and dim. z-order = -|offset| so the nose
    // planet sits on top.
    Repeater {
        model: gal.recent
        delegate: Item {
            id: planet
            required property int index
            required property var modelData

            // Signed distance from the camera, wrapped to [-n/2, +n/2] so the
            // carousel loops seamlessly.
            property real rawOff: index - gal.cameraIdx
            property real off: {
                const n = gal.recent.length;
                let o = rawOff;
                if (o > n / 2) o -= n;
                if (o < -n / 2) o += n;
                return o;
            }
            property real absOff: Math.abs(off)

            // 3D-ish projection: at the camera (off=0) → full size; ±1 → 0.55;
            // ±2 → 0.32; falls off after that.
            property real depthScale: Math.max(0.18, 1.0 / (1.0 + absOff * 0.85))
            property real planetSize: 360 * depthScale
            // small arc to make it feel like an orbit, not a flat row
            property real arcLift: -50 * (1 - depthScale)

            width: planetSize
            height: planetSize
            // horizontal layout: 320px between adjacent slots at camera, scaled by perspective
            x: gal.width / 2
                  + off * 320 * Math.pow(depthScale, 0.4)
                  - planetSize / 2
            y: gal.height / 2 + arcLift - planetSize / 2

            z: 100 - Math.round(absOff * 10)
            opacity: Math.max(0.15, 1.0 - absOff * 0.40)

            Behavior on planetSize { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on x          { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on y          { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on opacity    { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            // accent glow ring (stronger for the camera planet)
            Rectangle {
                anchors.centerIn: parent
                width:  parent.width + 18
                height: parent.height + 18
                radius: width / 2
                color: "transparent"
                border.width: planet.absOff < 0.4 ? 3 : 1
                border.color: Qt.rgba(
                    modelData.accent ? Qt.color(modelData.accent).r : gal.accent.r,
                    modelData.accent ? Qt.color(modelData.accent).g : gal.accent.g,
                    modelData.accent ? Qt.color(modelData.accent).b : gal.accent.b,
                    planet.absOff < 0.4 ? 0.85 : 0.30)
                Behavior on border.width { NumberAnimation { duration: 280 } }
                Behavior on border.color { ColorAnimation { duration: 280 } }
            }

            // Cover, round-masked via MultiEffect (same proven pattern as
            // OrbitalClock — Rectangle.clip+radius doesn't do rounded clipping
            // in Qt6, only bbox).
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: planetMask }
                Image {
                    anchors.fill: parent
                    source: modelData.cover ? "file://" + modelData.cover : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width:  Math.max(120, Math.round(planet.planetSize))
                    sourceSize.height: Math.max(120, Math.round(planet.planetSize))
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    cache: true
                }
            }
            Item {
                id: planetMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: width / 2; color: "black"; antialiasing: true }
            }
            // crisp inner border
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.40)
                z: 1
            }

            // click → play the track
            MouseArea {
                anchors.fill: parent
                cursorShape: planet.modelData.uri ? Qt.PointingHandCursor : Qt.ArrowCursor
                hoverEnabled: true
                onClicked: (mouse) => {
                    mouse.accepted = true;
                    const uri = planet.modelData.uri || "";
                    if (uri !== "") {
                        Quickshell.execDetached(["playerctl", "--player=spotify", "open", uri]);
                    }
                }
            }
        }
    }

    // ===== centered title + artist of the currently-focused planet =====
    Column {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 80
        spacing: 6
        property var focused: gal.recent[Math.round(gal.cameraIdx) % Math.max(1, gal.recent.length)]
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.focused ? parent.focused.title : ""
            color: "white"
            font.family: "JetBrains Mono"
            font.pixelSize: 22
            font.weight: Font.ExtraBold
            font.letterSpacing: 0.5
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.focused ? (parent.focused.artist || "").toUpperCase() : ""
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            font.weight: Font.Medium
            font.letterSpacing: 2.5
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
