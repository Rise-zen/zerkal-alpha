pragma Singleton
import QtQuick

// Material Design 3 "Expressive" motion tokens — lifted from caelestia-dots
// (https://github.com/caelestia-dots/shell, MIT). Distilled to a single
// QML singleton — no C++ plugin, just bezier curves + durations.
//
// Two families:
//   * Spatial  — for position / size / scale.  Overshoot past target → soft
//                spring bounce. Use for things that physically move.
//   * Effects  — for opacity / colour / blur.  Smooth, no overshoot. Use
//                for things that fade or recolour in place.
//
// Each family has fast / default / slow durations + matching curve.
//
// Usage:
//   NumberAnimation { duration: Anim.expressiveDefault.duration
//                     easing.type: Easing.BezierSpline
//                     easing.bezierCurve: Anim.expressiveDefault.curve }
QtObject {

    // ============= EXPRESSIVE SPATIAL (with overshoot) =============
    // The y-coordinates > 1 are what produce the spring-back feel.
    property var expressiveFast: ({
        duration: 350,
        curve: [0.42, 1.67, 0.21, 0.9, 1, 1]
    })
    property var expressiveDefault: ({
        duration: 500,
        curve: [0.38, 1.21, 0.22, 1, 1, 1]
    })
    property var expressiveSlow: ({
        duration: 650,
        curve: [0.39, 1.29, 0.35, 0.98, 1, 1]
    })

    // ============= EXPRESSIVE EFFECTS (smooth, no overshoot) =============
    property var fadeFast: ({
        duration: 150,
        curve: [0.31, 0.94, 0.34, 1, 1, 1]
    })
    property var fadeDefault: ({
        duration: 200,
        curve: [0.34, 0.8, 0.34, 1, 1, 1]
    })
    property var fadeSlow: ({
        duration: 300,
        curve: [0.34, 0.88, 0.34, 1, 1, 1]
    })

    // ============= STANDARD MATERIAL (legacy, non-expressive) =============
    // Plain ease-out — use when you want a calm, restrained motion.
    property var standard: ({
        duration: 400,
        curve: [0.2, 0, 0, 1, 1, 1]
    })

    // ============= DURATION-ONLY (use with simpler easings) =============
    property int small:      200
    property int normal:     400
    property int large:      600
    property int extraLarge: 1000
}
