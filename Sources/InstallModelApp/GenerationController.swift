import Foundation

@MainActor
final class GenerationController: ObservableObject {
    @Published private(set) var output = "Load an installer environment file, adjust the prompt, then generate.\n"
    @Published private(set) var isRunning = false
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var lastProfileURL: URL?

    private var process: Process?

    func run(environment: MiniMaxEnvironment, settings: GenerationSettings) {
        guard !isRunning else { return }
        do {
            let command = try GenerationCommand.make(environment: environment, settings: settings)
            if FileManager.default.fileExists(atPath: command.outputURL.path) ||
                FileManager.default.fileExists(atPath: command.profileURL.path) {
                throw GenerationCommandError.invalid("The MP4 or JSON already exists. Choose a new output name; existing results are never overwritten.")
            }
            try FileManager.default.createDirectory(at: command.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: command.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try validateFiles(environment: environment, command: command)

            let task = Process()
            let pipe = Pipe()
            task.executableURL = command.executableURL
            task.currentDirectoryURL = command.workingDirectoryURL
            task.arguments = command.arguments
            task.standardOutput = pipe
            task.standardError = pipe
            output = "$ " + ([command.executableURL.path] + command.arguments).map(shellQuote).joined(separator: " ") + "\n\n"
            isRunning = true
            lastOutputURL = command.outputURL
            lastProfileURL = command.profileURL
            process = task

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.output += text }
            }
            task.terminationHandler = { [weak self] completed in
                let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: remainder, encoding: .utf8) ?? ""
                Task { @MainActor in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    self?.output += text + "\nGeneration finished with exit code \(completed.terminationStatus).\n"
                    self?.isRunning = false
                    self?.process = nil
                }
            }
            try task.run()
        } catch {
            output += "ERROR: \(error.localizedDescription)\n"
            isRunning = false
            process = nil
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        output += "\nStopping generation…\n"
        process.interrupt()
    }

    private func validateFiles(environment: MiniMaxEnvironment, command: GenerationCommand) throws {
        let required = [
            command.workingDirectoryURL.appendingPathComponent(".venv/bin/python").path,
            command.workingDirectoryURL.appendingPathComponent("scripts/generate.py").path,
            environment.ffmpeg
        ]
        for path in required where !FileManager.default.isExecutableFile(atPath: path) {
            throw GenerationCommandError.invalid("Required executable is missing: \(path). Run Check or Install / Repair first.")
        }
    }

    private func shellQuote(_ value: String) -> String {
        if value.allSatisfy({ $0.isLetter || $0.isNumber || "-._/:".contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
