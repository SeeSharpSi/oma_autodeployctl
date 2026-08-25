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

  // Theme-derived palette (no hardcoded colors)
  readonly property color fg: Color.popups.text
  readonly property color dimText: Qt.darker(Color.popups.text, 1.4)
  readonly property color dimmerText: Qt.darker(Color.popups.text, 1.7)
  readonly property color healthyColor: Color.accent
  readonly property color barFg: root.bar ? root.bar.barForeground : Color.foreground

  function appColor(a) {
    return appOk(a) ? healthyColor : Color.urgent
  }

  function tint(c, alpha) {
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }

  function firstLine(s) {
    return String(s || "").split("\n")[0]
  }

  readonly property bool anyUnhealthy: errorText !== "" || (apps.length > 0 && healthyCount() < apps.length)

  readonly property color barStatusColor: !configured ? Qt.darker(barFg, 1.55)
    : anyUnhealthy ? Color.urgent
    : barFg

  readonly property string barTooltip: !configured ? "Autodeploy — not configured (click to set up)"
    : isLoading ? "Autodeploy — fetching…"
    : errorText !== "" ? "Autodeploy — " + firstLine(errorText)
    : apps.length === 0 ? "Autodeploy — no apps"
    : "Autodeploy — " + apps.length + " app" + (apps.length === 1 ? "" : "s") + " • " + healthyCount() + " healthy"

  property bool opened: false
  property bool configured: false
  property bool showingSetup: false
  property string sshUser: ""
  property string sshHost: ""
  readonly property int defaultSshPort: 22
  property string sshPort: ""
  property var apps: []
  property string errorText: ""
  property string statusText: ""
  property bool isLoading: false
  property string lastUpdated: ""

  component StatusChip: Rectangle {
    id: chip
    property string label: ""
    property color tone: root.healthyColor

    radius: height / 2
    implicitHeight: chipLabel.implicitHeight + Style.space(9)
    implicitWidth: chipRow.implicitWidth + Style.space(16)
    color: root.tint(tone, 0.12)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Rectangle {
        width: Style.space(7)
        height: Style.space(7)
        radius: width / 2
        color: chip.tone
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: chipLabel
        text: chip.label
        color: chip.tone
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

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
    const portText = portField.text.trim()
    let port = root.defaultSshPort
    if (portText !== "") {
      port = Number(portText)
      if (!Number.isInteger(port) || port < 1 || port > 65535) {
        setupErrorText = "Port must be a number between 1 and 65535."
        return
      }
    }
    setupErrorText = ""
    sshUser = user
    sshHost = host
    sshPort = String(port)
    mkdirProcess.command = ["mkdir", "-p", settingsPath.substring(0, settingsPath.lastIndexOf("/"))]
    mkdirProcess.running = true
  }

  function writeSettings() {
    const payload = { user: sshUser, host: sshHost, port: Number(sshPort) }
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
      "-p", sshPort !== "" ? sshPort : String(defaultSshPort),
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
    foreground: root.barStatusColor
    slotSize: Style.bar.statusSlot
    tooltipText: root.barTooltip
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
        blocked: (userField && userField.activeFocus) || (hostField && hostField.activeFocus) || (portField && portField.activeFocus)
      onCloseRequested: root.close()

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: Style.space(12)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(7)

          Text {
            text: "Autodeploy"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }
          Text {
            visible: root.configured && root.sshUser !== ""
            text: root.sshUser + "@" + root.sshHost + (root.sshPort !== "" && root.sshPort !== String(root.defaultSshPort) ? ":" + root.sshPort : "")
            color: root.dimText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Layout.alignment: Qt.AlignVCenter
          }
          Item { Layout.fillWidth: true }

          PanelActionButton {
            visible: root.configured && !root.showingSetup
            iconText: "󰑐"
            foreground: root.fg
            tooltipText: "Refresh status"
            enabled: !root.isLoading
            onClicked: root.fetchStatus()
          }
          PanelActionButton {
            visible: root.configured && !root.showingSetup
            iconText: "󰏫"
            foreground: root.fg
            tooltipText: "Edit connection"
            onClicked: root.editConnection()
          }
          PanelActionButton {
            iconText: "󰅙"
            foreground: root.fg
            tooltipText: "Close"
            onClicked: root.close()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.fg
        }

        // ---- Setup form (first click / edit) ----
        ColumnLayout {
          visible: root.showingSetup
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "SSH connection"
          }

          Text {
            Layout.fillWidth: true
            text: "Connect over SSH to a host running autodeployctl. The public key of this machine must already be installed for the user."
            wrapMode: Text.Wrap
            color: root.dimText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              Text {
                text: "User"
                color: root.dimText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: userField
                Layout.fillWidth: true
                text: root.sshUser
                placeholderText: "e.g. andor"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onAccepted: hostField.forceActiveFocus()
                Keys.onEscapePressed: root.close()
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              Text {
                text: "Host or IP"
                color: root.dimText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: hostField
                Layout.fillWidth: true
                text: root.sshHost
                placeholderText: "e.g. 192.168.254.10"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onAccepted: root.saveConnection()
                Keys.onEscapePressed: root.close()
              }
            }

            ColumnLayout {
              Layout.preferredWidth: Style.space(110)
              spacing: Style.space(4)

              Text {
                text: "Port"
                color: root.dimText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: portField
                Layout.fillWidth: true
                text: root.sshPort !== "" ? root.sshPort : String(root.defaultSshPort)
                placeholderText: "22"
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 65535 }
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                onAccepted: root.saveConnection()
                Keys.onEscapePressed: root.close()
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Button {
              text: root.configured ? "Save" : "Connect"
              bordered: true
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
          Row {
            visible: root.isLoading
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)

            Text {
              text: "↻"
              color: root.dimText
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              anchors.verticalCenter: parent.verticalCenter

              RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: root.isLoading
              }
            }

            Text {
              text: "Fetching status from " + root.sshUser + "@" + root.sshHost + "…"
              color: root.dimText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.italic: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Error box
          Rectangle {
            visible: !root.isLoading && root.errorText !== ""
            Layout.fillWidth: true
            radius: Style.cornerRadius
            color: root.tint(Color.urgent, 0.08)
            border.width: 1
            border.color: root.tint(Color.urgent, 0.35)
            implicitHeight: errRow.implicitHeight + Style.space(16)

            RowLayout {
              id: errRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: "⚠"
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignTop
              }

              Text {
                Layout.fillWidth: true
                text: root.errorText
                wrapMode: Text.Wrap
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Summary chips
          RowLayout {
            visible: !root.isLoading && root.errorText === "" && root.apps.length > 0
            Layout.fillWidth: true
            spacing: Style.space(8)

            StatusChip {
              label: root.apps.length + " app" + (root.apps.length === 1 ? "" : "s")
              tone: root.fg
            }
            StatusChip {
              label: root.healthyCount() + " healthy"
              tone: root.healthyColor
            }
            StatusChip {
              visible: root.healthyCount() < root.apps.length
              label: (root.apps.length - root.healthyCount()) + " down"
              tone: Color.urgent
            }
            Item { Layout.fillWidth: true }
            Text {
              visible: root.lastUpdated !== ""
              text: root.lastUpdated
              color: root.dimmerText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              Layout.alignment: Qt.AlignVCenter
            }
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

                Rectangle {
                  id: card
                  required property var modelData

                  readonly property color stateColor: root.appColor(modelData)

                  Layout.fillWidth: true
                  implicitHeight: cardCol.implicitHeight + Style.space(20)
                  radius: Style.cornerRadius
                  color: root.tint(root.fg, 0.04)
                  border.width: 1
                  border.color: root.tint(root.fg, 0.10)

                  ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(4)

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(8)

                      // Status dot with soft halo
                      Item {
                        width: Style.space(18)
                        height: Style.space(18)
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                          anchors.fill: parent
                          radius: width / 2
                          color: root.tint(card.stateColor, 0.18)
                        }

                        Rectangle {
                          width: Style.space(8)
                          height: Style.space(8)
                          radius: width / 2
                          anchors.centerIn: parent
                          color: card.stateColor
                        }
                      }

                      Text {
                        Layout.fillWidth: true
                        text: modelData.app || "?"
                        color: root.fg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.alignment: Qt.AlignVCenter
                      }

                      // Container-state badge
                      Rectangle {
                        readonly property string stateLabelText: modelData.container_state || (modelData.container_running === true ? "running" : "unknown")
                        radius: height / 2
                        color: root.tint(card.stateColor, 0.15)
                        implicitWidth: stateText.implicitWidth + Style.space(14)
                        implicitHeight: stateText.implicitHeight + Style.space(5)
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                          id: stateText
                          anchors.centerIn: parent
                          text: parent.stateLabelText
                          color: card.stateColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                    }

                    Text {
                      visible: root.appDetails(modelData) !== ""
                      Layout.fillWidth: true
                      Layout.leftMargin: Style.space(26)
                      text: root.appDetails(modelData)
                      wrapMode: Text.Wrap
                      color: root.dimmerText
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      visible: modelData.valid === false || (modelData.error !== null && modelData.error !== undefined && modelData.error !== "")
                      Layout.fillWidth: true
                      Layout.leftMargin: Style.space(26)
                      text: modelData.error || "Manifest invalid"
                      wrapMode: Text.Wrap
                      color: Color.urgent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            QQC.ScrollBar.vertical: QQC.ScrollBar {
              policy: QQC.ScrollBar.AsNeeded
            }
          }

          // Empty state
          ColumnLayout {
            visible: !root.isLoading && root.errorText === "" && root.apps.length === 0 && root.configured
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(6)

            Text {
              text: "󰒋"
              color: root.dimmerText
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              Layout.alignment: Qt.AlignHCenter
            }

            Text {
              text: "No apps found on the host."
              wrapMode: Text.Wrap
              color: root.dimText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignHCenter
            }
          }
        }

        // Footer hint
        Text {
          visible: !root.showingSetup
          Layout.fillWidth: true
          text: "Read-only view • ssh -p " + (root.sshPort !== "" ? root.sshPort : String(root.defaultSshPort)) + " " + (root.sshUser !== "" ? root.sshUser + "@" + root.sshHost : "user@host") + " autodeployctl status --json"
          wrapMode: Text.Wrap
          color: root.dimmerText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          opacity: 0.55
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
          root.sshPort = parsed.port !== undefined && Number(parsed.port) !== root.defaultSshPort ? String(parsed.port) : ""
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
        port: root.sshPort !== "" ? Number(root.sshPort) : root.defaultSshPort,
        loading: root.isLoading,
        error: root.errorText,
        apps: root.apps
      })
    }
    function configure(user: string, host: string, port: int): void {
      root.sshUser = user
      root.sshHost = host
      if (port >= 1 && port <= 65535) root.sshPort = String(port)
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
