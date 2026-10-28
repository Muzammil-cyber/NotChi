# NotChi architecture

This is a map for finding your way around the code, for people and for AI tools. The README covers what the app does and how to build it.

## The one idea

Everything inside the notch is a **module**: a type that conforms to `NotchModule` (`Sources/NotChi/Modules/Module.swift`). The shell (`Notch/`, `UI/`) never knows what a module does. It only decides **where** and **when** the module's views appear.

The module protocol is the only seam between the shell and the features. Its interface:

| Member | Meaning |
| --- | --- |
| `id`, `title`, `systemImage` | Identity. The `id` is also the automation id (`com.notchi.app.open <id>`). |
| `makeExpandedView()` | What shows when the tab is open. |
| `makeLeftWing()`, `makeRightWing()` | Compact views beside the collapsed notch. |
| `wingClaim` | Non-nil while the module wants the wings instead of the stats. `WingClaim.urgent` gets priority and room; `width` hugs the notch. |
| `isEnabled` | False when the user turned it off in Settings. It's then hidden and does no work. |
| `children`, `reveal(childID:)` | For container tabs (Overview, Dev): the modules shown inside them. |
| `start()`, `stop()`, `setVisible(_:)` | Lifecycle. Do on-screen work only while visible (see Resource rules). |

## Where things live

The folder tree mirrors what you see in the notch:

```
Sources/NotChi/
  App/            entry point, AppDelegate (creates the modules: start here), Settings (all prefs)
  Notch/          the shell
    NotchController   hover, hotkey, expand/collapse, tab selection, wing sizing
    ModuleHost        the module list: tabs, children, background; wing priority; id routing
    MenuBarProbe      measures free menu-bar space (Accessibility) so wings never cover menus
    NotchPanel / NotchGeometry / NotchState / HotKey
  UI/             shell views: NotchRootView (layout), ModuleTabBar (glass pill), NotchShape,
                  MenuBarIcon, Settings/ (window + one file per pane in Settings/Panes/)
  Modules/
    Module.swift      the NotchModule protocol and WingClaim
    Overview/         tab 1: OverviewModule shows its children side by side
      NowPlaying/       pane: track, artwork, controls (helper: MediaRemoteBridge)
      Calendar/         pane: date tile, agenda, reminders, meeting links
    Clipboard/        tab 2: clipboard history and the Stash strip
    Dev/              tab 3 (optional): DevModule holds developer tools
      PortSniper/       tool: listening ports, health, kill, Docker
      TextTools/        tool: JSON, JWT, Base64, URL, Time, Hash, UUID, Color; the detector picks one from the clipboard
    SystemStats/      background module: CPU/RAM/net in the wings and the header
    Transfer/         AirDrop + Quick Share; not a module, a coordinator the shell shows
  Support/        AppPaths, Permissions, SQLite wrapper
Vendor/           mediaremote-adapter (BSD-3), built by scripts/build-mediaremote-adapter.sh
scripts/          build-app.sh, build-mediaremote-adapter.sh, check-headers.sh
```

**Files inside a module folder follow one pattern:**

| File | Holds |
| --- | --- |
| `<Name>Module.swift` | The `NotchModule` conformance: small, it wires the model to the views. |
| `<Name>Model.swift` | Observable state and the logic. |
| `<Name>Views.swift` | The expanded view. |
| `<Name>Wings.swift` | The collapsed wing views. |
| `<Name>Items.swift` | Value types shown by the views (when there are several). |

## How a request flows

- **Launch:** `main.swift` → `AppDelegate.applicationDidFinishLaunching` builds the modules and hands them to `ModuleHost`. `NotchController` creates the panel with `NotchRootView`.
- **Hover or ⌥⌘N:** `NotchController.expand` → `ModuleHost.visibilityChanged` → the selected tab's `setVisible(true)`. A container forwards that to its children.
- **Automation** (`DistributedNotificationCenter`, observed in `AppDelegate.observeAutomation`):
  - `open <id>` → `NotchController.select` → `ModuleHost.tabID(for:)`.
  - A child's id opens its container tab and calls `reveal(childID:)`.
- **Collapsed wings:** `NotchRootView` asks `ModuleHost.wingClaimant`. The priority is:
  1. A transfer in progress
  2. An urgent claim
  3. The first claim in module order
  4. The stats wings

  `NotchController.updateWings` sizes them from `MenuBarProbe`.

## Common changes

| To… | Edit |
| --- | --- |
| Add a top-level tab | New folder in `Modules/`, a `NotchModule`, add it to `tabs:` in `AppDelegate`. |
| Add an Overview pane or a Dev tool | Add the module to `OverviewModule(panes:)` / `DevModule(tools:)` in `AppDelegate`. Routing, lifecycle and wings come for free. |
| Show something beside the collapsed notch | Implement `makeLeftWing`/`makeRightWing` and return a `wingClaim` while it should show. |
| Add a preference | `App/Settings.swift` (property + default + load), then the pane in `UI/Settings/Panes/`. |
| Add a Settings pane | A case in `SettingsTab` (`UI/Settings/SettingsView.swift`), plus a file in `Panes/`. |
| Add an automation command | `AppDelegate.observeAutomation`, then document it in README and `llms.txt`. |
| Need a new permission | Usage string in `Resources/Info.plist`. Under the hardened runtime, also an entitlement in `Resources/NotChi.entitlements`. Then add a row in `PermissionsSettingsPane`. |

## Resource rules

NotChi must stay light: about 0.1–0.5% CPU collapsed and about 1% open.
- Prefer notifications and observers to polling. When you must poll, do it only while visible, and adaptively.
- Animate inside `NotchShape` on a fixed canvas; don't animate `.frame`.
- Never scale text.
- Use Core Animation for loops that run while collapsed (see `EqualizerView`).
- Measure with `top -pid` and `sample` before and after a change.

## Conventions

- Every first-party Swift file starts with the license header. `scripts/check-headers.sh` enforces this in CI.
- Comments explain *why*, not what. Views say what they look like in one line.
- Nothing commits or tags releases except the maintainer. Releases are `v*` tags.
