import CoreGraphics
import Testing
@testable import FromScratchCore

struct WindowGeometryTests {
    // Primary 1920x1080 at AppKit origin; visibleFrame excludes a 25 pt menu bar.
    static let primary = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    // Display to the left of the primary (AppKit x -1920), and one above it (AppKit y 1080).
    static let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
    static let above = CGRect(x: 0, y: 1080, width: 1920, height: 1055)
    static let all = [primary, left, above]
    static let primaryHeight: CGFloat = 1080

    @Test func roundTrip() {
        let rects = [
            CGRect(x: 0, y: 0, width: 550, height: 450),
            CGRect(x: -1500, y: 200, width: 800, height: 600),
            CGRect(x: 300, y: -900, width: 640, height: 480),
        ]
        for r in rects {
            let appKit = WindowGeometry.appKitFrame(electron: r, primaryHeight: Self.primaryHeight)
            #expect(WindowGeometry.electronBounds(appKit: appKit, primaryHeight: Self.primaryHeight) == r)
        }
    }

    @Test func primaryTopLeft() {
        let f = WindowGeometry.appKitFrame(
            electron: CGRect(x: 0, y: 0, width: 550, height: 450), primaryHeight: 1080)
        #expect(f == CGRect(x: 0, y: 630, width: 550, height: 450))
    }

    @Test func negativeOriginSecondaryDisplay() {
        // Left display: Electron x -1920 maps to AppKit x -1920 unchanged.
        let leftSaved = CGRect(x: -1800, y: 100, width: 800, height: 600)
        let l = WindowGeometry.restoredFrame(
            saved: leftSaved, visibleFrames: Self.all, primaryHeight: Self.primaryHeight)
        #expect(l == CGRect(x: -1800, y: 380, width: 800, height: 600))

        // Display above: Electron y -1080 is the top of that display; AppKit y = 1080 - (-1000 + 500) = 1580.
        let aboveSaved = CGRect(x: 100, y: -1000, width: 700, height: 500)
        let a = WindowGeometry.restoredFrame(
            saved: aboveSaved, visibleFrames: Self.all, primaryHeight: Self.primaryHeight)
        #expect(a == CGRect(x: 100, y: 1580, width: 700, height: 500))
    }

    @Test func disconnectedDisplayReturnsNil() {
        // Saved on a display to the right that is no longer connected.
        let saved = CGRect(x: 2500, y: 100, width: 800, height: 600)
        #expect(WindowGeometry.restoredFrame(
            saved: saved, visibleFrames: Self.all, primaryHeight: Self.primaryHeight) == nil)
    }

    @Test func nothingSavedReturnsNil() {
        #expect(WindowGeometry.restoredFrame(
            saved: nil, visibleFrames: Self.all, primaryHeight: Self.primaryHeight) == nil)
    }

    @Test func invalidSizeOrNonFiniteReturnsNil() {
        let bad = [
            CGRect(x: 0, y: 0, width: 0, height: 450),
            CGRect(x: 0, y: 0, width: 550, height: -1),
            CGRect(x: CGFloat.nan, y: 0, width: 550, height: 450),
            CGRect(x: 0, y: CGFloat.infinity, width: 550, height: 450),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 450),
        ]
        for r in bad {
            #expect(WindowGeometry.restoredFrame(
                saved: r, visibleFrames: Self.all, primaryHeight: Self.primaryHeight) == nil)
        }
    }

    @Test func edgeTouchingIsNotAnIntersection() {
        // Strict inequality as in v2: a window ending exactly at the left display's left edge
        // overlaps nothing when only the primary is connected.
        let saved = CGRect(x: -550, y: 100, width: 550, height: 450)
        #expect(WindowGeometry.restoredFrame(
            saved: saved, visibleFrames: [Self.primary], primaryHeight: Self.primaryHeight) == nil)
        let overlapping = CGRect(x: -549, y: 100, width: 550, height: 450)
        #expect(WindowGeometry.restoredFrame(
            saved: overlapping, visibleFrames: [Self.primary], primaryHeight: Self.primaryHeight) != nil)
    }

    // Electron's getBounds() returns integers; storing AppKit's fractional frames would hand a
    // rolled-back v2 values it never wrote.
    @Test func electronBoundsAreWholeNumbers() {
        let appKit = CGRect(x: 10.4, y: 630.6, width: 550.5, height: 449.49)
        let b = WindowGeometry.electronBounds(appKit: appKit, primaryHeight: Self.primaryHeight)
        #expect(b == CGRect(x: 10, y: 0, width: 551, height: 449))
        for value in [b.origin.x, b.origin.y, b.size.width, b.size.height] {
            #expect(value == value.rounded())
        }
    }
}
