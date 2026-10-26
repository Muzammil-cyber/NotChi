// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct NowPlayingSettingsPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.nowPlayingEnabled) {
                    Text("Show Now Playing")
                    Text("The current track from Music, Spotify, browsers and other players, with playback controls, in the notch's Overview tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.nowPlayingInWings) {
                    Text("Show artwork beside the notch while playing")
                    Text("Replaces the system stats until playback pauses.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .disabled(!settings.nowPlayingEnabled)
            }
            Section("How it works") {
                Text("Since macOS 15.4 apps can't read what's playing directly, so NotChi runs a small helper (mediaremote-adapter) through the system's Perl. It only reports changes, and it doesn't run while this is off.")
                    .font(.callout).foregroundStyle(.secondary)
                if !MediaRemoteBridge.isAvailable {
                    Label("The helper is missing from this build.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .settingsPaneStyle()
    }
}
