# NotChi

A free, open-source command center that lives in your MacBook's notch. It shows a small pill at the top center on Macs without a notch.

Hover over the notch, or press **⌥⌘N**, to open it.

| Module | What it does |
| --- | --- |
| **Clipboard** | Automatic history of text, rich text, code, links, images and files. Includes search and type filters. Click an item to paste it into the app you're using. |
| **Stash** | A permanent drop zone at the top of the panel. Drag files, images or text in, pin what you want to keep, and drag items back out anywhere. |
| **Ports** | Lists the local dev servers that are listening, with a live health check and latency for each. One click kills a stuck process. |
| **Stats** | CPU, memory pressure and network up/down next to the notch, with sparklines in the panel. |

On the roadmap: Wi-Fi file transfer to and from your phone (QR code plus browser, no app needed), a Now Playing controller, and a calendar agenda with one-click meeting joins.

## Install

1. Download `NotChi.dmg` from [Releases](../../releases) and drag **NotChi** into Applications.
2. NotChi isn't notarized, because the project has no paid Apple developer account. Open it once like this:
   - In Finder, right-click NotChi and choose **Open**, then **Open**. Or run:
     ```sh
     xattr -dr com.apple.quarantine /Applications/NotChi.app
     ```
3. **Optional:** to turn on auto-paste, grant Accessibility access in **System Settings → Privacy & Security → Accessibility**. Without it, choosing an item copies it and you press ⌘V yourself.

> **Note:** Release builds are ad-hoc signed, so macOS treats each new version as a new app. After an update you may need to remove NotChi from the Accessibility list and add it again.

## Permissions

| Permission | Used for |
| --- | --- |
| Accessibility | Posting ⌘V into the frontmost app (auto-paste). |
| None | Hover detection, the global shortcut (a Carbon hotkey), clipboard polling, system stats, port scanning (libproc, current user's processes). |

NotChi skips clipboard items that password managers mark as concealed or transient. You can also exclude apps by bundle ID in Settings. All data stays local in `~/Library/Application Support/NotChi`.

## Build from source

Requires Xcode 15 or later on macOS 14 or later.

```sh
swift build                  # debug build
swift run                    # run directly (no .app bundle)
scripts/build-app.sh         # universal build/NotChi.app + build/NotChi.dmg
```

Open `Package.swift` in Xcode to develop with the full IDE.

**Stable signing for development:** ad-hoc signatures change on every build, which resets the Accessibility grant. To avoid that, create a self-signed code-signing certificate in Keychain Access:

1. Go to **Certificate Assistant → Create a Certificate…**, name it `NotChi Dev`, and set the type to *Code Signing*.
2. Build with:

```sh
SIGN_ID="NotChi Dev" scripts/build-app.sh
```

## Architecture

```
Sources/NotChi/
  App/        entry point, AppDelegate (menu bar item), Settings
  Notch/      NotchPanel (non-activating overlay), NotchController (hover/hotkey/collapse),
              NotchGeometry (notch detection), HotKey (Carbon), ModuleHost
  UI/         NotchRootView, NotchShape, tab bar, settings
  Modules/    one folder per feature, each implementing the NotchModule protocol
```

To add a feature, implement `NotchModule` (see `Modules/Module.swift`) and register it in `AppDelegate`.

## Releasing

Push a tag like `v0.1.0`. GitHub Actions builds the DMG and attaches it to the release.

## License

MIT
