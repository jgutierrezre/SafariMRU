// background.js — tracks tab MRU order and metadata, captures thumbnails, and
// pushes the state to the native host app over a localhost HTTP endpoint.

const PORT = 49153;
const STATE_URL = `http://127.0.0.1:${PORT}/state`;

const windowMRU = new Map();   // windowId -> [tabId, ...] most-recent first
const tabInfo = new Map();     // tabId -> { title, url, favIconUrl, index }
const thumbnails = new Map();  // tabId -> data URL

function getMRU(windowId) {
    if (!windowMRU.has(windowId)) windowMRU.set(windowId, []);
    return windowMRU.get(windowId);
}

function promote(windowId, tabId) {
    const mru = getMRU(windowId);
    const i = mru.indexOf(tabId);
    if (i !== -1) mru.splice(i, 1);
    mru.unshift(tabId);
}

async function refreshTabInfo(tabId) {
    try {
        const t = await browser.tabs.get(tabId);
        tabInfo.set(tabId, {
            title: t.title || "",
            url: t.url || "",
            favIconUrl: t.favIconUrl || "",
            index: t.index ?? 0,
        });
    } catch {
        // tab closed mid-refresh
    }
}

async function captureThumbnail(tabId) {
    try {
        const res = await browser.tabs.sendMessage(tabId, { type: "capture" });
        if (res && res.dataUrl) {
            thumbnails.set(tabId, res.dataUrl);
        }
    } catch {
        // content script not loaded (privileged page, discarded tab, etc.)
    }
}

async function pushState() {
    let win;
    try {
        win = await browser.windows.getLastFocused({ windowTypes: ["normal"] });
    } catch {
        return;
    }
    if (!win || win.id === undefined) return;

    const ordered = [];
    for (const id of getMRU(win.id)) {
        const info = tabInfo.get(id);
        if (!info) continue;
        ordered.push({ ...info, thumbnail: thumbnails.get(id) || "" });
    }

    try {
        await fetch(STATE_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ tabs: ordered }),
        });
    } catch {
        // native host not running; ignore
    }
}

browser.tabs.onActivated.addListener(async ({ tabId, windowId }) => {
    promote(windowId, tabId);
    await refreshTabInfo(tabId);
    await captureThumbnail(tabId);
    await pushState();
});

browser.tabs.onCreated.addListener(async (tab) => {
    if (tab.id !== undefined) {
        await refreshTabInfo(tab.id);
    }
});

browser.tabs.onRemoved.addListener((tabId) => {
    tabInfo.delete(tabId);
    thumbnails.delete(tabId);
    for (const mru of windowMRU.values()) {
        const i = mru.indexOf(tabId);
        if (i !== -1) mru.splice(i, 1);
    }
});

browser.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
    if (changeInfo.status === "complete" && tab.active) {
        await refreshTabInfo(tabId);
        await captureThumbnail(tabId);
        await pushState();
    } else if (changeInfo.title || changeInfo.favIconUrl) {
        await refreshTabInfo(tabId);
        await pushState();
    }
});

// Initial sync: seed MRU order and metadata for existing tabs.
(async () => {
    try {
        const wins = await browser.windows.getAll({ populate: true, windowTypes: ["normal"] });
        for (const win of wins) {
            const tabs = win.tabs || [];
            const active = tabs.find((t) => t.active);
            const rest = tabs.filter((t) => !t.active);

            for (const t of tabs) {
                if (t.id === undefined) continue;
                tabInfo.set(t.id, {
                    title: t.title || "",
                    url: t.url || "",
                    favIconUrl: t.favIconUrl || "",
                    index: t.index ?? 0,
                });
            }

            const mru = getMRU(win.id);
            if (active && active.id !== undefined) mru.push(active.id);
            for (const t of rest) {
                if (t.id !== undefined) mru.push(t.id);
            }

            if (active && active.id !== undefined) {
                await captureThumbnail(active.id);
            }
        }
        await pushState();
    } catch {
        // ignore startup errors
    }
})();
