import XCTest
@testable import InstallModelApp

final class InstallModelAppTests: XCTestCase {
    func testProfileRecommendationsMatchInstallerThresholds() {
        XCTAssertNil(InstallProfile.recommended(forMemoryGB: 19))
        XCTAssertEqual(InstallProfile.recommended(forMemoryGB: 24), .memory24GB)
        XCTAssertEqual(InstallProfile.recommended(forMemoryGB: 64), .memory64GB)
        XCTAssertEqual(InstallProfile.recommended(forMemoryGB: 128), .memory128GB)
    }

    func testMemoryHeadroomMatchesInstallerProfiles() {
        XCTAssertEqual(InstallProfile.memory24GB.memoryLimit(forMemoryGB: 24), 16)
        XCTAssertEqual(InstallProfile.memory64GB.memoryLimit(forMemoryGB: 64), 48)
        XCTAssertEqual(InstallProfile.memory128GB.memoryLimit(forMemoryGB: 128), 104)
    }

    func testIncompatibleProfileIsRejectedByUIModel() {
        XCTAssertFalse(InstallProfile.memory128GB.isCompatible(withMemoryGB: 64))
        XCTAssertTrue(InstallProfile.memory128GB.isCompatible(withMemoryGB: 128))
    }

    @MainActor
    func testBundledInstallerIsAvailable() {
        let scriptURL = InstallerController.scriptURL
        XCTAssertNotNil(scriptURL)
    }

