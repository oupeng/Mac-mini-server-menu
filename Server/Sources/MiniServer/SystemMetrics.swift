import Foundation
import Darwin
import IOKit

public struct TopProcess: Codable {
    public let name: String
    public let cpu: Double
    public let memMB: Int
}

public struct MetricsPayload: Codable {
    public let uptimeSeconds: Int
    public let loadAvg: [Double]
    public let cpuUsage: Double
    public let cpuTemp: Double
    public let powerWatts: Double
    public let memUsedMB: Int
    public let memTotalMB: Int
    public let memPercent: Double
    public let netRxBytesPerSec: UInt64
    public let netTxBytesPerSec: UInt64
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let diskReadBytesPerSec: UInt64
    public let diskWriteBytesPerSec: UInt64
    public let topProcesses: [TopProcess]
}

public final class MetricsCollector {
    private var lastCPULoad: host_cpu_load_info?
    private var lastNetRx: UInt64 = 0
    private var lastNetTx: UInt64 = 0
    private var currentTotalRx: UInt64 = 0
    private var currentTotalTx: UInt64 = 0
    private var lastNetTime: Date = Date()

    private var lastDiskRead: UInt64 = 0
    private var lastDiskWrite: UInt64 = 0
    private var lastDiskTime: Date = Date()

    public init() {
        _ = getCPUUsage()
        _ = getNetworkThroughput()
        _ = getDiskThroughput()
    }

    public func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0.0 }
        guard let prev = lastCPULoad else {
            lastCPULoad = cpuInfo
            return 0.0
        }

        let userDiff = Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0)
        let sysDiff  = Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1)
        let idleDiff = Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2)
        let niceDiff = Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3)
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff

        lastCPULoad = cpuInfo
        guard totalTicks > 0 else { return 0.0 }
        return ((userDiff + sysDiff + niceDiff) / totalTicks) * 100.0
    }

    public func getMemoryStats() -> (usedMB: Int, totalMB: Int, percent: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / (1024 * 1024))
        guard result == KERN_SUCCESS else { return (0, totalMB, 0.0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = active + wired + compressed
        let usedMB = Int(usedBytes / (1024 * 1024))
        let percent = (Double(usedBytes) / Double(totalBytes)) * 100.0

        return (usedMB, totalMB, percent)
    }

    public func getNetworkThroughput() -> (rxSec: UInt64, txSec: UInt64, totalRx: UInt64, totalTx: UInt64) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0, 0, 0) }
        defer { freeifaddrs(ifap) }

        var currentRx: UInt64 = 0
        var currentTx: UInt64 = 0

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            // 锁定 en0 物理网卡
            if name == "en0", let data = ptr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self)
                currentRx += UInt64(ifData.pointee.ifi_ibytes)
                currentTx += UInt64(ifData.pointee.ifi_obytes)
            }
        }

        currentTotalRx = currentRx
        currentTotalTx = currentTx

        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastNetTime), 0.1)
        let rxSpeed = (lastNetRx > 0 && currentRx >= lastNetRx) ? UInt64(Double(currentRx - lastNetRx) / elapsed) : 0
        let txSpeed = (lastNetTx > 0 && currentTx >= lastNetTx) ? UInt64(Double(currentTx - lastNetTx) / elapsed) : 0

        lastNetRx = currentRx
        lastNetTx = currentTx
        lastNetTime = now
        return (rxSpeed, txSpeed, currentTotalRx, currentTotalTx)
    }

    public func getDiskThroughput() -> (readSec: UInt64, writeSec: UInt64) {
        var diskList: io_iterator_t = 0
        let match = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &diskList) == kIOReturnSuccess else {
            return (0, 0)
        }
        defer { IOObjectRelease(diskList) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var drive: io_object_t = IOIteratorNext(diskList)

        while drive != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(drive, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                totalRead += (stats["Bytes (Read)"] as? UInt64) ?? 0
                totalWrite += (stats["Bytes (Write)"] as? UInt64) ?? 0
            }
            IOObjectRelease(drive)
            drive = IOIteratorNext(diskList)
        }

        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastDiskTime), 0.1)
        let readSpeed = (lastDiskRead > 0 && totalRead >= lastDiskRead) ? UInt64(Double(totalRead - lastDiskRead) / elapsed) : 0
        let writeSpeed = (lastDiskWrite > 0 && totalWrite >= lastDiskWrite) ? UInt64(Double(totalWrite - lastDiskWrite) / elapsed) : 0

        lastDiskRead = totalRead
        lastDiskWrite = totalWrite
        lastDiskTime = now
        return (readSpeed, writeSpeed)
    }

    // 核心改动：采用 -m 严格按照物理内存驻留集 (RSS) 从大到小排序
    public func getRealTopProcesses() -> [TopProcess] {
        let task = Process()
        task.launchPath = "/bin/ps"
        // -m: sort by memory usage
        task.arguments = ["-Aceo", "%cpu,rss,comm", "-m"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var result: [TopProcess] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            if result.count >= 10 { break }
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            if parts.count >= 3 {
                let cpuVal = Double(parts[0]) ?? 0.0
                let rssKB = Int(parts[1]) ?? 0
                let memMB = rssKB / 1024
                let fullPath = parts[2...].joined(separator: " ")
                let name = URL(fileURLWithPath: fullPath).lastPathComponent
                if !name.isEmpty && memMB > 0 {
                    result.append(TopProcess(name: name, cpu: cpuVal, memMB: memMB))
                }
            }
        }
        return result
    }

    public func collectPayload() -> MetricsPayload {
        let cpu = getCPUUsage()
        let mem = getMemoryStats()
        let net = getNetworkThroughput()
        let disk = getDiskThroughput()
        let temp = SMCReader.shared.getCPUTemperature()
        let power = SMCReader.shared.getSystemPower()
        let topProcs = getRealTopProcesses()

        var load = [Double](repeating: 0.0, count: 3)
        getloadavg(&load, 3)

        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        sysctl(&mib, 2, &bootTime, &size, nil, 0)
        let nowSec = time(nil)
        let uptime = max(0, Int(nowSec - bootTime.tv_sec))

        return MetricsPayload(
            uptimeSeconds: uptime,
            loadAvg: load,
            cpuUsage: cpu,
            cpuTemp: temp,
            powerWatts: power,
            memUsedMB: mem.usedMB,
            memTotalMB: mem.totalMB,
            memPercent: mem.percent,
            netRxBytesPerSec: net.rxSec,
            netTxBytesPerSec: net.txSec,
            totalRxBytes: net.totalRx,
            totalTxBytes: net.totalTx,
            diskReadBytesPerSec: disk.readSec,
            diskWriteBytesPerSec: disk.writeSec,
            topProcesses: topProcs
        )
    }
}
