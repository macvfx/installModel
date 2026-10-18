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
}
