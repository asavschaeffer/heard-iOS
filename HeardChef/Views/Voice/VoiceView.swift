import SwiftUI
import SwiftData

struct VoiceView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = VoiceViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.orange.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Status indicator
                    statusView

                    // Waveform animation
                    waveformView
                        .frame(height: 60)
                        .padding(.horizontal, 40)

                    // Transcript
                    transcriptView

                    Spacer()

                    // Main action button
                    mainButton

                    // Mode toggle
                    modeToggle
                        .padding(.bottom, 20)
                }
                .padding()
            }
            .navigationTitle("Heard, Chef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                VoiceSettingsView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
        }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return viewModel.isListening ? .green : .blue
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting..."
        case .connected:
            if viewModel.isListening {
                return "Listening..."
            } else if viewModel.isSpeaking {
                return "Speaking..."
            } else {
                return "Ready"
            }
        case .error(let message):
            return message
        }
    }

    // MARK: - Waveform View

    @ViewBuilder
    private var waveformView: some View {
        if viewModel.isListening || viewModel.isSpeaking {
            AudioWaveformView(
                audioLevel: viewModel.audioLevel,
                isActive: viewModel.isListening || viewModel.isSpeaking
            )
        } else {
            // Placeholder bars when inactive
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 4, height: 8)
                }
            }
        }
    }

    // MARK: - Transcript View

    @ViewBuilder
    private var transcriptView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.transcriptEntries) { entry in
                    TranscriptBubble(entry: entry)
                }

                if let currentTranscript = viewModel.currentTranscript, !currentTranscript.isEmpty {
                    TranscriptBubble(
                        entry: TranscriptEntry(
                            text: currentTranscript,
                            isUser: true,
                            timestamp: Date()
                        )
                    )
                    .opacity(0.7)
                }
            }
            .padding()
        }
        .frame(maxHeight: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Main Button

    @ViewBuilder
    private var mainButton: some View {
        Button {
            handleMainButtonTap()
        } label: {
            ZStack {
                Circle()
                    .fill(mainButtonColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: mainButtonColor.opacity(0.5), radius: 10, y: 5)

                Image(systemName: mainButtonIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(viewModel.isListening ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isListening)
    }

    private var mainButtonColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return viewModel.isListening ? .red : .orange
        case .connecting:
            return .yellow
        default:
            return .orange
        }
    }

    private var mainButtonIcon: String {
        switch viewModel.connectionState {
        case .disconnected, .error:
            return "waveform"
        case .connecting:
            return "ellipsis"
        case .connected:
            return viewModel.isListening ? "stop.fill" : "mic.fill"
        }
    }

    private func handleMainButtonTap() {
        switch viewModel.connectionState {
        case .disconnected, .error:
            viewModel.connect()
        case .connecting:
            break
        case .connected:
            if viewModel.isListening {
                viewModel.stopListening()
            } else {
                viewModel.startListening()
            }
        }
    }

    // MARK: - Mode Toggle

    @ViewBuilder
    private var modeToggle: some View {
        HStack {
            Text("Always Listening")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("", isOn: $viewModel.alwaysListening)
                .labelsHidden()
                .tint(.orange)
        }
    }
}

// MARK: - Transcript Entry

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

struct TranscriptBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack {
            if entry.isUser { Spacer(minLength: 40) }

            Text(entry.text)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    entry.isUser ? Color.orange : Color.gray.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(entry.isUser ? .white : .primary)

            if !entry.isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var phases: [Double] = Array(repeating: 0, count: 20)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 4, height: barHeight(for: index, date: timeline.date))
                }
            }
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard isActive else { return 8 }

        let time = date.timeIntervalSinceReferenceDate
        let frequency = 2.0 + Double(index) * 0.3
        let wave = sin(time * frequency + Double(index) * 0.5)
        let normalizedWave = (wave + 1) / 2 // 0 to 1

        let levelMultiplier = CGFloat(max(0.2, audioLevel))
        let height = 8 + normalizedWave * 40 * levelMultiplier

        return max(8, min(60, height))
    }
}

// MARK: - Settings View

struct VoiceSettingsView: View {
    @ObservedObject var viewModel: VoiceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.connectionState.description)
                            .foregroundStyle(.secondary)
                    }

                    if case .connected = viewModel.connectionState {
                        Button("Disconnect", role: .destructive) {
                            viewModel.disconnect()
                        }
                    } else {
                        Button("Connect") {
                            viewModel.connect()
                        }
                    }
                }

                Section("Voice") {
                    Toggle("Always Listening", isOn: $viewModel.alwaysListening)
                }

                Section("About") {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("Gemini 2.0 Flash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Connection State Extension

extension VoiceViewModel.ConnectionState: CustomStringConvertible {
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

#Preview {
    VoiceView()
        .modelContainer(for: [Ingredient.self, Recipe.self], inMemory: true)
}
