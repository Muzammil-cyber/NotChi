// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Expanded-notch card for the current transfer or toast.
struct TransferCard: View {
    let coordinator: TransferCoordinator

    var body: some View {
        if let activity = coordinator.current {
            card(for: activity)
        } else if let toast = coordinator.toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(toast).font(.system(size: 12)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func card(for activity: TransferActivity) -> some View {
        HStack(alignment: .center, spacing: 12) {
            icon(for: activity)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: activity)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle(for: activity)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                if case .transferring(let done, let total, _) = activity.phase, total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(maxWidth: 260)
                }
                if case .waitingForPhone(_, let devices) = activity.phase, !devices.isEmpty {
                    HStack(spacing: 6) {
                        Text("Or send to:").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        ForEach(devices) { device in
                            Button(device.name) { coordinator.send(activity.id, to: device) }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            actions(for: activity)
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func icon(for activity: TransferActivity) -> some View {
        switch activity.phase {
        case .waitingForPhone(let qr, _):
            QRCodeView(url: qr).frame(width: 108, height: 108)
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.green).frame(width: 34)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(.orange).frame(width: 34)
        default:
            Image(systemName: activity.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 26)).foregroundStyle(.white.opacity(0.85)).frame(width: 34)
        }
    }

    private func title(for activity: TransferActivity) -> String {
        switch activity.phase {
        case .incomingRequest: "\(activity.deviceName) wants to send \(activity.summary)"
        case .waitingForPhone: "Send \(activity.summary) to Android"
        case .connecting: activity.direction == .incoming ? "Receiving from \(activity.deviceName)…" : "Connecting to \(activity.deviceName)…"
        case .transferring: (activity.direction == .incoming ? "Receiving " : "Sending ") + activity.summary
        case .finished: activity.direction == .incoming ? "Saved \(activity.summary) to Downloads" : "Sent \(activity.summary)"
        case .failed: "Transfer failed"
        }
    }

    private func subtitle(for activity: TransferActivity) -> String {
        let size = ByteCountFormatter.string(fromByteCount: activity.totalSize, countStyle: .file)
        switch activity.phase {
        case .incomingRequest(let pin): return "\(activity.files.count) file\(activity.files.count == 1 ? "" : "s") · \(size) · PIN \(pin)"
        case .waitingForPhone: return "Scan with your Android camera, or in Quick Share tap Receive → scan QR code. Same Wi-Fi needed."
        case .connecting(let pin): return pin.map { "Check the PIN matches: \($0)" } ?? size
        case .transferring(let done, let total, let rate):
            let doneText = ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            guard rate > 0 else { return "\(doneText) of \(totalText)" }
            let speed = ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file)
            let remaining = Double(total - done) / rate
            return "\(doneText) of \(totalText) · \(speed)/s · \(Self.eta(remaining))"
        case .finished: return activity.direction == .incoming ? "Also added to your stash" : activity.deviceName
        case .failed(let reason): return reason
        }
    }

    @ViewBuilder private func actions(for activity: TransferActivity) -> some View {
        switch activity.phase {
        case .incomingRequest:
            HStack(spacing: 6) {
                Button("Decline") { coordinator.decline(activity.id) }.buttonStyle(PillButtonStyle())
                Button("Accept") { coordinator.accept(activity.id) }.buttonStyle(PillButtonStyle(prominent: true))
            }
        case .waitingForPhone, .connecting, .transferring:
            Button("Cancel") { coordinator.cancel(activity.id) }.buttonStyle(PillButtonStyle())
        case .finished(let saved):
            if let first = saved.first {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting(saved.isEmpty ? [first] : saved) }
                    .buttonStyle(PillButtonStyle())
            }
        case .failed:
            Button("Dismiss") { coordinator.dismiss(activity.id) }.buttonStyle(PillButtonStyle())
        }
    }

    private static func eta(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "" }
        if seconds < 60 { return "\(max(1, Int(seconds)))s left" }
        return "\(Int(seconds / 60))m left"
    }
}

/// Collapsed-notch indicator shown in place of the stats wings while a transfer runs.
struct TransferWing: View {
    enum Side { case left, right }
    let coordinator: TransferCoordinator
    let side: Side

    var body: some View {
        Group {
            if let activity = coordinator.current {
                switch side {
                case .left:
                    Image(systemName: symbol(for: activity))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color(for: activity))
                case .right:
                    Text(progressText(for: activity))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
            } else if coordinator.toast != nil {
                Image(systemName: side == .left ? "arrow.down.circle.fill" : "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func symbol(for activity: TransferActivity) -> String {
        switch activity.phase {
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .incomingRequest: "iphone.and.arrow.forward"
        default: activity.direction == .incoming ? "arrow.down.circle" : "arrow.up.circle"
        }
    }

    private func color(for activity: TransferActivity) -> Color {
        switch activity.phase {
        case .finished: .green
        case .failed: .orange
        default: .white
        }
    }

    private func progressText(for activity: TransferActivity) -> String {
        switch activity.phase {
        case .transferring(let done, let total, _) where total > 0: "\(Int(Double(done) / Double(total) * 100))%"
        case .incomingRequest: "Accept?"
        case .waitingForPhone: "Scan"
        case .finished: "Done"
        case .failed: "Failed"
        default: "…"
        }
    }
}

/// Renders a URL as a crisp QR code (white modules on black, matching the notch).
struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image = Self.render(url.absoluteString) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .padding(5)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func render(_ text: String) -> NSImage? {
        if let hit = cache.object(forKey: text as NSString) { return hit }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache.setObject(image, forKey: text as NSString)
        return image
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(prominent ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
