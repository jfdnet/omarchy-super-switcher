# Omarchy Super Switcher

All-in-one switching for [Omarchy](https://omarchy.org/): windows, workspaces, and a
gesture-driven workspace gallery — derived from ManateeLazyCat's
[omarchy-window-switcher](https://github.com/manateelazycat/omarchy-window-switcher)
(Orbit + Overview Workspaces) and
[omarchy-workspace-gallery](https://github.com/manateelazycat/omarchy-workspace-gallery),
tuned for **stock Hyprland**.

## Features

### Alt+Tab — fast window switching (Orbit)
- Fast activation on stock Hyprland: upstream waits ~1.6 s per switch on an
  `orbit-window-ready` dispatcher that does not exist outside the author's
  environment; we finish activation immediately (~100–300 ms).
- Switch targets land **maximized in the Super+Alt+F style** when not already
  visible; already-fullscreen windows keep their mode; the cursor locks into
  the landed window so `follow_mouse` cannot steal focus.
- Cycles windows across **all workspaces** (`scope: "all"`).

### Workspace numbers on the bar
- Shows the numbers of occupied workspaces (focused one highlighted) when two
  or more are in use; hides itself with a single workspace.
- Click a number to jump; right-click for the overview.

### Workspace overview — Super+Tab
- Live workspace previews, cycling with Super+Tab / Super+Shift+Tab.

### Workspace Gallery — Super+A (gesture driven)
- Top strip: live thumbnails of every workspace — click to switch the preview.
- Bottom: large preview of the selected workspace — **click any window to
  switch to exactly that app** (workspace switch + focus + cursor lock).
- Drag windows between thumbnails to move them across workspaces.
- Three-finger swipe up/down to open/close, left/right to browse; two-finger
  pinch (or `Down`) compacts occupied workspaces into consecutive numbers.
- Gestures need one setup step: `python3 gallery/scripts/gesture_config.py install`
  (injects a managed block into `~/.config/hypr/input.lua`; `uninstall` removes it).

## Install

```bash
omarchy plugin add https://github.com/jfdnet/omarchy-super-switcher.git --enable
```

Replaces Omarchy's built-in workspace bar widget. Remove Orbit/Overview
Workspaces/Workspace Gallery copies first if you have them — this plugin
bundles all of them.

## Update / Remove

```bash
omarchy plugin update io.github.jfdnet.super-switcher
omarchy plugin remove io.github.jfdnet.super-switcher
```

## Requirements

- Omarchy with the Quickshell plugin system (Hyprland 0.56+ with Lua config)

## 中文说明

为 [Omarchy](https://omarchy.org/) 打造的一体化切换插件（基于 ManateeLazyCat 的
omarchy-window-switcher 与 omarchy-workspace-gallery，MIT 授权致谢）：

- **Alt+Tab**：原版 Hyprland 上不再卡 1.6 秒；跨工作区落点自动 Super+Alt+F 式
  全屏（已全屏的保持原模式）；光标锁进落点窗口防抢焦
- **顶栏工作区标号**：≥2 个工作区占用时显示编号（聚焦高亮，点击跳转）
- **Super+Tab**：工作区实时总览
- **Super+A 工作区 Gallery**：顶部缩略图切换预览、大预览里点哪个 app 就切到
  哪个 app、拖拽窗口跨工作区、三指手势开关、捏合压缩工作区编号
  （手势需执行一次 `python3 gallery/scripts/gesture_config.py install`）

## Credits

- [ManateeLazyCat](https://github.com/manateelazycat) — Orbit, Overview
  Workspaces, and Workspace Gallery, the upstream projects this derives from
- [Omarchy](https://omarchy.org/) — the desktop this targets

## License

[MIT](LICENSE) — derived from ManateeLazyCat's MIT-licensed plugins.
