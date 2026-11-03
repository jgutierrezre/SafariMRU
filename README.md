# Safari MRU

A tiny macOS menu-bar app that gives Safari a proper **most-recently-used (MRU) tab switcher** — the `Ctrl+Tab` behaviour you know from Chrome, Firefox and Windows.

Unlike browser extensions, Safari MRU is fully native: it reads Safari's real tab list through the Accessibility API, so there is no polling, no injected script, and no perceptible delay when the switcher opens.

## Features

- **`Ctrl+Tab` / `Ctrl+Shift+Tab`** cycles tabs in MRU order. The preview appears while you hold Control and the tab only switches when you *release* it, so you can cycle through entries without loading pages.
- **Live thumbnails** of each tab (ScreenCaptureKit), with the tab's favicon, index and title. Cards are clickable and highlight on hover.
- **`Ctrl+1` … `Ctrl+9`** jump straight to a tab — MRU order during a cycle, tab-bar order otherwise. **`Ctrl+0`** jumps to the last tab.
- **`Esc`** cancels a cycle without switching.
- **Screen-clamped grid**: many tabs shrink to fit instead of overflowing off-screen.
- **Settings**: launch at login, enable/disable the number shortcuts, enable/disable thumbnails.

## Requirements

- macOS 13 Ventura or later (Apple Silicon; tested on macOS 27)
- **Accessibility** permission (required — used to read Safari's tabs and to intercept the shortcuts)
- **Screen Recording** permission (optional — only for thumbnails)

## Install

1. Download `SafariMRU-<version>.zip` from [Releases](https://github.com/jgutierrezre/SafariMRU/releases) and unzip it.
2. Move **SafariMRU.app** to `/Applications`.
3. The build is **signed with a self-signed certificate, not notarized** (there is no Apple Developer ID yet), so macOS will block the first launch. Either:
   - open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** for Safari MRU, or
   - clear the quarantine flag once:
     ```sh
     xattr -dr com.apple.quarantine /Applications/SafariMRU.app
     ```
4. Launch the app. It asks for **Accessibility** access — approve it in **System Settings → Privacy & Security → Accessibility**. No relaunch is needed; the app retries every couple of seconds until the permission is granted.
5. Optional: open **Settings…** from the menu-bar icon and enable **Show tab thumbnails**, then allow **Screen & System Audio Recording** when prompted. If the app is not listed there, click **+** and add `/Applications/SafariMRU.app`.

> The signing identity is stable, so **Accessibility and Screen Recording grants survive app updates**. They are only lost if you replace the app or remove the entry by hand.

## Usage

| Shortcut | Action |
| --- | --- |
| `Ctrl+Tab` | Cycle forward through recent tabs (switch on Control release) |
| `Ctrl+Shift+Tab` | Cycle backward |
| `Ctrl+1` … `Ctrl+9` | Jump to tab N (MRU order while cycling, tab-bar order otherwise) |
| `Ctrl+0` | Jump to the last tab |
| `Esc` | Cancel the cycle |
| Click a card | Switch to that tab immediately |

The preview closes as soon as you commit a switch.

## How it works

- **MRU order** comes from an `AXObserver` on Safari's `AXFocusedUIElement`. It fires after Safari switches tabs and reflects the newly active tab, so the order is exact and does not need polling.
- **Switching** is deferred: `Ctrl+Tab` only moves the highlight; the tab changes on Control release (or immediately when you click a card).
- **Thumbnails** are captured with ScreenCaptureKit, cropped to the page's content area and clamped to the visible display. Capture only runs while the switcher is **closed**, so the overlay can never end up inside a thumbnail; the cache is refreshed shortly after a tab becomes active and every few seconds while Safari is frontmost.
- Favicons are read from Safari's accessibility tree.

## Build from source

Requires Xcode 27.

```sh
git clone https://github.com/jgutierrezre/SafariMRU.git
cd SafariMRU
open SafariMRU/SafariMRU.xcodeproj   # build & run from Xcode
```

Or produce a distributable zip (self-signed if the identity is in your keychain, otherwise ad-hoc):

```sh
Scripts/build-release.sh 1.0.0                              # ad-hoc
SIGN_IDENTITY="SafariMRU Self-Signed" Scripts/build-release.sh 1.0.0   # stable identity
```

Pushing a `v*` tag builds the zip on GitHub Actions and attaches it to a release:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## Notes and limitations

- Safari only. Other browsers are not tracked.
- Thumbnails are cached per tab title and refreshed while the switcher is closed; a tab you open and switch away from within ~1 second may briefly show the previous capture.
- Accessibility access is broad by nature: the app sees key events globally (to intercept `Ctrl+Tab`) and reads Safari's UI tree. Nothing is sent anywhere; the app makes no network requests.

## License

[MIT](LICENSE)
