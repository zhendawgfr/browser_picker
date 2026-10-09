import CoreGraphics

public enum PanelPlacement {
    public static let offset: CGFloat = 8

    /// Frame (AppKit coordinates, origin bottom-left) with the panel's top-left near the cursor,
    /// flipped left/up when it would overflow, then clamped to the visible frame.
    public static func frame(size: CGSize, cursor: CGPoint, screenVisibleFrame v: CGRect) -> CGRect {
        var x = cursor.x + offset
        var y = cursor.y - offset - size.height
        if x + size.width > v.maxX { x = cursor.x - offset - size.width }
        if y < v.minY { y = cursor.y + offset }
        x = clamp(x, lower: v.minX, upper: v.maxX - size.width)
        y = clamp(y, lower: v.minY, upper: v.maxY - size.height)
        // Larger than the screen: pin to the top-left so the header stays visible.
        if size.width > v.width { x = v.minX }
        if size.height > v.height { y = v.maxY - size.height }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(upper, lower))
    }
}
