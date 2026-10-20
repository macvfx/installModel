import Foundation

enum RuntimeSelectionError: LocalizedError {
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            "Choose the MiniMax runtime folder or its scripts/generate.py file."
        }
    }
}

enum RuntimeSupport {
    static let requiredReadableFiles = [
        "requirements.txt",
        "scripts/generate.py",
        "scripts/doctor.py",
        "scripts/quantize_text_encoder.py"
    ]

    static func runtimeURL(from selection: URL, fileManager: FileManager = .default) throws -> URL {
        let standardized = selection.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw RuntimeSelectionError.unsupportedSelection
        }

        if isDirectory.boolValue {
            if fileManager.fileExists(atPath: standardized.appendingPathComponent("scripts/generate.py").path) {
                return standardized
            }
            if standardized.lastPathComponent == "scripts",
               fileManager.fileExists(atPath: standardized.appendingPathComponent("generate.py").path) {
                return standardized.deletingLastPathComponent()
            }
        } else if standardized.lastPathComponent == "generate.py",
                  standardized.deletingLastPathComponent().lastPathComponent == "scripts" {
            return standardized.deletingLastPathComponent().deletingLastPathComponent()
        }

        throw RuntimeSelectionError.unsupportedSelection
    }

    static func validationIssues(
        runtimeURL: URL,
        ffmpegPath: String? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        var issues: [String] = []
        let python = runtimeURL.appendingPathComponent(".venv/bin/python").path
        if !fileManager.isExecutableFile(atPath: python) {
            issues.append("Python environment is missing or not executable: \(python)")
        }

        for relativePath in requiredReadableFiles {
            let path = runtimeURL.appendingPathComponent(relativePath).path
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) ||
                isDirectory.boolValue || !fileManager.isReadableFile(atPath: path) {
                issues.append("Required runtime file is missing or unreadable: \(path)")
            }
        }

        if let ffmpegPath, !fileManager.isExecutableFile(atPath: ffmpegPath) {
            issues.append("FFmpeg is missing or not executable: \(ffmpegPath)")
        }
        return issues
    }

    static func installationRoot(for runtimeURL: URL) -> URL? {
        let runtime = runtimeURL.standardizedFileURL
        guard runtime.lastPathComponent == "minimax-h3-mac" else { return nil }
        let apps = runtime.deletingLastPathComponent()
        guard apps.lastPathComponent == "Apps" else { return nil }
        return apps.deletingLastPathComponent()
    }
}

enum ModelSupport {
    static func validationIssues(
        environment: MiniMaxEnvironment,
        fileManager: FileManager = .default
    ) -> [String] {
        var issues: [String] = []
        let modelIndex = URL(fileURLWithPath: environment.checkpoint, isDirectory: true)
            .appendingPathComponent("model_index.json").path
        if !fileManager.isReadableFile(atPath: modelIndex) {
            issues.append("Checkpoint is incomplete; missing or unreadable: \(modelIndex). Run Install / Repair with this model folder selected")
        }

        for (label, path) in [
            ("Transformer", environment.transformer),
            ("Text encoder", environment.textEncoder),
            ("Turbo LoRA", environment.turboLoRA)
        ] {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                issues.append("\(label) folder is missing: \(path). Connect the model drive or run Install / Repair")
            }
        }
        return issues
    }
}
