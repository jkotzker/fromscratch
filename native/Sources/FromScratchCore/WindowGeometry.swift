import CoreGraphics

// Window frames saved by v2 are Electron screen coordinates: origin at the top-left of the primary
// display, y growing downward, secondary displays possibly at negative x or y. AppKit puts the
// origin at the bottom-left of the primary display with y growing upward. Only y differs.
public enum WindowGeometry {
    // Flipping is its own inverse, so both directions share one formula.
    private static func flipY(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - (r.origin.y + r.size.height),
               width: r.size.width, height: r.size.height)
    }

    public static func appKitFrame(electron: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipY(electron, primaryHeight: primaryHeight)
    }

    /// Rounded to whole points: Electron's getBounds() returns integers, so a rolled-back v2 reads
    /// back only values it could have written itself.
    public static func electronBounds(appKit: CGRect, primaryHeight: CGFloat) -> CGRect {
        let r = flipY(appKit, primaryHeight: primaryHeight)
        return CGRect(x: r.origin.x.rounded(), y: r.origin.y.rounded(),
                      width: r.size.width.rounded(), height: r.size.height.rounded())
    }

    // Mirrors isOnAConnectedDisplay in src/main/index.js: saved bounds can point at a display that is
    // no longer connected, which would open the window somewhere invisible. Returns the AppKit frame,
    // or nil when the caller should center a default-sized window instead. `visibleFrames` are in
    // AppKit coordinates (NSScreen.visibleFrame); v2 tested against Electron's workArea.
    public static func restoredFrame(saved: CGRect?, visibleFrames: [CGRect], primaryHeight: CGFloat) -> CGRect? {
        guard let saved else { return nil }
        let components = [saved.origin.x, saved.origin.y, saved.size.width, saved.size.height]
        guard components.allSatisfy(\.isFinite), saved.size.width > 0, saved.size.height > 0 else { return nil }
        let frame = appKitFrame(electron: saved, primaryHeight: primaryHeight)
        // Strict inequalities as in v2: touching edges do not count as overlap.
        let onDisplay = visibleFrames.contains { v in
            frame.minX < v.maxX && frame.maxX > v.minX && frame.minY < v.maxY && frame.maxY > v.minY
        }
        return onDisplay ? frame : nil
    }
}
