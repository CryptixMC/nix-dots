pragma Singleton
import QtQuick

// phase: "capturing" -> "processing" -> "result" | "error"
// While gaming, the overlay never becomes visible at all (see
// ScreenContext.qml) -- result still lands via clipboard + notification.
QtObject {
    property bool visible: false
    property string phase: "capturing"
    property string resultText: ""
    property string errorMessage: ""
    property string route: "" // "vision" | "ocr" | "ocr-gaming"

    function reset() {
        phase = "capturing";
        resultText = "";
        errorMessage = "";
        route = "";
    }

    function hide() {
        visible = false;
    }
}
