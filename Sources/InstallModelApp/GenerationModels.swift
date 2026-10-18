import Foundation

enum MiniMaxEnvironmentError: LocalizedError {
    case unreadable(String)
    case malformedLine(Int)
    case missing(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "Could not read the environment file: \(detail)"
        case .malformedLine(let line): "Unsupported or malformed value on line \(line). Rerun the installer to recreate this file."
        case .missing(let key): "The environment file is missing \(key). Rerun Install / Repair first."
        case .invalidPath(let key): "\(key) must contain an absolute path."
        }
    }
}

struct MiniMaxEnvironment: Equatable {
    let runtime: String
    let checkpoint: String
    let transformer: String
    let textEncoder: String
    let turboLoRA: String
    let outputs: String
    let profiles: String
    let ffmpeg: String
    let profileID: String
    let memoryLimitGB: Int
    let streamBlockGroupSize: Int

    static func load(from url: URL) throws -> MiniMaxEnvironment {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw MiniMaxEnvironmentError.unreadable(error.localizedDescription) }

        let allowed = Set([
            "MINIMAX_H3_RUNTIME", "MINIMAX_H3_CHECKPOINT", "MINIMAX_H3_TRANSFORMER",
            "MINIMAX_H3_TEXT_ENCODER", "MINIMAX_H3_TURBO", "MINIMAX_H3_TURBO_LORA",
            "MINIMAX_H3_OUTPUTS", "MINIMAX_H3_PROFILES", "MINIMAX_H3_FFMPEG",
            "MINIMAX_H3_PROFILE_ID", "MINIMAX_H3_MEMORY_LIMIT_GB",
            "MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE"
        ])
        var values: [String: String] = [:]
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard line.hasPrefix("export "), let equals = line.firstIndex(of: "=") else {
                throw MiniMaxEnvironmentError.malformedLine(index + 1)
            }
            let key = String(line[line.index(line.startIndex, offsetBy: 7)..<equals])
            guard allowed.contains(key) else { continue }
            let encoded = String(line[line.index(after: equals)...])
            guard let decoded = decodeBashWord(encoded) else {
                throw MiniMaxEnvironmentError.malformedLine(index + 1)
            }
            values[key] = decoded
        }

        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else { throw MiniMaxEnvironmentError.missing(key) }
            return value
        }
        func path(_ key: String) throws -> String {
            let value = try required(key)
            guard value.hasPrefix("/") else { throw MiniMaxEnvironmentError.invalidPath(key) }
            return value
        }

        let turbo = values["MINIMAX_H3_TURBO_LORA"] ?? values["MINIMAX_H3_TURBO"]
        guard let turbo, turbo.hasPrefix("/") else { throw MiniMaxEnvironmentError.missing("MINIMAX_H3_TURBO_LORA") }
        return MiniMaxEnvironment(
            runtime: try path("MINIMAX_H3_RUNTIME"),
            checkpoint: try path("MINIMAX_H3_CHECKPOINT"),
            transformer: try path("MINIMAX_H3_TRANSFORMER"),
            textEncoder: try path("MINIMAX_H3_TEXT_ENCODER"),
            turboLoRA: turbo,
            outputs: try path("MINIMAX_H3_OUTPUTS"),
            profiles: try path("MINIMAX_H3_PROFILES"),
            ffmpeg: try path("MINIMAX_H3_FFMPEG"),
            profileID: try required("MINIMAX_H3_PROFILE_ID"),
            memoryLimitGB: Int(try required("MINIMAX_H3_MEMORY_LIMIT_GB")) ?? 16,
            streamBlockGroupSize: Int(try required("MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE")) ?? 1
        )
    }

    private static func decodeBashWord(_ value: String) -> String? {
        // The installer writes one value with bash printf %q. Accept its ordinary
        // backslash form, but never evaluate substitutions, quotes, or shell code.
        guard !value.hasPrefix("$'"), !value.contains("`"), !value.contains("$(") else { return nil }
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "'" || character == "\"" || character == ";" {
                return nil
            } else {
                result.append(character)
            }
        }
        return escaped ? nil : result
    }
}

