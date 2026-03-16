import CoreGraphics
import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
struct LaunchScreenLayoutTests {
    private let tolerance: CGFloat = 0.0001

    @Test
    func compactPhoneUsesOverlayMinimums() {
        let layout = LaunchScreenLayout(containerWidth: 393)

        #expect(layout.chefSize == 170)
        #expect(layout.bubbleWidth == 175)
        #expect(layout.progressWidth == 200)
        #expect(LaunchScreenLayout.chefOffsetX == 0)
        #expect(LaunchScreenLayout.chefOffsetY == 0)
        #expect(LaunchScreenLayout.bubbleOffsetX == 104)
        #expect(LaunchScreenLayout.bubbleOffsetY == -145)
        #expect(LaunchScreenLayout.progressHeight == 2)
    }

    @Test
    func regularWidthScalesUsingOverlayMultipliers() {
        let layout = LaunchScreenLayout(containerWidth: 700)

        #expect(abs(layout.chefSize - 182) < tolerance)
        #expect(abs(layout.bubbleWidth - 196) < tolerance)
        #expect(abs(layout.progressWidth - 238) < tolerance)
    }

    @Test
    func wideLayoutsClampAtOverlayMaximums() {
        let layout = LaunchScreenLayout(containerWidth: 1024)

        #expect(layout.chefSize == 210)
        #expect(layout.bubbleWidth == 215)
        #expect(layout.progressWidth == 240)
    }
}
