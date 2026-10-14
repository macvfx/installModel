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
}
