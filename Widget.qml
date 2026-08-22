import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "cassian.autodeploy"

  readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/autodeploy.json"
  readonly property color okColor: "#55a555"

  property bool opened: false
  property bool configured: false
  property bool showingSetup: false
  property string sshUser: ""
  property string sshHost: ""
  property var apps: []
  property string errorText: ""
  property string statusText: ""
  property bool isLoading: false
  property string lastUpdated: ""

  function open() {
    opened = true
    if (configured) {
      showingSetup = false
      fetchStatus()
    } else {
      showingSetup = true
    }
    Qt.callLater(function() {
      if (showingSetup && userField) {
        userField.forceActiveFocus()
        userField.selectAll()
      }
    })
  }
  function close() { opened = false }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }

  readonly property bool popoutSwitchClosing: false

  function saveConnection() {
    const user = userField.text.trim()
    const host = hostField.text.trim()
    if (user === "" || host === "") {
      setupErrorText = "Enter both SSH user and host."
      return
    }
    setupErrorText = ""
    sshUser = user
    sshHost = host
    mkdirProcess.command = ["mkdir", "-p", settingsPath.substring(0, settingsPath.lastIndexOf("/"))]
    mkdirProcess.running = true
  }

  function writeSettings() {
    const payload = { user: sshUser, host: sshHost }
    settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
    configured = true
    showingSetup = false
    fetchStatus()
  }

  function editConnection() {
    showingSetup = true
    errorText = ""
    Qt.callLater(function() {
      if (userField) {
        userField.forceActiveFocus()
        userField.selectAll()
      }
    })
  }

  function fetchStatus() {
    if (!configured || isLoading) return
    isLoading = true
    errorText = ""
    sshProc.command = [
      "ssh",
      "-o", "BatchMode=yes",
      "-o", "ConnectTimeout=5",
      "-o", "StrictHostKeyChecking=accept-new",
      sshUser + "@" + sshHost,
      "/usr/local/sbin/autodeployctl", "status", "--json"
    ]
    sshProc.running = true
  }

  function appOk(a) {
    return a && a.valid === true && a.service_running === true && a.container_running === true
  }

  function appDetails(a) {
    const parts = []
    if (a.public_host) parts.push(a.public_host + (a.host_port ? ":" + a.host_port : ""))
    if (a.deployed_digest) {
      let d = String(a.deployed_digest).replace(/^sha256:/, "")
      parts.push(d.substring(0, 12))
    }
    const checks = a.health_checks || []
    if (checks.length > 0) parts.push(checks.join(", "))
    return parts.join("  •  ")
  }

  function healthyCount() {
    let n = 0
    for (let i = 0; i < apps.length; i++) {
      if (appOk(apps[i])) n++
    }
    return n
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // server glyph (Nerd Font)
    text: "󰒋"
    slotSize: Style.bar.statusSlot
    tooltipText: "Autodeploy — remote service status (click to view)"
    onPressed: function(btn) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(560))
    contentHeight: fittedContentHeight(mainColumn.implicitHeight + Style.space(8))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: (userField && userField.activeFocus) || (hostField && hostField.activeFocus)
      onCloseRequested: root.close()

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: Style.space(12)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Autodeploy"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }
          Text {
            visible: root.configured && root.sshUser !== ""
            text: root.sshUser + "@" + root.sshHost
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Layout.alignment: Qt.AlignVCenter
          }
          Item { Layout.fillWidth: true }

          Button {
            visible: root.configured && !root.showingSetup
            text: root.isLoading ? "…" : "↻"
            implicitWidth: Style.space(28)
            implicitHeight: Style.space(28)
            fontSize: Style.font.caption
            onClicked: root.fetchStatus()
          }
          Button {
            visible: root.configured && !root.showingSetup
            text: "✎"
            implicitWidth: Style.space(28)
            implicitHeight: Style.space(28)
            fontSize: Style.font.caption
            onClicked: root.editConnection()
          }
          Button {
            text: "✕"
            implicitWidth: Style.space(28)
            implicitHeight: Style.space(28)
            fontSize: Style.font.caption
            onClicked: root.close()
          }
        }

        // ---- Setup form (first click / edit) ----
        ColumnLayout {
          visible: root.showingSetup
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Connect over SSH to a host running autodeployctl. The public key of this machine must already be installed for the user."
            wrapMode: Text.Wrap
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
              id: userField
              Layout.fillWidth: true
              text: root.sshUser
              placeholderText: "SSH user (e.g. andor)"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              onAccepted: hostField.forceActiveFocus()
              Keys.onEscapePressed: root.close()
            }

            TextField {
              id: hostField
              Layout.fillWidth: true
              text: root.sshHost
              placeholderText: "Host or IP (e.g. 192.168.254.10)"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              onAccepted: root.saveConnection()
              Keys.onEscapePressed: root.close()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Button {
              text: root.configured ? "Save" : "Connect"
              onClicked: root.saveConnection()
            }
            Button {
              visible: root.configured
              text: "Cancel"
              onClicked: {
                root.showingSetup = false
                root.fetchStatus()
              }
            }
            Item { Layout.fillWidth: true }
          }

          Text {
            visible: setupErrorText !== ""
            Layout.fillWidth: true
            text: setupErrorText
            wrapMode: Text.Wrap
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        // ---- Status view ----
        ColumnLayout {
          visible: !root.showingSetup
          Layout.fillWidth: true
          spacing: Style.space(8)

          // Loading
          Text {
            visible: root.isLoading
            Layout.fillWidth: true
            text: "Fetching status from " + root.sshUser + "@" + root.sshHost + "…"
            color: Qt.darker(Color.popups.text, 1.2)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.italic: true
          }

          // Error
          Text {
            visible: !root.isLoading && root.errorText !== ""
            Layout.fillWidth: true
            text: root.errorText
            wrapMode: Text.Wrap
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Summary
          Text {
            visible: !root.isLoading && root.errorText === "" && root.apps.length > 0
            Layout.fillWidth: true
            text: root.apps.length + " app" + (root.apps.length === 1 ? "" : "s") + " • " + root.healthyCount() + " healthy" + (root.lastUpdated !== "" ? " • " + root.lastUpdated : "")
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Flickable {
            id: listFlick
            visible: !root.isLoading && root.errorText === "" && root.apps.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Math.max(listContent.implicitHeight + Style.space(8), Style.space(60)), Style.space(320))
            Layout.maximumHeight: Style.space(320)
            contentHeight: listContent.implicitHeight + Style.space(8)
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: listContent
              width: listFlick.width - Style.space(8)
              x: Style.space(4)
              y: Style.space(4)
              spacing: Style.space(10)

              Repeater {
                model: root.apps

                ColumnLayout {
                  required property var modelData
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: width / 2
                      color: root.appOk(modelData) ? root.okColor : Color.urgent
                      Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                      text: modelData.app || "?"
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: modelData.container_state || (modelData.container_running === true ? "running" : "unknown")
                      color: root.appOk(modelData) ? root.okColor : Color.urgent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      Layout.alignment: Qt.AlignVCenter
                    }
                  }

                  Text {
                    visible: root.appDetails(modelData) !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.space(16)
                    text: root.appDetails(modelData)
                    wrapMode: Text.Wrap
                    color: Qt.darker(Color.popups.text, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: modelData.valid === false || (modelData.error !== null && modelData.error !== undefined && modelData.error !== "")
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.space(16)
                    text: modelData.error || "Manifest invalid"
                    wrapMode: Text.Wrap
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Rectangle {
                    visible: index < root.apps.length - 1
                    Layout.fillWidth: true
                    height: 1
                    color: Color.popups.text
                    opacity: 0.12
                  }
                }
              }
            }

            QQC.ScrollBar.vertical: QQC.ScrollBar {
              policy: QQC.ScrollBar.AsNeeded
            }
          }

          // Empty state
          Text {
            visible: !root.isLoading && root.errorText === "" && root.apps.length === 0 && root.configured
            Layout.fillWidth: true
            text: "No apps found on the host."
            wrapMode: Text.Wrap
            color: Qt.darker(Color.popups.text, 1.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            opacity: 0.9
          }
        }

        // Footer hint
        Text {
          visible: !root.showingSetup
          Layout.fillWidth: true
          text: "Read-only view • ssh " + (root.sshUser !== "" ? root.sshUser + "@" + root.sshHost : "user@host") + " autodeployctl status --json"
          wrapMode: Text.Wrap
          color: Qt.darker(Color.popups.text, 1.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          opacity: 0.6
        }
      }
    }
  }

  property string setupErrorText: ""

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        const parsed = JSON.parse(String(text() || "{}"))
        if (parsed.user && parsed.host) {
          root.sshUser = String(parsed.user)
          root.sshHost = String(parsed.host)
          root.configured = true
        } else {
          root.configured = false
        }
      } catch (e) {
        root.configured = false
      }
    }
    onLoadFailed: root.configured = false
    onFileChanged: reload()
  }

  // The first read can race shell startup (weather-plugin pattern); one
  // delayed reload self-corrects a stored config left unhonored.
  Timer {
    interval: 1500
    running: true
    onTriggered: settingsFile.reload()
  }

  Process {
    id: mkdirProcess
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.setupErrorText = "Could not create settings directory."
        return
      }
      root.writeSettings()
    }
  }

  Process {
    id: sshProc
    stdout: StdioCollector {
      id: sshStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: sshStderr
      waitForEnd: true
    }
    onExited: function(code, status) {
      root.isLoading = false
      if (code !== 0) {
        root.apps = []
        const err = String(sshStderr.text || "").trim()
        root.errorText = "SSH failed (exit " + code + "): " + (err !== "" ? err.split("\n")[0] : "no output")
        return
      }
      const out = String(sshStdout.text || "").trim()
      try {
        let parsed = JSON.parse(out)
        if (!Array.isArray(parsed)) parsed = [parsed]
        root.apps = parsed
        root.lastUpdated = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")
        root.errorText = ""
      } catch (e) {
        root.apps = []
        root.errorText = "Could not parse autodeployctl output: " + e.message
      }
    }
  }

  IpcHandler {
    target: "cassian.autodeploy"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.fetchStatus() }
    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        configured: root.configured,
        showingSetup: root.showingSetup,
        user: root.sshUser,
        host: root.sshHost,
        loading: root.isLoading,
        error: root.errorText,
        apps: root.apps
      })
    }
    function configure(user: string, host: string): void {
      root.sshUser = user
      root.sshHost = host
      mkdirProcess.command = ["mkdir", "-p", root.settingsPath.substring(0, root.settingsPath.lastIndexOf("/"))]
      mkdirProcess.running = true
    }
  }

  // Card height stays declarative: contentHeight binds to
  // mainColumn.implicitHeight below, so the border resizes whenever the
  // layout polish pass updates the column height (e.g. results arriving
  // while the panel is already open). Never assign contentHeight
  // imperatively here — that would destroy the binding.
}
