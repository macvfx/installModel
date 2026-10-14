import Foundation

enum InstallProfile: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case memory24GB = "24gb"
    case memory64GB = "64gb"
    case memory128GB = "128gb"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .memory24GB: "24 GB low-memory"
        case .memory64GB: "64 GB quality"
        case .memory128GB: "128 GB+ high-memory"
        }
    }

    var minimumMemoryGB: Int {
        switch self {
        case .automatic: 20
        case .memory24GB: 20
        case .memory64GB: 48
        case .memory128GB: 96
        }
    }

    static func recommended(forMemoryGB memoryGB: Int) -> InstallProfile? {
        guard memoryGB >= 20 else { return nil }
        if memoryGB < 48 { return .memory24GB }
        if memoryGB < 96 { return .memory64GB }
        return .memory128GB
    }

    func memoryLimit(forMemoryGB memoryGB: Int) -> Int? {
        let resolved = self == .automatic ? Self.recommended(forMemoryGB: memoryGB) : self
        switch resolved {
        case .memory24GB: return memoryGB - 8
        case .memory64GB: return memoryGB - 16
        case .memory128GB: return memoryGB - 24
        case .automatic, .none: return nil
        }
    }

    func isCompatible(withMemoryGB memoryGB: Int) -> Bool {
        memoryGB >= minimumMemoryGB
    }
}

enum WorkflowMode: String, CaseIterable, Identifiable {
    case prepare = "Stage 1: Prepare models"
    case target = "Stage 2: Set up target Mac"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .prepare:
            "Choose a local installation root and an external Models folder. This Mac downloads and prepares reusable assets. When complete, safely eject the drive and connect it to the target Mac."
        case .target:
            "Choose a local installation root on this Mac and the existing Models folder on the external drive. Run Check first, then Install / Repair; completed model files are reused and only missing target components are fetched or built."
        }
    }
}

enum InstallerOperation {
    case preview
    case check
    case install
}

struct InstallerRequest {
    var storageRoot: String
    var modelsDirectory: String?
    var profile: InstallProfile
    var licenseAccepted: Bool

    func arguments(for operation: InstallerOperation) -> [String] {
        var result = ["--storage-root", storageRoot, "--profile", profile.rawValue]
        if let modelsDirectory, !modelsDirectory.isEmpty {
            result += ["--models-dir", modelsDirectory]
        }
        if licenseAccepted {
            result.append("--license-accepted")
        }
        switch operation {
        case .preview: result.append("--show-config")
        case .check: result.append("--check-only")
        case .install: break
        }
        return result
    }
}

struct MachineInfo {
    let chip: String
    let memoryGB: Int
    let architecture: String
    let operatingSystem: String

    var isSupportedArchitecture: Bool { architecture == "arm64" }
    var recommendedProfile: InstallProfile? { .recommended(forMemoryGB: memoryGB) }
}
