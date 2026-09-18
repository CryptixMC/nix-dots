pragma Singleton
import QtQuick

QtObject {
    property bool visible: false
    property string status: ""

    function toggle() {
        visible = !visible;
        if (visible)
            status = "";
    }

    function hide() {
        visible = false;
    }
}
