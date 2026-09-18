pragma Singleton
import QtQuick

// Backs the askuser overlay -- surfaces the ask-user MCP server's
// questions (mcp-servers/ask_user.py) to a real on-screen dialog. File-based
// handoff: the MCP server writes a request file and IPC-triggers `show`
// with its id; this state reads that file, and writing the answer back to
// its response_file is what unblocks the (still-running, still-polling)
// MCP server process on the other end.
QtObject {
    id: root

    property bool visible: false
    property string requestId: ""
    property string question: ""
    property var options: []
    property bool allowFreeText: true
    property string responseFile: ""

    function reset() {
        visible = false;
        requestId = "";
        question = "";
        options = [];
        allowFreeText = true;
        responseFile = "";
    }
}
