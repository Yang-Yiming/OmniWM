import Foundation
import Testing

@testable import OmniWM

@Suite struct LayoutRefreshControllerTests {
    @Test @MainActor func hiddenEdgeRevealUsesEpsilonForNonZoomApps() {
        #expect(LayoutRefreshController.hiddenEdgeReveal(isZoomApp: false) == 0.001)
    }

    @Test @MainActor func hiddenEdgeRevealUsesZeroForZoom() {
        #expect(LayoutRefreshController.hiddenEdgeReveal(isZoomApp: true) == 0)
    }
}
