import AppKit
import SwiftUI

struct GenerateView: View {
    let suggestedEnvironmentPath: String
    let theme: AppTheme
    let onAdoptInstallation: (MiniMaxEnvironment) -> Void

    @StateObject private var controller = GenerationController()
    @AppStorage("installModel.environmentPath") private var environmentPath = ""
    @State private var environment: MiniMaxEnvironment?
    @State private var environmentMessage = "Load the environment file created by Install / Repair."
    @State private var runtimeIssue: String?
    @State private var settings = GenerationSettings()
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    environmentSection
                    promptSection
                    settingsSection
                    outputPathsSection
                    actionSection
                    logSection
                }
                .padding(24)
            }
        }
        .foregroundStyle(theme.primaryText)
        .onAppear {
            if environmentPath.isEmpty { environmentPath = suggestedEnvironmentPath }
            if environment == nil, FileManager.default.isReadableFile(atPath: environmentPath) {
                loadEnvironment()
            }
        }
        .onChange(of: suggestedEnvironmentPath) { _, newValue in
            if environment == nil { environmentPath = newValue }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generate a MiniMax H3 clip")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.heading)
            Text("Edit the prompt and settings here. The app launches the installed generator directly—no pasted shell command is evaluated.")
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var environmentSection: some View {
        ThemedSection(title: "1. Installed environment", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("minimax-h3-paths.env", text: $environmentPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseEnvironment)
                    Button("Load", action: loadEnvironment)
                        .buttonStyle(.borderedProminent)
                }
                HStack {
                    Button("Locate runtime or generate.py…", action: locateRuntime)
                        .disabled(environment == nil || controller.isRunning)
                    if let environment {
                        Text(environment.runtime)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if let runtimeIssue {
                    Label(runtimeIssue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(environmentMessage)
                    .font(.caption)
                    .foregroundStyle(environment == nil || runtimeIssue != nil ? theme.secondaryText : Color.green)
                Text("The last environment-file location is remembered and reloaded automatically when it is available.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var promptSection: some View {
        ThemedSection(title: "2. Prompt and output name", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Video prompt").font(.caption).foregroundStyle(theme.secondaryText)
                TextEditor(text: $settings.prompt)
                    .font(.body)
                    .frame(minHeight: 105)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Color(nsColor: .textColor))
                TextField("Output filename (without extension)", text: $settings.outputName)
                    .textFieldStyle(.roundedBorder)
                Text("One name is used for both the finished .mp4 and its performance-profile .json file.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var settingsSection: some View {
        ThemedSection(title: "3. Generation settings", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("Resolution").foregroundStyle(theme.secondaryText)
                        TextField("768x448", text: $settings.resolution).frame(width: 120)
                        Text("Duration").foregroundStyle(theme.secondaryText)
                        Stepper("\(settings.duration) sec", value: $settings.duration, in: 1...30).frame(width: 135)
                    }
                    GridRow {
                        Text("Steps").foregroundStyle(theme.secondaryText)
                        Stepper("\(settings.steps)", value: $settings.steps, in: 1...30).frame(width: 120)
                        Text("Seed").foregroundStyle(theme.secondaryText)
                        TextField("42", value: $settings.seed, format: .number).frame(width: 135)
                    }
                }

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Memory limit").foregroundStyle(theme.secondaryText)
                            Stepper("\(settings.memoryLimitGB) GB", value: $settings.memoryLimitGB, in: 8...max(8, environment?.memoryLimitGB ?? 256))
                            Spacer()
                            Text("Stream group").foregroundStyle(theme.secondaryText)
                            Stepper("\(settings.streamBlockGroupSize)", value: $settings.streamBlockGroupSize, in: 1...16)
                        }
                        HStack {
                            Text("Turbo LoRA scale").foregroundStyle(theme.secondaryText)
                            Slider(value: $settings.turboLoRAScale, in: 0...2, step: 0.1)
                            Text(settings.turboLoRAScale, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit().frame(width: 28)
                        }
                        Toggle("Low-memory mode", isOn: $settings.lowMemory)
                        Toggle("Stream transformer blocks", isOn: $settings.streamBlocks)
                        Toggle("Disable block cache", isOn: $settings.noBlockCache)
                        Toggle("Require a muxed MP4", isOn: $settings.requireMuxedMP4)
                        Text("Dense dequantization remains off, matching the tested installer profile.")
                            .font(.caption).foregroundStyle(theme.secondaryText)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var outputPathsSection: some View {
        ThemedSection(title: "4. Files to write", theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
                pathPreview(label: "Video", path: resolvedOutputPath)
                pathPreview(label: "Profile", path: resolvedProfilePath)
                if let message = settings.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if outputAlreadyExists {
                    Label("The MP4 or JSON already exists. Choose a new output name; the app will not overwrite it.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var actionSection: some View {
        ThemedSection(title: "5. Generate", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Generation can take many minutes. Closing the lid or disconnecting an external model drive will interrupt it.")
                    .foregroundStyle(theme.secondaryText)
                HStack {
                    Button("Generate clip", action: generate)
                        .buttonStyle(.borderedProminent)
                        .disabled(environment == nil || runtimeIssue != nil || settings.validationMessage != nil || outputAlreadyExists || controller.isRunning)
                    Button("Stop", role: .destructive) { controller.stop() }
                        .disabled(!controller.isRunning)
                    Button("Reveal MP4") { reveal(controller.lastOutputURL) }
                        .disabled(controller.lastOutputURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                    Button("Reveal JSON") { reveal(controller.lastProfileURL) }
                        .disabled(controller.lastProfileURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                    Button("Reveal Log") { reveal(controller.lastLogURL) }
                        .disabled(controller.lastLogURL == nil)
                    if controller.isRunning { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private var logSection: some View {
        ThemedSection(title: "Generation output", theme: theme) {
            ScrollView([.horizontal, .vertical]) {
                Text(controller.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220)
        }
    }

    @ViewBuilder
    private var background: some View {
        if theme == .iconContrast {
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.045, blue: 0.12), Color(red: 0.025, green: 0.095, blue: 0.21), Color(red: 0.01, green: 0.03, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var resolvedOutputPath: String {
        guard let environment else { return "Load an environment to preview the MP4 path." }
        return URL(fileURLWithPath: environment.outputs, isDirectory: true)
            .appendingPathComponent(environment.profileID, isDirectory: true)
            .appendingPathComponent(settings.outputName).appendingPathExtension("mp4").path
    }

    private var resolvedProfilePath: String {
        guard let environment else { return "Load an environment to preview the JSON path." }
        return URL(fileURLWithPath: environment.profiles, isDirectory: true)
            .appendingPathComponent(environment.profileID, isDirectory: true)
            .appendingPathComponent(settings.outputName).appendingPathExtension("json").path
    }

    private var outputAlreadyExists: Bool {
        guard environment != nil else { return false }
        return FileManager.default.fileExists(atPath: resolvedOutputPath) || FileManager.default.fileExists(atPath: resolvedProfilePath)
    }

    private func pathPreview(label: String, path: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(theme.secondaryText).frame(width: 52, alignment: .leading)
            Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func chooseEnvironment() {
        let panel = NSOpenPanel()
        panel.title = "Choose minimax-h3-paths.env"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            environmentPath = url.path
            loadEnvironment()
        }
    }

    private func loadEnvironment() {
        do {
            let loaded = try MiniMaxEnvironment.load(from: URL(fileURLWithPath: environmentPath))
            environment = loaded
            settings.memoryLimitGB = loaded.memoryLimitGB
            settings.streamBlockGroupSize = loaded.streamBlockGroupSize
            let issues = RuntimeSupport.validationIssues(
                runtimeURL: URL(fileURLWithPath: loaded.runtime, isDirectory: true),
                ffmpegPath: loaded.ffmpeg
            ) + ModelSupport.validationIssues(environment: loaded)
            runtimeIssue = issues.first
            onAdoptInstallation(loaded)
            environmentMessage = "Loaded \(loaded.profileID): \(loaded.memoryLimitGB) GB memory limit, stream group \(loaded.streamBlockGroupSize). Setup now targets this installation."
        } catch {
            environment = nil
            runtimeIssue = nil
            environmentMessage = "ERROR: \(error.localizedDescription)"
        }
    }

    private func locateRuntime() {
        guard let currentEnvironment = environment else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the MiniMax runtime folder or scripts/generate.py"
        panel.prompt = "Use Runtime"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selected = panel.url {
            do {
                let runtimeURL = try RuntimeSupport.runtimeURL(from: selected)
                let updated = currentEnvironment.replacingRuntime(with: runtimeURL.path)
                let issues = RuntimeSupport.validationIssues(
                    runtimeURL: runtimeURL,
                    ffmpegPath: currentEnvironment.ffmpeg
                ) + ModelSupport.validationIssues(environment: updated)
                guard issues.isEmpty else {
                    runtimeIssue = issues.joined(separator: " ")
                    return
                }
                environment = updated
                runtimeIssue = nil
                onAdoptInstallation(updated)
                if updated.root != nil {
                    environmentMessage = "Using the validated runtime at \(runtimeURL.path). Setup now targets this installation; the environment file has not been rewritten."
                } else {
                    environmentMessage = "Using the validated runtime at \(runtimeURL.path). It is outside the standard <root>/Apps/minimax-h3-mac layout, so generation can use it but Setup cannot repair it automatically."
                }
            } catch {
                runtimeIssue = error.localizedDescription
            }
        }
    }

    private func generate() {
        guard let environment else { return }
        controller.run(environment: environment, settings: settings)
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
