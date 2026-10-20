import AppKit
import SwiftUI

struct ContentView: View {
    private let machine = SystemProbe.currentMachine()

    @StateObject private var installer = InstallerController()
    @AppStorage("installModel.workflow") private var storedWorkflow = WorkflowMode.prepare.rawValue
    @AppStorage("installModel.profile") private var storedProfile = InstallProfile.automatic.rawValue
    @AppStorage("installModel.storageRoot") private var storageRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("MiniMax-H3").path
    @AppStorage("installModel.useSeparateModelsDirectory") private var useSeparateModelsDirectory = true
    @AppStorage("installModel.modelsDirectory") private var modelsDirectory = "/Volumes/Example-H3-Models/Models"
    @State private var licenseAccepted = false
    @AppStorage("installModel.theme") private var storedTheme = AppTheme.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: storedTheme) ?? .system }
    private var workflow: WorkflowMode { WorkflowMode(rawValue: storedWorkflow) ?? .prepare }
    private var profile: InstallProfile { InstallProfile(rawValue: storedProfile) ?? .automatic }

    var body: some View {
        TabView {
            setupPage
                .tabItem { Label("Setup", systemImage: "shippingbox") }
            GenerateView(
                suggestedEnvironmentPath: URL(fileURLWithPath: storageRoot, isDirectory: true)
                    .appendingPathComponent("minimax-h3-paths.env").path,
                theme: theme,
                onAdoptInstallation: adoptInstallation
            )
            .tabItem { Label("Generate", systemImage: "film.stack") }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.forcedColorScheme)
    }

    private var setupPage: some View {
        ZStack {
            background
                .ignoresSafeArea()

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
        .foregroundStyle(theme.primaryText)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MiniMax H3 Setup")
                    .font(.largeTitle.bold())
                    .foregroundStyle(theme.heading)
                Text("A minimal front end for the repository's audited installer. Tokens are never requested or stored by this app.")
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 20)
            themeControl
        }
    }

    private var machineSection: some View {
        ThemedSection(title: "1. Detected Mac", theme: theme) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { Text("Chip").foregroundStyle(theme.secondaryText); Text(machine.chip) }
                GridRow { Text("Unified memory").foregroundStyle(theme.secondaryText); Text("\(machine.memoryGB) GB") }
                GridRow { Text("Architecture").foregroundStyle(theme.secondaryText); Text(machine.architecture) }
                GridRow { Text("Suggested profile").foregroundStyle(theme.secondaryText); Text(machine.recommendedProfile?.title ?? "Unsupported: at least 24 GB-class memory required") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !machine.isSupportedArchitecture {
                Label("Apple Silicon arm64 is required.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var accountSection: some View {
        ThemedSection(title: "2. Hugging Face account and license", theme: theme) {
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
        ThemedSection(title: "3. Choose workflow", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Workflow", selection: Binding(
                    get: { workflow },
                    set: { storedWorkflow = $0.rawValue }
                )) {
                    ForEach(WorkflowMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text(workflow.guidance).foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storageSection: some View {
        ThemedSection(title: "4. Storage and profile", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                pathRow("Installation root", text: $storageRoot) {
                    chooseDirectory(title: "Choose installation root", value: $storageRoot)
                }
                capacityRow(label: "Installation files", info: installationStorage, minimumGiB: 20)
                Toggle("Keep model files in a separate folder or external drive", isOn: $useSeparateModelsDirectory)
                if useSeparateModelsDirectory {
                    pathRow("Models folder", text: $modelsDirectory) {
                        chooseDirectory(title: "Choose or create the Models folder", value: $modelsDirectory)
                    }
                }
                Text("The app remembers these locations, workflow, and profile for the next launch.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                capacityRow(label: "Model files", info: modelStorage, minimumGiB: 120, recommendedGiB: 200)
                Picker("Profile", selection: Binding(
                    get: { profile },
                    set: { storedProfile = $0.rawValue }
                )) {
                    ForEach(InstallProfile.allCases) { item in Text(item.title).tag(item) }
                }
                .frame(maxWidth: 320)

                if let limit = profile.memoryLimit(forMemoryGB: machine.memoryGB) {
                    Text("Estimated MLX memory guideline for this selection: \(limit) GB.")
                        .foregroundStyle(theme.secondaryText)
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
        ThemedSection(title: "5. Preview, check, and install", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview is read-only. Check reports missing components. Install / Repair may install Homebrew formulas, download large model files, create a Python environment, and build the profile-specific conditioner.")
                    .foregroundStyle(theme.secondaryText)
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
                        .foregroundStyle(theme.secondaryText)
                }
                if !storageCapacityIsValid {
                    Text("Choose mounted storage with at least 20 GiB free for installation files and 120 GiB free for model files. The selected attached drive is measured directly when it contains the chosen path.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outputSection: some View {
        ThemedSection(title: "Installer output", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView([.horizontal, .vertical]) {
                    Text(installer.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 220)
                if let logURL = installer.lastLogURL {
                    Button("Reveal operation log") { reveal(logURL) }
                        .help(logURL.path)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if theme == .iconContrast {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.045, blue: 0.12),
                    Color(red: 0.025, green: 0.095, blue: 0.21),
                    Color(red: 0.01, green: 0.03, blue: 0.085)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var themeControl: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                storedTheme = theme == .iconContrast ? AppTheme.system.rawValue : AppTheme.iconContrast.rawValue
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme == .iconContrast ? theme.accent : theme.secondaryText)
                .frame(width: 34, height: 34)
                .background(
                    theme == .iconContrast
                        ? Color(red: 0.05, green: 0.16, blue: 0.32)
                        : Color(nsColor: .controlBackgroundColor),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(theme == .iconContrast ? theme.heading.opacity(0.65) : Color.secondary.opacity(0.25))
                }
        }
        .buttonStyle(.plain)
        .help(theme == .iconContrast ? "Return to System theme" : "Reveal Magic theme")
        .accessibilityLabel("Appearance")
        .accessibilityHint(theme == .iconContrast ? "Return to System theme" : "Reveal Magic theme")
        .accessibilityValue(theme.title)
    }

    private var configurationIsValid: Bool {
        machine.isSupportedArchitecture && profile.isCompatible(withMemoryGB: machine.memoryGB) && storageRoot.hasPrefix("/") &&
            (!useSeparateModelsDirectory || modelsDirectory.hasPrefix("/")) && storageCapacityIsValid
    }

    private var effectiveModelsDirectory: String {
        if useSeparateModelsDirectory { return modelsDirectory }
        return URL(fileURLWithPath: storageRoot, isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true).path
    }

    private var installationStorage: StorageVolumeInfo? {
        StorageProbe.inspect(path: storageRoot)
    }

    private var modelStorage: StorageVolumeInfo? {
        StorageProbe.inspect(path: effectiveModelsDirectory)
    }

    private var storageCapacityIsValid: Bool {
        guard let installationStorage, let modelStorage else { return false }
        return installationStorage.availableGiB >= 20 && modelStorage.availableGiB >= 120
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

    private func adoptInstallation(_ environment: MiniMaxEnvironment) {
        if let root = environment.root {
            storageRoot = root
        } else if let derived = RuntimeSupport.installationRoot(
            for: URL(fileURLWithPath: environment.runtime, isDirectory: true)
        ) {
            storageRoot = derived.path
        }
        if let models = environment.models {
            modelsDirectory = models
            useSeparateModelsDirectory = models != URL(fileURLWithPath: storageRoot, isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true).path
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            Text(label).font(.caption).foregroundStyle(theme.secondaryText)
            HStack {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: choose)
            }
        }
    }

    @ViewBuilder
    private func capacityRow(
        label: String,
        info: StorageVolumeInfo?,
        minimumGiB: Int,
        recommendedGiB: Int? = nil
    ) -> some View {
        if let info {
            let belowMinimum = info.availableGiB < minimumGiB
            let belowRecommendation = recommendedGiB.map { info.availableGiB < $0 } ?? false
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: belowMinimum ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text("\(label): \(info.availableGiB) GiB free on \(info.locationDescription).")
                    .textSelection(.enabled)
                if belowMinimum {
                    Text("Minimum: \(minimumGiB) GiB.").fontWeight(.semibold)
                } else if belowRecommendation, let recommendedGiB {
                    Text("\(recommendedGiB) GiB recommended.").fontWeight(.semibold)
                }
            }
            .font(.caption)
            .foregroundStyle(belowMinimum ? Color.red : (belowRecommendation ? Color.orange : theme.secondaryText))
        } else {
            Label("\(label): choose an existing mounted folder or a new folder inside an existing mounted volume.", systemImage: "externaldrive")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
