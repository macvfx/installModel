import Foundation

@MainActor
final class InstallerController: ObservableObject {
    @Published private(set) var output = "Ready. Run Preview or Check before installing.\n"
    @Published private(set) var isRunning = false
    @Published private(set) var lastExitCode: Int32?

    private var process: Process?

    static var scriptURL: URL? {
        Bundle.module.url(
            forResource: "install-minimax-h3-mac",
            withExtension: "sh",
            subdirectory: "Resources/Scripts"
        )
    }

    func run(_ request: InstallerRequest, operation: InstallerOperation) {
        guard !isRunning else { return }
        guard let scriptURL = Self.scriptURL else {
            output += "ERROR: Bundled installer script is missing.\n"
            return
        }

        let arguments = request.arguments(for: operation)
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path] + arguments
        task.standardOutput = pipe
        task.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/local/bin"
        task.environment = environment

        output = "$ " + commandPreview(scriptPath: scriptURL.path, arguments: arguments) + "\n\n"
        lastExitCode = nil
        isRunning = true
        process = task

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.output += text }
        }

        task.terminationHandler = { [weak self] completed in
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            let remainderText = String(data: remainder, encoding: .utf8) ?? ""
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.output += remainderText
                self?.output += "\nProcess finished with exit code \(completed.terminationStatus).\n"
                self?.lastExitCode = completed.terminationStatus
                self?.isRunning = false
                self?.process = nil
            }
        }

        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            output += "ERROR: \(error.localizedDescription)\n"
            isRunning = false
            process = nil
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        output += "\nStopping installer…\n"
        process.interrupt()
    }

    private func commandPreview(scriptPath: String, arguments: [String]) -> String {
        (["bash", scriptPath] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        if value.allSatisfy({ $0.isLetter || $0.isNumber || "-._/:".contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
