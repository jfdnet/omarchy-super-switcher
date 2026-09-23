# Omarchy Super Switcher

Window management for [Omarchy](https://omarchy.org/): fast app switching,
workspace numbers on the bar, a live workspace overview, and a
gesture-driven workspace gallery — tuned for **stock Hyprland**.

## Features

### Alt+Tab — fast app switching
- Instant activation (~100–300 ms instead of multi-second stalls).
- Cycles windows across **all workspaces**.
- Switch targets land **maximized in the Super+Alt+F style** when not already
  visible; already-fullscreen windows keep their mode; the cursor locks into
  the landed window so `follow_mouse` cannot steal focus.

### Workspace numbers on the bar
- Shows the numbers of occupied workspaces (focused one highlighted) when two
  or more are in use; hides itself with a single workspace.
- Click a number to jump; right-click for the overview.

### Workspace overview — Super+Tab
- Live workspace previews, cycling with Super+Tab / Super+Shift+Tab.

### Workspace Gallery — Super+A (gesture driven)
- Top strip: occupied workspaces plus **one empty "＋" slot** — single click
  switches the preview, **double click enters the workspace**; double click
  (or a window drop) on the empty slot creates and enters a fresh workspace,
  and the next empty slot appears right away.
- Bottom: large preview of the selected workspace — **click any window to
  land on exactly that app, maximized**.
- Drag windows between thumbnails to move them across workspaces — drops
  always land where released, and ids renumber in real time once a drag
  settles so the bar always stays consecutive (dragging both windows off
  workspace 1 ends as workspaces 1 and 2, never 2 and 3). The gap closing
  runs as an animated compaction.
- Three-finger swipe up/down to open/close, left/right to browse.
- Gestures need one setup step:
  `python3 gallery/scripts/gesture_config.py install`
  (injects a managed block into `~/.config/hypr/input.lua`; `uninstall`
  removes it).

## Install

```bash
omarchy plugin add https://github.com/jfdnet/omarchy-super-switcher.git --enable
```

Replaces Omarchy's built-in workspace bar widget. Remove any standalone
window-switcher / workspace-gallery plugins first to avoid duplicate
shortcuts.

## Update / Remove

```bash
omarchy plugin update io.github.jfdnet.super-switcher
omarchy plugin remove io.github.jfdnet.super-switcher
```

## Requirements

- Omarchy with the Quickshell plugin system (Hyprland 0.56+ with Lua config)

---

## 中文说明

为 [Omarchy](https://omarchy.org/) 打造的窗口管理插件：

- **Alt+Tab**：秒级切换，跨所有工作区轮换；落点自动 Super+Alt+F 式全屏
  （已全屏的保持原模式）；光标锁进落点窗口防抢焦
- **顶栏工作区标号**：≥2 个工作区占用时显示编号（聚焦高亮，点击跳转）
- **Super+Tab**：工作区实时总览
- **Super+A 工作区 Gallery**：顶部缩略图 = 已占用工作区 + 一个「＋」空槽
  （单击预览/双击进入，双击或拖入空槽即新建并进入，槽满后自动追加下一个
  空槽）、大预览里点哪个 app 就全屏切到哪个 app、拖拽窗口跨工作区（落点
  即时生效，拖完实时压缩编号、顶栏始终连续，合拢带动画）、三指手势开关
  （手势需执行一次 `python3 gallery/scripts/gesture_config.py install`）

## License

[MIT](LICENSE)
