pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Application lookup for the overview's search mode.
// Queries DesktopEntries and applies Omarchy's launcher.hides filter so
// results agree with the Super+Space menu.
Singleton {
    id: root

    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

    // NoDisplay alone is not enough: Omarchy hides a further list of desktop ids
    // that ship without it (btop, cmake-gui, avahi-discover and 35 others), so
    // filtering on NoDisplay only would surface entries its own launcher hides.
    property var hiddenIds: ({})
    property var iconIndex: ({})
    property var pendingIconIndex: ({})

    function normalizeDesktopId(value) {
        return String(value || "").trim().replace(/\.desktop$/, "");
    }

    FileView {
        path: `${root.omarchyPath}/default/omarchy/launcher.hides`
        watchChanges: true
        printErrors: false
        onLoaded: root.loadHides(text())
        onFileChanged: reload()
        // Not fatal: without the list, application results simply include the
        // entries Omarchy's own launcher hides. Worth saying so out loud rather
        // than silently diverging from the Super+Space menu.
        onLoadFailed: {
            console.warn("io.github.jfdnet.super-switcher: no launcher.hides at "
                + `${root.omarchyPath}/default/omarchy/launcher.hides`
                + " -- hidden applications will show in search results");
            root.loadHides("");
        }
    }

    function loadHides(rawText) {
        const next = ({});
        const lines = String(rawText || "").split(/\n/);
        for (let i = 0; i < lines.length; ++i) {
            const id = root.normalizeDesktopId(lines[i]);
            if (id.length > 0)
                next[id] = true;
        }
        root.hiddenIds = next;
    }

    // 图标文件只允许来自系统图标根目录(与 iconIndexScanCommand 同源),
    // 阻断"窗口类名/桌面 Icon= 任意绝对路径 → 同步宿主解码"的攻击面。
    readonly property var allowedIconRoots: {
        const dirs = [];
        const home = Quickshell.env("HOME") || "";
        if (home.length > 0)
            dirs.push(home + "/.icons", home + "/.local/share/icons");
        const xdg = Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share";
        xdg.split(":").forEach(d => {
            const t = String(d || "").replace(/\/+$/, "");
            if (t.length > 0)
                dirs.push(t + "/icons");
        });
        dirs.push("/usr/share/pixmaps");
        return dirs;
    }

    // 文本规范化 ".."/"." 段(QML 无 realpath), 再对白名单根做前缀匹配。
    function isAllowedIconPath(path) {
        const raw = String(path || "");
        const p = raw.startsWith("file://") ? raw.slice(7) : raw;
        if (!p.startsWith("/"))
            return false;
        const canon = p.split("/").reduce((acc, seg) => {
            if (!seg || seg === ".")
                return acc;
            if (seg === "..") {
                acc.pop();
                return acc;
            }
            acc.push(seg);
            return acc;
        }, []).join("/");
        return root.allowedIconRoots.some(r => canon.length > r.length && canon.startsWith(r + "/"));
    }

    function iconSource(iconName, fallback) {
        const name = String(iconName || fallback || "application-x-executable").trim();
        if (name.length === 0)
            return "";
        // image:// provider 名可被应用控制且不经文件白名单, 一律拒绝,
        // 失败回退到 NerdIcon 字形。
        if (name.startsWith("image://"))
            return "";
        if (name.startsWith("file://"))
            return root.isAllowedIconPath(name) ? name : "";
        if (name.startsWith("/"))
            return root.isAllowedIconPath(name) ? "file://" + name : "";
        const indexed = root.iconIndex[name];
        if (indexed)
            return root.isAllowedIconPath(indexed) ? "file://" + indexed : "";
        const path = Quickshell.iconPath(name, true);
        return path ? (path.startsWith("/") ? "file://" + path : path) : "";
    }

    function iconIndexScanCommand() {
        return [
            'dirs="$HOME/.icons $HOME/.local/share/icons";',
            'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
            'for ext in svg png; do',
            '  for base in $dirs; do',
            '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
            '  done;',
            '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
            'done'
        ].join(" ");
    }

    function indexIconLine(path) {
        const value = String(path || "").trim();
        const slash = value.lastIndexOf("/");
        const file = slash >= 0 ? value.slice(slash + 1) : value;
        const dot = file.lastIndexOf(".");
        const name = dot > 0 ? file.slice(0, dot) : file;
        if (name.length > 0 && root.pendingIconIndex[name] === undefined)
            root.pendingIconIndex[name] = value;
    }

    Process {
        id: iconIndexScan
        command: ["bash", "-c", root.iconIndexScanCommand()]
        stdout: SplitParser {
            onRead: function(line) { root.indexIconLine(line); }
        }
        onStarted: root.pendingIconIndex = ({})
        onExited: root.iconIndex = root.pendingIconIndex
    }

    Component.onCompleted: iconIndexScan.running = true

    function guessIcon(name) { return name || "application-x-executable" }

    function entryHaystack(entry) {
        return [
            entry?.name || "",
            entry?.genericName || "",
            entry?.comment || "",
            entry?.id || ""
        ].join(" ").toLowerCase();
    }

    // Ranked by how early the match lands: names starting with the query first,
    // then names containing it, then entries matching only on comment or id.
    // Ties break alphabetically.
    function fuzzyQuery(query) {
        const needle = String(query || "").toLowerCase().trim();
        if (needle.length === 0)
            return [];

        const values = DesktopEntries.applications.values || [];
        const scored = [];
        const seen = ({});
        for (let i = 0; i < values.length; ++i) {
            const entry = values[i];
            if (!entry || entry.noDisplay)
                continue;
            if (root.hiddenIds[root.normalizeDesktopId(entry.id)])
                continue;
            // The same desktop file can be exposed once from the user's
            // applications directory and once from the system directory,
            // often with ids such as Discord and omarchy-Discord. Keep one
            // result when the visible application metadata is identical.
            const position = root.entryHaystack(entry).indexOf(needle);
            if (position < 0)
                continue;
            const duplicateKey = [
                entry.name || "",
                entry.genericName || "",
                entry.comment || "",
                entry.icon || ""
            ].join("\u001f").toLowerCase();
            if (seen[duplicateKey])
                continue;
            seen[duplicateKey] = true;
            const name = String(entry.name || "");
            const nameIndex = name.toLowerCase().indexOf(needle);
            const score = nameIndex === 0 ? 0 : (nameIndex > 0 ? 1 : 2 + position);
            scored.push({ entry: entry, score: score, name: name });
        }

        scored.sort((a, b) => (a.score - b.score) || a.name.localeCompare(b.name));
        return scored.map(item => item.entry);
    }

    // uwsm-app keeps the app out of wayland-wm@.service, and gtk-launch resolves
    // ids with spaces or ones UWSM rejects. The .desktop suffix is required or
    // ids like org.telegram.desktop will not resolve. Same approach as AppLibrary.
    function launchApp(app) {
        const id = String(app?.id || "");
        if (id.length === 0)
            return false;
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", `${id}.desktop`]);
        return true;
    }
}
