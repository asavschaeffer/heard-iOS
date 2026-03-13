import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct AppWarmupTests {
    @Test
    func progressTracksUniqueCompletedSteps() {
        let warmup = AppWarmup()

        #expect(warmup.completedStepCount == 0)
        #expect(warmup.progress == 0)
        #expect(warmup.isFinished == false)

        warmup.recordCompletion(of: .audioSession)
        #expect(warmup.completedStepCount == 1)
        #expect(warmup.progress == (1.0 / Double(AppWarmup.Step.allCases.count)))
        #expect(warmup.isFinished == false)

        warmup.recordCompletion(of: .audioSession)
        #expect(warmup.completedStepCount == 1)

        for step in AppWarmup.Step.allCases where step != .audioSession {
            warmup.recordCompletion(of: step)
        }

        #expect(warmup.completedStepCount == AppWarmup.Step.allCases.count)
        #expect(warmup.progress == 1.0)
        #expect(warmup.isFinished)
    }
}
