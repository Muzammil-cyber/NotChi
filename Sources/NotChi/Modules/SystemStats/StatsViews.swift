import SwiftUI

// MARK: - Formatting

enum StatsFormat {
    /// Compact byte rate for the wings: "0B", "340K", "1.2M".
    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        switch v {
        case ..<1000: return "\(Int(v))B"
        case ..<(1000 * 1000): return "\(Int((v / 1000).rounded()))K"
        case ..<(1000 * 1000 * 1000): return shortUnit(v / 1e6, "M")
        default: return shortUnit(v / 1e9, "G")
        }
    }

    private static func shortUnit(_ x: Double, _ unit: String) -> String {
        x >= 10 ? "\(Int(x.rounded()))\(unit)" : String(format: "%.1f%@", x, unit)
    }

    /// Longer rate for cards: "1.24 MB/s".
    static func longRate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1000 { return "\(Int(v)) B/s" }
        if v < 1e6 { return String(format: "%.0f KB/s", v / 1e3) }
        if v < 1e9 { return String(format: "%.2f MB/s", v / 1e6) }
        return String(format: "%.2f GB/s", v / 1e9)
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 10 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}

// MARK: - Wings

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

// MARK: - Expanded view

/// Three side-by-side cards: CPU, Memory, Network.
struct StatsExpandedView: View {
    let model: StatsModel

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "CPU",
                value: StatsFormat.percent(model.cpu),
                subtitle: "Total usage",
                series: [.init(values: model.cpuHistory, color: .cyan)],
                fixedMax: 1
            )
            StatCard(
                title: "Memory",
                value: StatsFormat.percent(model.memFraction),
                subtitle: "\(StatsFormat.gigabytes(model.memUsed)) / \(StatsFormat.gigabytes(model.memTotal)) GB · \(model.pressure.label) pressure",
                accent: model.pressure.color,
                series: [.init(values: model.memHistory, color: model.pressure.color)],
                fixedMax: 1
            )
            StatCard(
                title: "Network",
                value: nil,
                subtitle: nil,
                series: [
                    .init(values: model.downHistory, color: .green),
                    .init(values: model.upHistory, color: .orange),
                ],
                fixedMax: nil
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    rateLine("arrow.down", model.downRate, .green)
                    rateLine("arrow.up", model.upRate, .orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rateLine(_ symbol: String, _ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text(StatsFormat.longRate(rate))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct StatSeries {
    var values: [Double]
    var color: Color
}

private struct StatCard<Header: View>: View {
    let title: String
    let value: String?
    let subtitle: String?
    var accent: Color? = nil
    let series: [StatSeries]
    let fixedMax: Double?
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let accent { Circle().fill(accent).frame(width: 6, height: 6) }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let value {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            header()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Sparkline(series: series, fixedMax: fixedMax)
                .frame(height: 48)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
    }
}

extension StatCard where Header == EmptyView {
    fileprivate init(title: String, value: String?, subtitle: String?, accent: Color? = nil,
                     series: [StatSeries], fixedMax: Double?) {
        self.init(title: title, value: value, subtitle: subtitle, accent: accent,
                  series: series, fixedMax: fixedMax) { EmptyView() }
    }
}

// MARK: - Sparkline

/// Smooth line chart(s) over a fixed 60-sample window, with a gradient fill under each line.
private struct Sparkline: View {
    let series: [StatSeries]
    let fixedMax: Double?

    private var maxValue: Double {
        if let fixedMax { return fixedMax }
        let peak = series.flatMap(\.values).max() ?? 0
        return max(peak * 1.15, 1024) // floor avoids amplifying idle noise
    }

    var body: some View {
        ZStack {
            ForEach(series.indices, id: \.self) { i in
                let s = series[i]
                SparkShape(values: s.values, maxValue: maxValue, closed: true)
                    .fill(LinearGradient(colors: [s.color.opacity(0.35), s.color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                SparkShape(values: s.values, maxValue: maxValue, closed: false)
                    .stroke(s.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct SparkShape: Shape {
    let values: [Double]
    let maxValue: Double
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, maxValue > 0 else { return path }
        // Spread the samples across the full width until the history fills up, then scroll.
        let step = rect.width / CGFloat(values.count - 1)
        let startX: CGFloat = 0
        let points = values.enumerated().map { i, v in
            CGPoint(x: startX + step * CGFloat(i),
                    y: rect.height - rect.height * CGFloat(min(1, max(0, v / maxValue))))
        }
        path.move(to: points[0])
        for i in 1..<points.count {
            let p0 = points[i - 1], p1 = points[i]
            let midX = (p0.x + p1.x) / 2
            path.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
        }
        if closed {
            path.addLine(to: CGPoint(x: points.last!.x, y: rect.height))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}
