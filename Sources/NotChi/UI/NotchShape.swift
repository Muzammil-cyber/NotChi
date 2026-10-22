import SwiftUI

/// The notch silhouette: concave flares where it meets the top edge, rounded bottom corners.
///
/// The visible size and horizontal offset are part of the shape (and animatable) rather
/// than coming from a `.frame`: the shape sits on a fixed full-panel canvas, so growing or
/// shrinking it only redraws one path instead of re-laying out the whole panel each frame.
struct NotchShape: Shape {
    var size: CGSize
    var offsetX: CGFloat = 0
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(AnimatablePair(size.width, size.height), AnimatablePair(offsetX, AnimatablePair(topRadius, bottomRadius))) }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            offsetX = newValue.second.first
            topRadius = newValue.second.second.first
            bottomRadius = newValue.second.second.second
        }
    }

    func path(in canvas: CGRect) -> Path {
        let rect = CGRect(x: canvas.midX - size.width / 2 + offsetX, y: canvas.minY, width: size.width, height: size.height)
        var path = Path()
        let t = min(topRadius, rect.width / 4), b = min(bottomRadius, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                          control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                          control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                          control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
