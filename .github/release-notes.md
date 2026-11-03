A native, most-recently-used tab switcher for Safari.

### Install

1. Download the `SafariMRU-x.y.z.zip` below and unzip it.
2. Move **SafariMRU.app** to `/Applications`.
3. This build is **ad-hoc signed, not notarized**, so macOS blocks the first launch.
   Open **System Settings → Privacy & Security**, click **Open Anyway** for Safari MRU
   (or run `xattr -dr com.apple.quarantine /Applications/SafariMRU.app`).
4. Launch it and grant **Accessibility** in **System Settings → Privacy & Security → Accessibility**.
   No relaunch needed — the app retries until the permission is in place.
5. Optional: menu bar icon → **Settings…** → **Show tab thumbnails**, then allow **Screen Recording**.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Cycle recent tabs (switch on Control release) |
| `Ctrl+1` … `Ctrl+9` | Jump to a tab (MRU order mid-cycle, tab-bar order otherwise) |
| `Ctrl+0` | Last tab |
| `Esc` | Cancel |
| Click a card | Switch immediately |

Requires macOS 27 on Apple Silicon.