    @MainActor
    func testBundledInstallerProvidesEveryDoctorToolAndRunsFromRuntime() throws {
        let scriptURL = try XCTUnwrap(InstallerController.scriptURL)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("REQUIRED_COMMANDS=\"git hf uv\""))
        XCTAssertTrue(script.contains("for formula in python@3.12 ffmpeg git hf uv; do"))
        XCTAssertTrue(script.contains("cd \"$RUNTIME_DIR\""))
    }

    func testStageTwoCheckArgumentsReuseExternalModels() {
        let request = InstallerRequest(
            storageRoot: "/Users/example/MiniMax-H3",
            modelsDirectory: "/Volumes/Example-H3-Models/Models",
            profile: .memory128GB,
            licenseAccepted: true
        )
        XCTAssertEqual(
            request.arguments(for: .check),
            [
                "--storage-root", "/Users/example/MiniMax-H3",
                "--profile", "128gb",
                "--models-dir", "/Volumes/Example-H3-Models/Models",
                "--license-accepted", "--check-only"
            ]
        )
    }

    func testEnvironmentLoaderDecodesEscapedExternalDrivePathsWithoutExecutingShell() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("minimax-h3-paths.env")
        let source = """
        export MINIMAX_H3_ROOT=/Users/example/MiniMax-H3
        export MINIMAX_H3_MODELS=/Volumes/Model\\ Drive/Models
        export MINIMAX_H3_RUNTIME=/Volumes/Model\\ Drive/Runtime
        export MINIMAX_H3_CHECKPOINT=/Volumes/Model\\ Drive/Models/Checkpoint
        export MINIMAX_H3_TRANSFORMER=/Volumes/Model\\ Drive/Models/Transformer
        export MINIMAX_H3_TEXT_ENCODER=/Volumes/Model\\ Drive/Models/Encoder
        export MINIMAX_H3_TURBO_LORA=/Volumes/Model\\ Drive/Models/Turbo
        export MINIMAX_H3_OUTPUTS=/Volumes/Model\\ Drive/Outputs
        export MINIMAX_H3_PROFILES=/Volumes/Model\\ Drive/Profiles
        export MINIMAX_H3_FFMPEG=/opt/homebrew/bin/ffmpeg
        export MINIMAX_H3_PROFILE_ID=m1-max-64gb
        export MINIMAX_H3_MEMORY_LIMIT_GB=48
        export MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE=1
        export UNRELATED_VALUE=$(touch\\ /tmp/must-not-run)
        """
        try source.write(to: file, atomically: true, encoding: .utf8)

        let environment = try MiniMaxEnvironment.load(from: file)
        XCTAssertEqual(environment.root, "/Users/example/MiniMax-H3")
        XCTAssertEqual(environment.models, "/Volumes/Model Drive/Models")
        XCTAssertEqual(environment.runtime, "/Volumes/Model Drive/Runtime")
        XCTAssertEqual(environment.memoryLimitGB, 48)
        XCTAssertEqual(environment.profileID, "m1-max-64gb")
    }

    func testEnvironmentLoaderRejectsShellSyntaxInRequiredValue() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try "export MINIMAX_H3_RUNTIME=$(touch\\ /tmp/must-not-run)\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MiniMaxEnvironment.load(from: file))
    }

    func testGenerationCommandUsesDirectArgumentsAndPairsMP4WithJSON() throws {
        let environment = MiniMaxEnvironment(
            runtime: "/Users/example/MiniMax-H3/Runtime",
            checkpoint: "/Volumes/Models/Checkpoint",
            transformer: "/Volumes/Models/Transformer",
            textEncoder: "/Volumes/Models/Encoder",
            turboLoRA: "/Volumes/Models/Turbo",
            outputs: "/Volumes/Models/Outputs",
            profiles: "/Volumes/Models/Profiles",
            ffmpeg: "/opt/homebrew/bin/ffmpeg",
            profileID: "m2-ultra-128gb",
            memoryLimitGB: 104,
            streamBlockGroupSize: 1
        )
        var settings = GenerationSettings()
        settings.prompt = "A fox; this semicolon remains prompt text"
        settings.outputName = "snow-fox"
        let command = try GenerationCommand.make(environment: environment, settings: settings)

        XCTAssertEqual(command.executableURL.path, "/usr/bin/caffeinate")
        XCTAssertTrue(command.arguments.contains(settings.prompt))
        XCTAssertEqual(command.outputURL.path, "/Volumes/Models/Outputs/m2-ultra-128gb/snow-fox.mp4")
        XCTAssertEqual(command.profileURL.path, "/Volumes/Models/Profiles/m2-ultra-128gb/snow-fox.json")
        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--ffmpeg")! + 1], "/opt/homebrew/bin/ffmpeg")
    }

    func testGenerationRejectsFolderInOutputName() {
        var settings = GenerationSettings()
        settings.outputName = "other/frosty"
        XCTAssertNotNil(settings.validationMessage)
    }

    func testRuntimeLocatorAcceptsGenerateScriptAndDerivesInstallationRoot() throws {
        let installation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runtime = installation.appendingPathComponent("Apps/minimax-h3-mac", isDirectory: true)
        let scripts = runtime.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let generate = scripts.appendingPathComponent("generate.py")
        try "# generated fixture\n".write(to: generate, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: installation) }

        XCTAssertEqual(try RuntimeSupport.runtimeURL(from: generate), runtime)
        XCTAssertEqual(RuntimeSupport.installationRoot(for: runtime)?.path, installation.path)
    }

    func testRuntimeValidationTreatsPythonScriptAsReadableNotExecutable() throws {
        let runtime = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let python = runtime.appendingPathComponent(".venv/bin/python")
        let ffmpeg = runtime.appendingPathComponent("tools/ffmpeg")
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ffmpeg.deletingLastPathComponent(), withIntermediateDirectories: true)
        for relativePath in RuntimeSupport.requiredReadableFiles {
            let file = runtime.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# readable fixture\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        try "#!/bin/sh\n".write(to: python, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: ffmpeg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
        defer { try? FileManager.default.removeItem(at: runtime) }

        XCTAssertEqual(RuntimeSupport.validationIssues(runtimeURL: runtime, ffmpegPath: ffmpeg.path), [])
    }

    func testRuntimeValidationReportsMissingGenerateScript() throws {
        let runtime = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runtime) }

        XCTAssertTrue(
            RuntimeSupport.validationIssues(runtimeURL: runtime)
                .contains(where: { $0.contains("scripts/generate.py") })
        )
    }

    func testModelValidationReportsMissingCheckpointIndexBeforeGeneration() throws {
        let models = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkpoint = models.appendingPathComponent("MiniMax-H3/FL2VA", isDirectory: true)
        let transformer = models.appendingPathComponent("Transformer", isDirectory: true)
        let encoder = models.appendingPathComponent("Encoder", isDirectory: true)
        let turbo = models.appendingPathComponent("Turbo", isDirectory: true)
        for directory in [checkpoint, transformer, encoder, turbo] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: models) }

        let environment = MiniMaxEnvironment(
            runtime: "/Applications/example-runtime",
            checkpoint: checkpoint.path,
            transformer: transformer.path,
            textEncoder: encoder.path,
            turboLoRA: turbo.path,
            outputs: "/tmp/outputs",
            profiles: "/tmp/profiles",
            ffmpeg: "/opt/homebrew/bin/ffmpeg",
            profileID: "64gb",
            memoryLimitGB: 48,
            streamBlockGroupSize: 1
        )

        let missingIssues = ModelSupport.validationIssues(environment: environment)
        XCTAssertTrue(missingIssues.contains(where: { $0.contains("model_index.json") }))

        try "{}\n".write(to: checkpoint.appendingPathComponent("model_index.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ModelSupport.validationIssues(environment: environment), [])
    }

    func testStorageProbeUsesExistingVolumeForNewChildFolder() throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: volume) }

        let requested = volume.appendingPathComponent("New MiniMax Install/Models", isDirectory: true)
        let info = try XCTUnwrap(StorageProbe.inspect(path: requested.path))
        XCTAssertEqual(info.probePath, volume.path)
        XCTAssertGreaterThan(info.availableGiB, 0)
    }

    func testStorageProbeRejectsAnUnmountedVolumesPath() {
        let missingVolume = "/Volumes/Example-Missing-\(UUID().uuidString)/Models"
        XCTAssertNil(StorageProbe.inspect(path: missingVolume))
    }
}
