import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // ── Smart Gaps: 单平铺窗口工作区自动去边距/边框 ─────────────────
  property bool applied: false
  property bool applyPending: false
  property bool unloading: false
  property var screensaverWindows: ({})

  readonly property string screensaverClass: "org.omarchy.screensaver"
  readonly property string enableRuleCode: 'local selector = "w[tv1]s[false]"; if _G.omarchy_smart_gaps_rule and _G.omarchy_smart_gaps_rule_selector ~= selector then _G.omarchy_smart_gaps_rule:set_enabled(false); _G.omarchy_smart_gaps_rule = nil end; if _G.omarchy_smart_gaps_rule then _G.omarchy_smart_gaps_rule:set_enabled(true) else _G.omarchy_smart_gaps_rule = hl.workspace_rule({ workspace = selector, gaps_out = 0, gaps_in = 0, no_border = true }) end; _G.omarchy_smart_gaps_rule_selector = selector'
  readonly property string disableRuleCode: 'if _G.omarchy_smart_gaps_rule then _G.omarchy_smart_gaps_rule:set_enabled(false) end'

  // ── Rounded Corners: 通过 looknfeel.lua 配置实现 ────────────────
  // 全局圆角写入 ~/.config/hypr/looknfeel.lua（omarchy Lua 配置的标准用户覆盖点）
  // 运行时 hyprctl keyword 被 Lua 解析器拦截, 只能走配置文件 + reload 路径
  readonly property string configFile: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"
  readonly property string roundingBlock: "\n-- Arrangements plugin: 全局窗体圆角\nhl.config({\n  decoration = {\n    rounding = 12,\n  },\n})\n"
  readonly property string roundingMarker: "Arrangements plugin"

  function applyRule() {
    if (root.unloading)
      return

    if (applyProcess.running) {
      root.applyPending = true
      return
    }

    root.applyPending = false
    applyProcess.command = ["hyprctl", "eval", root.enableRuleCode]
    applyProcess.running = true
  }

  function ensureRoundingInConfig() {
    roundingCheck.command = ["grep", "-q", root.roundingMarker, root.configFile]
    roundingCheck.running = true
  }

  function eventParts(event, count) {
    try {
      if (event && event.parse)
        return event.parse(count)
    } catch (error) {
    }

    return String(event?.data ?? "").split(",")
  }

  function rememberScreensaver(address) {
    var key = String(address || "")
    if (key === "")
      return

    var next = Object.assign({}, root.screensaverWindows)
    next[key] = true
    root.screensaverWindows = next
  }

  function forgetScreensaver(address) {
    var key = String(address || "")
    if (!root.screensaverWindows[key])
      return false

    var next = Object.assign({}, root.screensaverWindows)
    delete next[key]
    root.screensaverWindows = next
    return true
  }

  function handleHyprlandEvent(event) {
    var name = String(event?.name ?? "").toLowerCase()

    if (name === "openwindow") {
      var opened = eventParts(event, 4)
      if (String(opened[2] || "") === root.screensaverClass)
        rememberScreensaver(opened[0])
    } else if (name === "closewindow") {
      var closed = eventParts(event, 1)
      if (forgetScreensaver(closed[0]))
        applyTimer.restart()
    } else if (name === "configreloaded") {
      applyTimer.restart()
    }
  }

  function statusJson() {
    return JSON.stringify({
      smartGaps: {
        applied: root.applied,
        selector: "w[tv1]s[false]",
        gapsIn: 0,
        gapsOut: 0,
        borders: false
      },
      roundedCorners: {
        enabled: true,
        radius: 8,
        method: "looknfeel.lua config"
      }
    })
  }

  Process {
    id: applyProcess

    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "" && text.trim() !== "ok")
          console.log("super-switcher arrangements: " + text.trim())
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          console.warn("super-switcher arrangements: " + text.trim())
      }
    }

    onExited: function(exitCode) {
      root.applied = exitCode === 0
      if (root.applyPending && !root.unloading)
        Qt.callLater(root.applyRule)
    }
  }

  Process {
    id: roundingCheck

    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.unloading) {
        // 标记不存在, 追加并 reload
        roundingAppend.running = true
      }
    }
  }

  Process {
    id: roundingAppend

    command: ["sh", "-c", "echo '" + root.roundingBlock + "' >> " + root.configFile + " && hyprctl reload"]

    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          console.log("super-switcher arrangements rounding: " + text.trim())
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          console.warn("super-switcher arrangements rounding: " + text.trim())
      }
    }
  }

  Timer {
    id: applyTimer
    interval: 100
    repeat: false
    onTriggered: root.applyRule()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  IpcHandler {
    target: "io.github.jfdnet.super-switcher.arrangements"

    function status(): string { return root.statusJson() }
  }

  Component.onCompleted: {
    applyTimer.start()
    ensureRoundingInConfig()
  }

  Component.onDestruction: {
    root.unloading = true
    Quickshell.execDetached(["hyprctl", "eval", root.disableRuleCode])
    // 圆角不卸载——它是用户配置的一部分, 插件只负责确保它存在
    // 要移除: 手动删 looknfeel.lua 中的 Arrangements plugin 块
  }
}
