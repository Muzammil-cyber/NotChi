// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct DevSettingsPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.devEnabled) {
                    Text("Show Dev tab")
                    Text("Developer utilities: Port Sniper (more coming). Off hides the tab; nothing runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }
            Section("Port Sniper") {
                Toggle(isOn: $settings.portsShowAll) {
                    Text("Show all listening ports")
                    Text("By default only dev servers and Docker/OrbStack containers are listed; system services and desktop apps are hidden.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }
            Section("Docker") {
                Text("Container ports are detected through the Docker engine socket (OrbStack, Docker Desktop, Colima, Rancher Desktop). Stopping a container row runs `docker stop`; the engine itself is never killed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .settingsPaneStyle()
    }
}
