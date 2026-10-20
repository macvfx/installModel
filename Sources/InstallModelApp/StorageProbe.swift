import Foundation

struct StorageVolumeInfo: Equatable {
    let requestedPath: String
    let probePath: String
    let volumeName: String
    let mountPath: String
    let availableBytes: Int64

    var availableGiB: Int {
        Int(availableBytes / 1_073_741_824)
    }

    var locationDescription: String {
        let kind = mountPath.hasPrefix("/Volumes/") ? "attached volume" : "local volume"
        return "\(volumeName) (\(kind), mounted at \(mountPath))"
    }
}

enum StorageProbe {
    static func inspect(path: String, fileManager: FileManager = .default) -> StorageVolumeInfo? {
        guard path.hasPrefix("/") else { return nil }
        let requestedURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let requiredMount = requiredMountedVolume(for: requestedURL)
        if let requiredMount, !fileManager.fileExists(atPath: requiredMount.path) {
            return nil
        }
        guard let probeURL = deepestExistingAncestor(
            of: requestedURL,
            stoppingAt: requiredMount ?? URL(fileURLWithPath: "/", isDirectory: true),
            fileManager: fileManager
        ) else { return nil }

        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: probeURL.path),
              let freeNumber = attributes[.systemFreeSize] as? NSNumber else { return nil }
        let values = try? probeURL.resourceValues(forKeys: [.volumeNameKey, .volumeURLKey])
        let mountURL = values?.volume ?? probeURL
        let volumeName = values?.volumeName ?? mountURL.lastPathComponent

        return StorageVolumeInfo(
            requestedPath: requestedURL.path,
            probePath: probeURL.path,
            volumeName: volumeName.isEmpty ? mountURL.path : volumeName,
            mountPath: mountURL.path,
            availableBytes: freeNumber.int64Value
        )
    }

    private static func requiredMountedVolume(for url: URL) -> URL? {
        let components = url.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes", isDirectory: true)
            .appendingPathComponent(components[2], isDirectory: true)
    }

    private static func deepestExistingAncestor(
        of url: URL,
        stoppingAt lowerBound: URL,
        fileManager: FileManager
    ) -> URL? {
        var candidate = url
        while candidate.path != lowerBound.path && !fileManager.fileExists(atPath: candidate.path) {
            candidate.deleteLastPathComponent()
        }
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
