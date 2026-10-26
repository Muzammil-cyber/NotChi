// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: AppLogo.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("NotChi logo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotChi").font(.title2.weight(.semibold))
                        Text(AppVersion.displayString).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("License", value: "PolyForm Noncommercial 1.0.0")
                LabeledContent("Copyright", value: "© 2026 Muhammad Muzammil Loya")
                LabeledContent("Source") {
                    Link("github.com/Muzammil-cyber/NotChi", destination: URL(string: "https://github.com/Muzammil-cyber/NotChi")!)
                }
                LabeledContent("Commercial licensing") {
                    Link("muzammilloya.dev", destination: URL(string: "https://muzammilloya.dev")!)
                }
                LabeledContent("Third-party components") {
                    Text("NearDrop · Google Nearby · SwiftProtobuf · mediaremote-adapter").foregroundStyle(.secondary)
                }
                LabeledContent("Data") {
                    Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.support) }
                }
            }
        }
        .settingsPaneStyle()
    }
}
