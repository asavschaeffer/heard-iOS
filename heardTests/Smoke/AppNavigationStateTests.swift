import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct AppNavigationStateTests {
    @Test
    func requestCallSwitchesToChatTab() {
        let sut = AppNavigationState()
        sut.selectedTab = .inventory

        sut.requestCall()

        #expect(sut.selectedTab == .chat)
    }

    @Test
    func requestCallSetsPendingFlag() {
        let sut = AppNavigationState()

        sut.requestCall()

        #expect(sut.pendingCallRequest)
    }

    @Test
    func pendingCallRequestDefaultsToFalse() {
        let sut = AppNavigationState()

        #expect(sut.pendingCallRequest == false)
    }
}
