import CoreGraphics
import Testing
@testable import SaneHostsFeature

@Suite("Coach Mark Overlay Coordinates")
@MainActor
struct CoachMarkOverlayCoordinateTests {
    @Test("Converts global highlight frame into window-local coordinates")
    func convertsGlobalToLocalFrame() {
        let window = CGRect(x: 500, y: 120, width: 900, height: 650)
        let globalHighlight = CGRect(x: 620, y: 260, width: 180, height: 44)

        let local = CoachMarkOverlay.localFrame(globalHighlight, in: window)

        #expect(local.origin.x == 120)
        #expect(local.origin.y == 140)
        #expect(local.width == 180)
        #expect(local.height == 44)
    }

    @Test("Zero highlight frame stays zero")
    func zeroFrameStaysZero() {
        let window = CGRect(x: 300, y: 80, width: 1024, height: 768)
        let local = CoachMarkOverlay.localFrame(.zero, in: window)
        #expect(local == .zero)
    }
}
