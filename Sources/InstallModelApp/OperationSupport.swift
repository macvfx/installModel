import Darwin
import Foundation

final class DurableOperationLog {
    let url: URL
    private var handle: FileHandle?

    init(category: String, fileManager: FileManager = .default) throws {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/InstallModel", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(8)
        url = base.appendingPathComponent("\(formatter.string(from: Date()))-\(category)-\(suffix).log")
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            // The on-screen log remains available if the durable log fails mid-run.
        }
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    deinit { close() }
}

enum OwnedProcessTree {
    static func interrupt(rootPID: Int32) {
        let descendants = descendantPIDs(of: rootPID)
        for pid in descendants.reversed() {
            Darwin.kill(pid, SIGINT)
        }
        Darwin.kill(rootPID, SIGINT)
    }

    private static func descendantPIDs(of parentPID: Int32) -> [Int32] {
        let direct = childPIDs(of: parentPID)
        return direct + direct.flatMap { descendantPIDs(of: $0) }
    }

    private static func childPIDs(of parentPID: Int32) -> [Int32] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", String(parentPID)]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }
}
