# NotChi

A free, source-available command center that lives in your MacBook's notch. It shows a small pill at the top center on Macs without a notch.

**The Zero-App Android Solution:** NotChi is the only macOS utility that allows seamless, high-speed local file sharing with Android devices using their **native, built-in Quick Share feature**. Your phone doesn't need any third-party app companion, client downloads, or setup configurations. If it has Android Quick Share, it works out of the box.

Hover over the notch, or press **⌥⌘N**, to open it.

| Module | What it does |
| --- | --- |
| **Clipboard** | Automatic history of text, rich text, code, links, images and files. Includes search and type filters. Click an item to paste it into the app you're using. |
| **Stash** | A permanent drop zone at the top of the panel. Drag files, images or text in, pin what you want to keep, and drag items back out anywhere. |
| **Ports** | Lists the local dev servers that are listening, with a live health check and latency for each. One click kills a stuck process. |
| **Stats** | CPU, memory pressure and network up/down next to the notch, with sparklines in the panel. |
| **Phone transfer** | Send and receive files with your iPhone (AirDrop) or Android phone (Quick Share). Choose your phone in Settings → Phone. |

On the roadmap: a Now Playing controller and a calendar agenda with one-click meeting joins.

## Installation

1. Download `NotChi.dmg` from the [latest release](../../releases/latest).
2. Open the DMG and drag **NotChi** into **Applications**.
3. Launch NotChi from Applications. The first time, follow the steps below.

### 🚀 macOS Gatekeeper notice

Because this is a free, source-available project, the `.dmg` isn't signed with a paid Apple Developer ID. When you first open the app, macOS blocks it by default.

To open the app safely, without any terminal commands:

