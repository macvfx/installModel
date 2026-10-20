import Foundation

@MainActor
final class GenerationController: ObservableObject {
    @Published private(set) var output = "Load an installer environment file, adjust the prompt, then generate.\n"
    @Published private(set) var isRunning = false
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var lastProfileURL: URL?
    @Published private(set) var lastLogURL: URL?

    private var process: Process?
    private var operationLog: DurableOperationLog?

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
            do {
                let log = try DurableOperationLog(category: "generation")
                operationLog = log
                lastLogURL = log.url
                log.append(output)
            } catch {
                output += "WARNING: Could not create a durable generation log: \(error.localizedDescription)\n"
                operationLog = nil
                lastLogURL = nil
            }
            isRunning = true
            lastOutputURL = command.outputURL
            lastProfileURL = command.profileURL
            process = task

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.appendOutput(text) }
            }
            task.terminationHandler = { [weak self] completed in
                let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: remainder, encoding: .utf8) ?? ""
                Task { @MainActor in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    self?.appendOutput(text + "\nGeneration finished with exit code \(completed.terminationStatus).\n")
                    self?.isRunning = false
                    self?.process = nil
                    self?.operationLog?.close()
                    self?.operationLog = nil
                }
            }
            try task.run()
        } catch {
            appendOutput("ERROR: \(error.localizedDescription)\n")
            isRunning = false
            process = nil
            operationLog?.close()
            operationLog = nil
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        appendOutput("\nStopping generation and its child processes…\n")
        OwnedProcessTree.interrupt(rootPID: process.processIdentifier)
    }

    private func validateFiles(environment: MiniMaxEnvironment, command: GenerationCommand) throws {
        let issues = RuntimeSupport.validationIssues(
            runtimeURL: command.workingDirectoryURL,
            ffmpegPath: environment.ffmpeg
        ) + ModelSupport.validationIssues(environment: environment)
        if let issue = issues.first {
            throw GenerationCommandError.invalid("\(issue). Locate the correct runtime or run Install / Repair for this exact installation.")
        }
    }

    private func appendOutput(_ text: String) {
        output += text
        operationLog?.append(text)
    }

    private func shellQuote(_ value: String) -> String {
        if value.allSatisfy({ $0.isLetter || $0.isNumber || "-._/:".contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
