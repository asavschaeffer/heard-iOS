import SwiftUI

struct LaunchLoadingView: View {
    @EnvironmentObject var warmup: AppWarmup

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image("app-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)

                ProgressView(value: warmup.progress)
                    .tint(.orange)
                    .frame(width: 200)
            }
            .offset(y: -20)
        }
    }
}