1. Double-click NotChi. When the security warning pops up, click **Done** (or **OK**/**Cancel**, depending on your macOS version).
2. Open **System Settings** and go to **Privacy & Security**.
3. Scroll down to the **Security** section.
4. You'll see a note saying NotChi was blocked. Click **Open Anyway** and enter your Mac password, or use Touch ID.
5. Click **Open** in the confirmation that follows.

You only need to do this once. After approving it, NotChi launches normally.

> **Tip:** the **Open Anyway** button only shows for about an hour after the blocked launch. If you don't see it, double-click NotChi again and go back to Privacy & Security.
>
> On macOS 15 (Sequoia) and later, right-clicking the app and choosing **Open** no longer skips this check, so use the steps above.

<details>
<summary>Prefer the terminal?</summary>

This removes the quarantine flag macOS adds to downloaded files:

```sh
xattr -dr com.apple.quarantine /Applications/NotChi.app
```

</details>

### First-run setup

- **Find it:** NotChi has no Dock icon. Move your pointer onto the notch, or press **⌥⌘N**, to open it. On Macs without a notch it's a small pill at the top center of the screen.
- **Turn on auto-paste (recommended):** go to **System Settings → Privacy & Security → Accessibility** and switch **NotChi** on. You can also click **Open System Settings** in NotChi → Settings → Permissions.
  - **What it does:** lets NotChi paste a clipboard item straight into the app you're using. It also keeps the stats beside the notch from covering your menus and menu bar icons.
  - **Without it:** picking an item only copies it, and you press ⌘V yourself.
- **Launch at login:** turn it on in **Settings → General**.

### Updating

Download the new DMG and replace the app in Applications. You may need to repeat the Gatekeeper steps once for the new version.

If auto-paste stops working after an update, the Accessibility switch may be on for the *old* copy. Go to **Privacy & Security → Accessibility**, select NotChi, remove it with **−**, then add it again with **+**. NotChi's Settings → Permissions shows whether access is currently granted.

### Troubleshooting

| Problem | Fix |
| --- | --- |
| "NotChi is damaged and can't be opened" | The download was quarantined. Use the terminal command above, or download again. |
| Nothing appears at the notch | Check that NotChi is running in Activity Monitor. Then try **⌥⌘N**, and check **Settings → General → Expand on hover**. |
| ⌥⌘N does nothing | Another app may use that shortcut. Pick a different one in **Settings → General**. |
| Clicking an item copies but doesn't paste | Grant Accessibility (see above). If it already looks granted, remove NotChi from the list and add it again. |
| Stats next to the notch disappeared | That's intentional: a side hides when your app's menus or menu bar icons need the space. You can turn the stats off in **Settings → General**. |
| A Docker/OrbStack container is missing from Ports | Make sure Docker/OrbStack is running and the container publishes a port (`-p 8080:80`). |

### Uninstall

Quit NotChi from **Settings → General → Quit NotChi**. Then delete it from Applications and remove its data:

```sh
rm -rf ~/Library/Application\ Support/NotChi
defaults delete com.notchi.app
```

## Phone transfer

Pick your phone in **Settings → Phone** (iPhone, Android, Both or None). Only the services for that choice run, and with **None** nothing listens on the network.

**iPhone (AirDrop)**
- **Mac → iPhone:** drop files on **iPhone** next to the stash, or right-click a stash item → Send to iPhone. The system AirDrop picker opens.
- **iPhone → Mac:** AirDrop as usual. When the file lands in Downloads, NotChi shows it in the notch and adds it to the stash.

**Android (Quick Share)**
- **Android → Mac:** in Quick Share on the phone, pick your Mac. The notch and a notification show the sender, the files and a PIN; nothing is saved until you click **Accept** (in either one). Progress shows around the notch.
- **Mac → Android:** drop files on **Android** next to the stash. Scan the QR code in the notch with the phone's camera (Samsung: Quick Share → Receive → scan QR code), and the transfer starts.
- Both devices must be on the **same Wi-Fi**. Some public or guest networks block devices from seeing each other.
- **Why a QR code?** macOS doesn't let apps send the Bluetooth signal that makes Android phones discoverable, so the QR code takes its place.
- The first time, macOS asks to allow **Local Network** access and possibly incoming connections. Allow both.

Received files go to **Downloads** by default; pick another folder in Settings → Phone. AirDrop always saves to Downloads, so NotChi moves AirDrop arrivals into your folder.

Quick Share support is adapted from [NearDrop](https://github.com/grishka/NearDrop) by Grishka (public domain).

## Permissions

| Permission | Used for |
| --- | --- |
| Accessibility | Posting ⌘V into the frontmost app (auto-paste), and reading where menus and menu bar icons are so the stats wings never cover them. |
| Local Network | Quick Share with Android phones (only when Android is selected). |
| Downloads folder | Saving received files and noticing AirDrop arrivals (only when a phone is selected). |
| Notifications | Incoming share requests (PIN, Accept / Decline) and finished transfers. Optional. |
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

**Signing and Accessibility:** macOS ties the Accessibility grant to the app's signing identity.

- `build-app.sh` signs with your **Apple Development** certificate when you have one. A free Apple ID added in Xcode → Settings → Accounts is enough. That identity stays the same across builds, so you grant Accessibility once.
- Without that certificate, the build is ad-hoc signed and each build looks like a new app. You'd have to remove NotChi from the Accessibility list and add it again after every build.
- `SIGN_ID="<identity>"` picks a specific certificate, and `SIGN_ID=-` forces ad-hoc signing.

## Automation

Scripts, Raycast, or Shortcuts can drive NotChi with distributed notifications:

| Notification | Object |
| --- | --- |
| `com.notchi.app.open` | optional tab: `clipboard`, `ports`, `stats` |
| `com.notchi.app.close` | — |
| `com.notchi.app.settings` | optional pane: `general`, `clipboard`, `phone`, `ports`, `permissions`, `about` |
| `com.notchi.app.send` | `iphone:/path/to/file` or `android:/path/to/file` (needs that phone enabled in Settings) |

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

Copyright (c) 2026 Muhammad Muzammil Loya ([muzammilloya.dev](https://muzammilloya.dev)).

NotChi is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may use, modify and share it for **noncommercial** purposes (personal use, study, research, hobby projects, and use by charities, schools and similar organizations).

Any commercial use needs a separate commercial license — selling it or a fork, bundling it in a paid product or service, or otherwise making money from it. To arrange one, get in touch via [muzammilloya.dev](https://muzammilloya.dev).

NotChi includes third-party components under their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
