// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Left wing: CPU % with a usage bar, RAM % with a pressure dot.
struct StatsLeftWing: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("CPU")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                Text(StatsFormat.percent(model.cpu))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressBar(fraction: model.cpu, tint: .cyan)
                .frame(height: 2)
            HStack(spacing: 4) {
                Circle().fill(model.pressure.color).frame(width: 5, height: 5)
                Text("RAM")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                Text(StatsFormat.percent(model.memFraction))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

/// Right wing: download and upload rates stacked.
struct StatsRightWing: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("↓", model.downRate, .green)
            row("↑", model.upRate, .orange)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }

    private func row(_ arrow: String, _ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(arrow)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(StatsFormat.rate(rate))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
    }
}
