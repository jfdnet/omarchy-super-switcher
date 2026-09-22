# Omarchy Super Switcher

Visual window and workspace switching for [Omarchy](https://omarchy.org/) —
a derivative of ManateeLazyCat's
[omarchy-window-switcher](https://github.com/manateelazycat/omarchy-window-switcher)
(Orbit + Overview Workspaces) tuned for **stock Hyprland** with a
switch-to-workflow that lands windows the way you actually want them.

## What's different from upstream

1. **Fast Alt+Tab on stock Hyprland.** Upstream queries an
   `orbit-window-ready` readiness dispatcher during activation; that
   dispatcher does not exist on stock Hyprland, so every activation ended via
   a 1600 ms settle timeout (1.6–5 s per switch). Super Switcher treats the
   missing dispatcher as "unavailable", finishes activation immediately, and
   never re-issues the doomed query. Switch latency drops to ~100–300 ms.
2. **Switch targets land maximized (Super+Alt+F style).** Switching to a
   window you cannot see (other workspaces) lands it fullscreen in the
   Super+Alt+F style — `mode = "maximized"`, filling the work area while
   keeping bar/gaps. Already-fullscreen windows are never downgraded, and
   windows already visible on the current workspace are just focused, leaving
   the tiled layout intact.
3. **All-workspace scope by default.** The Alt+Tab cycle covers every normal
   workspace, so you can actually reach the windows you cannot see.
   (`scope: "visible"` in the plugin config restores upstream behavior.)

Everything else — the Orbit picker, live workspace overview, snap layouts,
settings panel — is upstream's work.

## Install

```bash
omarchy plugin add https://github.com/jfdnet/omarchy-super-switcher.git --enable
```

The plugin replaces Omarchy's built-in workspace bar widget and registers its
shortcuts at runtime (`Alt+Tab` / `Alt+Shift+Tab` windows, `Super+Tab` /
`Super+Shift+Tab` workspace overview).

If Orbit or Overview Workspaces is installed separately, remove those copies
first so two plugins do not compete for the same global shortcuts.

## Update / Remove

```bash
omarchy plugin update io.github.jfdnet.super-switcher
omarchy plugin remove io.github.jfdnet.super-switcher
```

Removing the plugin restores Omarchy's native `Alt+Tab`.

## Requirements

- Omarchy with the Quickshell plugin system (Hyprland 0.56+ with Lua config)

## Credits

- [ManateeLazyCat](https://github.com/manateelazycat) — Orbit and Overview
  Workspaces, the upstream this project derives from
- [Omarchy](https://omarchy.org/) — the desktop this targets

## 中文说明

为 [Omarchy](https://omarchy.org/) 打造的可视化窗口/工作区切换插件，基于
ManateeLazyCat 的 omarchy-window-switcher（Orbit + Overview Workspaces），
针对**原版 Hyprland** 做了体验调优：

- **Alt+Tab 不再卡顿**：上游依赖的 `orbit-window-ready` dispatcher 在原版
  Hyprland 上不存在，导致每次激活都吃满 1.6 秒兜底超时（实测 1.6–5 秒）。
  本插件检测到不可用后立即完成激活，切换延迟降至 ~100–300 毫秒。
- **切换落点默认 Super+Alt+F 式全屏**：切到看不见的窗口（其他工作区）时，
  自动以 maximized 模式铺满工作区；已全屏的窗口保持原模式不降级；当前
  工作区平铺窗口只聚焦，不打乱布局。
- **默认轮换所有工作区的窗口**（上游默认仅当前工作区）。

```bash
omarchy plugin add https://github.com/jfdnet/omarchy-super-switcher.git --enable
```

## License

[MIT](LICENSE) — 基于 ManateeLazyCat 的 omarchy-window-switcher（MIT）。
