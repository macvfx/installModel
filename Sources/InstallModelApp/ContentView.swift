import AppKit
import SwiftUI

struct ContentView: View {
    private let machine = SystemProbe.currentMachine()

    @StateObject private var installer = InstallerController()
    @State private var workflow: WorkflowMode = .prepare
    @State private var profile: InstallProfile = .automatic
    @State private var storageRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("MiniMax-H3").path
    @State private var useSeparateModelsDirectory = true
    @State private var modelsDirectory = "/Volumes/Example-H3-Models/Models"
    @State private var licenseAccepted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                machineSection
                accountSection
                workflowSection
                storageSection
                actionsSection
                outputSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MiniMax H3 Setup")
                .font(.largeTitle.bold())
            Text("A minimal front end for the repository's audited installer. Tokens are never requested or stored by this app.")
                .foregroundStyle(.secondary)
        }
    }

    private var machineSection: some View {
        GroupBox("1. Detected Mac") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { Text("Chip").foregroundStyle(.secondary); Text(machine.chip) }
                GridRow { Text("Unified memory").foregroundStyle(.secondary); Text("\(machine.memoryGB) GB") }
                GridRow { Text("Architecture").foregroundStyle(.secondary); Text(machine.architecture) }
                GridRow { Text("Suggested profile").foregroundStyle(.secondary); Text(machine.recommendedProfile?.title ?? "Unsupported: at least 24 GB-class memory required") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !machine.isSupportedArchitecture {
                Label("Apple Silicon arm64 is required.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var accountSection: some View {
        GroupBox("2. Hugging Face account and license") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create or sign in to a Hugging Face account, review the MiniMax H3 Community License on the model page, then authenticate this Mac with `hf auth login` in Terminal. Authentication is required on each Mac; the external model drive does not carry your account login.")
                HStack {
                    Button("Create account") { open("https://huggingface.co/join") }
                    Button("Open model and license") { open("https://huggingface.co/MiniMaxAI/MiniMax-H3") }
                    Button("Token settings") { open("https://huggingface.co/settings/tokens") }
                }
                Toggle("I personally reviewed and accepted the MiniMax H3 license", isOn: $licenseAccepted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var workflowSection: some View {
        GroupBox("3. Choose workflow") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Workflow", selection: $workflow) {
                    ForEach(WorkflowMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text(workflow.guidance).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storageSection: some View {
        GroupBox("4. Storage and profile") {
            VStack(alignment: .leading, spacing: 12) {
                pathRow("Local installation root", text: $storageRoot) {
                    chooseDirectory(title: "Choose local installation root", value: $storageRoot)
                }
                Toggle("Keep model files in a separate folder or external drive", isOn: $useSeparateModelsDirectory)
                if useSeparateModelsDirectory {
                    pathRow("Models folder", text: $modelsDirectory) {
                        chooseDirectory(title: "Choose or create the Models folder", value: $modelsDirectory)
                    }
                }
                Picker("Profile", selection: $profile) {
                    ForEach(InstallProfile.allCases) { item in Text(item.title).tag(item) }
                }
                .frame(maxWidth: 320)

                if let limit = profile.memoryLimit(forMemoryGB: machine.memoryGB) {
                    Text("Estimated MLX memory guideline for this selection: \(limit) GB.")
                        .foregroundStyle(.secondary)
                }
                if !profile.isCompatible(withMemoryGB: machine.memoryGB) {
                    Label("This profile requires at least \(profile.minimumMemoryGB) GB unified memory.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsSection: some View {
        GroupBox("5. Preview, check, and install") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview is read-only. Check reports missing components. Install / Repair may install Homebrew formulas, download large model files, create a Python environment, and build the profile-specific conditioner.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Preview configuration") { run(.preview) }
                    Button("Check this Mac") { run(.check) }
                    Button("Install / Repair") { run(.install) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!licenseAccepted || !configurationIsValid)
                    Button("Stop", role: .destructive) { installer.stop() }
                        .disabled(!installer.isRunning)
                    if installer.isRunning { ProgressView().controlSize(.small) }
                }
                if !licenseAccepted {
                    Text("License confirmation is required before model installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outputSection: some View {
        GroupBox("Installer output") {
            ScrollView([.horizontal, .vertical]) {
                Text(installer.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220)
        }
    }

    private var configurationIsValid: Bool {
        machine.isSupportedArchitecture && profile.isCompatible(withMemoryGB: machine.memoryGB) && storageRoot.hasPrefix("/") &&
            (!useSeparateModelsDirectory || modelsDirectory.hasPrefix("/"))
    }

    private func request() -> InstallerRequest {
        InstallerRequest(
            storageRoot: storageRoot,
            modelsDirectory: useSeparateModelsDirectory ? modelsDirectory : nil,
            profile: profile,
            licenseAccepted: licenseAccepted
        )
    }

    private func run(_ operation: InstallerOperation) {
        installer.run(request(), operation: operation)
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseDirectory(title: String, value: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            value.wrappedValue = url.path
        }
    }

    @ViewBuilder
    private func pathRow(_ label: String, text: Binding<String>, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: choose)
            }
        }
    }
}
