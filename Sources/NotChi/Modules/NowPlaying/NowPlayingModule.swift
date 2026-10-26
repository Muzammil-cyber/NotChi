// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Now Playing: the current track with artwork and playback controls, as a section of
/// the Overview tab, plus artwork and an equalizer in the wings while something plays.
@MainActor
final class NowPlayingModule: NotchModule {
    let id = "nowplaying"
    let title = "Now Playing"
    let systemImage = "music.note"

    let model = NowPlayingModel()
    private let settings = Settings.shared

    var isEnabled: Bool { settings.nowPlayingEnabled }

    var claimsWings: Bool {
        settings.nowPlayingEnabled && settings.nowPlayingInWings && model.isPlaying && model.hasMedia
    }

    /// Just the artwork and the equalizer.
    var claimedWingWidth: CGFloat? { 36 }

    func makeExpandedView() -> AnyView { AnyView(NowPlayingExpandedView(model: model)) }
    func makeLeftWing() -> AnyView? { AnyView(NowPlayingLeftWing(model: model)) }
    func makeRightWing() -> AnyView? { AnyView(NowPlayingRightWing(model: model)) }

    func start() { observeEnabled() }
    func stop() { model.setRunning(false) }

    /// The helper process runs only while the section is turned on.
    private func observeEnabled() {
        withObservationTracking {
            model.setRunning(settings.nowPlayingEnabled)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeEnabled() }
        }
    }
}