struct GenerationSettings {
    var prompt = "A cinematic locked-off shot of a small red fox walking through fresh snow at dawn, natural coherent movement, detailed fur, soft backlight, quiet winter ambience, no text, no watermark"
    var outputName = "fox-test"
    var resolution = "768x448"
    var duration = 5
    var steps = 9
    var seed = 42
    var memoryLimitGB = 48
    var streamBlockGroupSize = 1
    var turboLoRAScale = 1.0
    var lowMemory = true
    var streamBlocks = true
    var noBlockCache = true
    var requireMuxedMP4 = true

    var validationMessage: String? {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a prompt." }
        if outputName.isEmpty || outputName == "." || outputName == ".." || outputName.contains("/") || outputName.contains(":") {
            return "Use a filename only, without folders, slashes, or colons."
        }
        let parts = resolution.lowercased().split(separator: "x")
        if parts.count != 2 || parts.contains(where: { Int($0) == nil }) { return "Resolution must look like 768x448." }
        if duration < 1 || steps < 1 || memoryLimitGB < 1 || streamBlockGroupSize < 1 { return "Numeric settings must be greater than zero." }
        return nil
    }
}

struct GenerationCommand {
    let executableURL: URL
    let workingDirectoryURL: URL
    let arguments: [String]
    let outputURL: URL
    let profileURL: URL

    static func make(environment: MiniMaxEnvironment, settings: GenerationSettings) throws -> GenerationCommand {
        if let message = settings.validationMessage { throw GenerationCommandError.invalid(message) }
        if settings.memoryLimitGB > environment.memoryLimitGB {
            throw GenerationCommandError.invalid("Memory limit cannot exceed the installed profile guideline of \(environment.memoryLimitGB) GB.")
        }
        let profileDirectory = URL(fileURLWithPath: environment.profiles, isDirectory: true)
            .appendingPathComponent(environment.profileID, isDirectory: true)
        let outputDirectory = URL(fileURLWithPath: environment.outputs, isDirectory: true)
            .appendingPathComponent(environment.profileID, isDirectory: true)
        let outputURL = outputDirectory.appendingPathComponent(settings.outputName).appendingPathExtension("mp4")
        let profileURL = profileDirectory.appendingPathComponent(settings.outputName).appendingPathExtension("json")
        let python = URL(fileURLWithPath: environment.runtime, isDirectory: true)
            .appendingPathComponent(".venv/bin/python").path
        let script = URL(fileURLWithPath: environment.runtime, isDirectory: true)
            .appendingPathComponent("scripts/generate.py").path
        var arguments = [
            "-dimsu", python, script, settings.prompt,
            "--checkpoint", environment.checkpoint,
            "--transformer", environment.transformer,
            "--text-encoder", environment.textEncoder,
            "--turbo-lora", environment.turboLoRA,
            "--turbo-lora-scale", String(settings.turboLoRAScale),
            "--profile", "quality",
            "--resolution", settings.resolution,
            "--duration", String(settings.duration),
            "--steps", String(settings.steps),
            "--seed", String(settings.seed),
            "--memory-limit-gb", String(settings.memoryLimitGB),
            "--stream-block-group-size", String(settings.streamBlockGroupSize),
            "--dense-dequant-profile", "off",
            "--ffmpeg", environment.ffmpeg,
            "--forward-profile-json", profileURL.path,
            "--output", outputURL.path
        ]
        if settings.lowMemory { arguments.append("--low-memory") }
        if settings.streamBlocks { arguments.append("--stream-blocks") }
        if settings.noBlockCache { arguments.append("--no-block-cache") }
        if settings.requireMuxedMP4 { arguments.append("--require-muxed-mp4") }
        return GenerationCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/caffeinate"),
            workingDirectoryURL: URL(fileURLWithPath: environment.runtime, isDirectory: true),
            arguments: arguments,
            outputURL: outputURL,
            profileURL: profileURL
        )
    }
}

enum GenerationCommandError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}
