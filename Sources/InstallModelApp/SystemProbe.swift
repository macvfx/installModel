import Darwin
import Foundation

enum SystemProbe {
    static func currentMachine() -> MachineInfo {
        let processInfo = ProcessInfo.processInfo
        let memoryGB = Int(processInfo.physicalMemory / 1_073_741_824)
        return MachineInfo(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown Apple chip",
            memoryGB: memoryGB,
            architecture: architecture(),
            operatingSystem: processInfo.operatingSystemVersionString
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }

    private static func architecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }.prefix { $0 != 0 }
        return String(bytes: bytes.map(UInt8.init), encoding: .utf8) ?? "unknown"
    }
}
