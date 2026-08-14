// versioned import: sddm ships a Qt5 greeter and Qt5 rejects unversioned ones
import QtQuick 2.15

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: colBackground

    readonly property string stateDir: config.stateDir || "/var/lib/archeclipse/sddm"
    readonly property string fontFamily: config.font || "JetBrainsMono Nerd Font"

    // fallback palette, replaced by sddm-theme.sh
    property color colBackground: "#12161a"
    property color colForeground: "#d4d8da"
    property color colAccent: "#6d7f8a"
    readonly property color colFail: "#cc2222"

    property var userList: []
    property var sessionList: []
    property int userIndex: 0
    property int sessionIndex: 0
    property bool authenticating: false

    readonly property var currentUser: userList[userIndex]

    component Label: Text {
        color: root.colForeground
        font.family: root.fontFamily
    }

    component PowerButton: Label {
        id: button

        signal triggered

        opacity: hover.hovered ? 1.0 : 0.7
        color: hover.hovered ? root.colAccent : root.colForeground
        font.pixelSize: 22

        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: button.triggered()
        }
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
    }

    // role names, not Qt.UserRole offsets
    Instantiator {
        model: userModel
        delegate: QtObject {
            required property string name
            required property string realName

            Component.onCompleted: root.userList = root.userList.concat({
                name: name,
                label: realName || name
            })
        }
    }

    Instantiator {
        model: sessionModel
        delegate: QtObject {
            required property string name

            Component.onCompleted: root.sessionList = root.sessionList.concat(name)
        }
    }

    Component.onCompleted: {
        userIndex = Math.max(0, Math.min(userModel.lastIndex, userList.length - 1));
        sessionIndex = Math.max(0, Math.min(sessionModel.lastIndex, sessionList.length - 1));

        const req = new XMLHttpRequest();
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            // no file = keep defaults
            try {
                const c = JSON.parse(req.responseText);
                colBackground = c.background;
                colForeground = c.foreground;
                colAccent = c.accent;
            } catch (e) {}
        };
        req.open("GET", "file://" + stateDir + "/colors.json");
        req.send();

        password.forceActiveFocus();
    }

    function login() {
        if (authenticating)
            return;
        if (!currentUser) {
            pill.failed = true;
            message.text = "No user available";
            return;
        }
        authenticating = true;
        message.text = "Authenticating...";
        sddm.login(currentUser.name, password.text, sessionIndex);
    }

    Connections {
        target: sddm

        function onLoginSucceeded() {
            root.authenticating = false;
            message.text = "";
        }
        function onLoginFailed() {
            root.authenticating = false;
            pill.failed = true;
            message.text = "Login failed";
            password.clear();
            password.forceActiveFocus();
        }
        function onInformationMessage(msg) {
            message.text = msg;
        }
    }

    // pre-blurred by sddm-theme.sh, runtime blur dies on software rendering
    Image {
        anchors.fill: parent
        source: "file://" + root.stateDir + "/background.jpg"
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    Column {
        id: clock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: loginArea.top
        anchors.bottomMargin: 72
        spacing: 4

        property date now: new Date()

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.now = new Date()
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.now, "HH:mm")
            font.pixelSize: 92
            font.weight: Font.Light
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.now, "dddd, d MMMM")
            font.pixelSize: 18
            opacity: 0.7
        }
    }

    Column {
        id: loginArea

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 40
        spacing: 16

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.currentUser ? root.currentUser.label : ""
            font.pixelSize: 20

            TapHandler {
                enabled: root.userList.length > 1
                onTapped: {
                    root.userIndex = (root.userIndex + 1) % root.userList.length;
                    password.clear();
                    password.forceActiveFocus();
                }
            }
            HoverHandler {
                enabled: root.userList.length > 1
                cursorShape: Qt.PointingHandCursor
            }
        }

        Rectangle {
            id: pill

            property bool failed: false

            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            height: 52
            radius: height / 2 // hyprlock's `rounding = -1`
            // Qt.rgba not Qt.alpha, the latter is Qt6 only
            color: Qt.rgba(root.colBackground.r, root.colBackground.g, root.colBackground.b, 0.55)
            border.width: 2
            border.color: failed ? root.colFail : password.activeFocus ? root.colAccent : Qt.rgba(root.colForeground.r, root.colForeground.g, root.colForeground.b, 0.35)

            Behavior on border.color {
                ColorAnimation {
                    duration: 300
                }
            }

            TextInput {
                id: password

                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                passwordMaskDelay: 0
                enabled: !root.authenticating
                color: root.colForeground
                font.family: root.fontFamily
                font.pixelSize: 18

                onTextChanged: pill.failed = false
                onAccepted: root.login()

                Label {
                    anchors.centerIn: parent
                    // no focus check, field is focused at startup
                    visible: password.text === ""
                    text: "Input Password..."
                    font.pixelSize: 16
                    font.italic: true
                    opacity: 0.45
                }
            }
        }

        Label {
            id: message

            anchors.horizontalCenter: parent.horizontalCenter
            color: pill.failed ? root.colFail : root.colForeground
            font.pixelSize: 14
            font.italic: true
            opacity: text === "" ? 0 : 0.85

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
        }
    }

    Label {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 32
        text: (root.sessionList[root.sessionIndex] || "") + (root.sessionList.length > 1 ? "  ▾" : "")
        font.pixelSize: 15
        opacity: sessionHover.hovered ? 1.0 : 0.7

        HoverHandler {
            id: sessionHover

            enabled: root.sessionList.length > 1
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.sessionList.length > 1
            onTapped: root.sessionIndex = (root.sessionIndex + 1) % root.sessionList.length
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 20

        PowerButton {
            text: "⏻"
            visible: sddm.canPowerOff
            onTriggered: sddm.powerOff()
        }
        PowerButton {
            text: "↻"
            visible: sddm.canReboot
            onTriggered: sddm.reboot()
        }
        PowerButton {
            text: "⏾"
            visible: sddm.canSuspend
            onTriggered: sddm.suspend()
        }
    }
}
