import Foundation
import Darwin
import IOKit

public struct TopProcess: Codable {
    public let name: String
    public let cpu: Double
    public let memMB: Int
}

public struct DiskVolumeInfo: Codable, Identifiable {
    public var id: String { mountPoint }
    public let name: String
    public let mountPoint: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let usedPercent: Double
    public let smartStatus: String
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
    public let memPressurePercent: Double // 新增：精确的连续内存压力比例 (用于波形图高度)
    public let memPressureLevel: Int
    public let swapUsedMB: Int
    public let netRxBytesPerSec: UInt64
    public let netTxBytesPerSec: UInt64
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let diskReadBytesPerSec: UInt64
    public let diskWriteBytesPerSec: UInt64
    public let topProcesses: [TopProcess]
    public let diskVolumes: [DiskVolumeInfo]
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

    private var lastDiskSpaceCheckTime: Date = .distantPast
    private var cachedDiskVolumes: [DiskVolumeInfo] = []
    private let diskSpaceInterval: TimeInterval = 600

    public init() {
        _ = getCPUUsage()
        _ = getNetworkThroughput()
        _ = getDiskThroughput()
        _ = getDiskVolumesCached()
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

    // 核心新增：提取 Wired 与 Compressed，计算真实的“内存压力”高度
    public func getMemoryStats() -> (usedMB: Int, totalMB: Int, percent: Double, pressurePercent: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / (1024 * 1024))
        guard result == KERN_SUCCESS else { return (0, totalMB, 0.0, 0.0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        
        let usedBytes = active + wired + compressed
        let usedMB = Int(usedBytes / (1024 * 1024))
        
        // 整体占用率
        let percent = (Double(usedBytes) / Double(totalBytes)) * 100.0
        // 真实内存压力（对齐活动监视器的图形逻辑）
        let pressurePercent = (Double(wired + compressed) / Double(totalBytes)) * 100.0

        return (usedMB, totalMB, percent, min(100.0, pressurePercent))
    }

    public func getMemoryPressure() -> (level: Int, swapMB: Int) {
        var level: Int32 = 1 
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        var swapUsedMB = 0
        var buf = [UInt64](repeating: 0, count: 4)
        var bufSize = buf.count * MemoryLayout<UInt64>.size
        if sysctlbyname("vm.swapusage", &buf, &bufSize, nil, 0) == 0 {
            swapUsedMB = Int(buf[2] / (1024 * 1024))
        }
        return (Int(level), swapUsedMB)
    }

    public func getNetworkThroughput() -> (rxSec: UInt64, txSec: UInt64, totalRx: UInt64, totalTx: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return (0, 0, 0, 0) }

        var buffer = [Int8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0 else { return (0, 0, 0, 0) }

        var currentRx: UInt64 = 0
        var currentTx: UInt64 = 0

        buffer.withUnsafeBufferPointer { bufPtr in
            var cursor = bufPtr.baseAddress!
            let end = cursor.advanced(by: len)

            while cursor < end {
                let msgHdr = cursor.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
                if msgHdr.ifm_type == RTM_IFINFO2 {
                    let if2m = cursor.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                    let ifIndex = Int(if2m.ifm_index)
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if let _ = if_indextoname(UInt32(ifIndex), &nameBuf) {
                        let name = String(cString: nameBuf)
                        if name == "en0" {
                            currentRx = if2m.ifm_data.ifi_ibytes
                            currentTx = if2m.ifm_data.ifi_obytes
                            break
                        }
                    }
                }
                cursor = cursor.advanced(by: Int(msgHdr.ifm_msglen))
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
        return (rxSpeed, txSpeed, currentRx, currentTx)
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

    public func getDiskVolumesCached() -> [DiskVolumeInfo] {
        let now = Date()
        if !cachedDiskVolumes.isEmpty && now.timeIntervalSince(lastDiskSpaceCheckTime) < diskSpaceInterval {
            return cachedDiskVolumes
        }

        var mntbuf: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mntbuf, MNT_NOWAIT)
        guard count > 0, let buffer = mntbuf else { return cachedDiskVolumes }

        var results: [DiskVolumeInfo] = []
        let smartMap = getCachedSmartStatusMap()

        for i in 0..<Int(count) {
            let fs = buffer[i]
            let mntOn = withUnsafePointer(to: fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let mntFrom = withUnsafePointer(to: fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }

            if mntOn == "/" || mntOn.hasPrefix("/Volumes/") {
                if mntOn.contains("Preboot") || mntOn.contains("Recovery") || mntOn.contains("VM") {
                    continue
                }
                let blockSize = UInt64(fs.f_bsize)
                let totalBytes = UInt64(fs.f_blocks) * blockSize
                let freeBytes = UInt64(fs.f_bavail) * blockSize

                if totalBytes > 0 {
                    let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
                    let percent = (Double(usedBytes) / Double(totalBytes)) * 100.0

                    var displayName = URL(fileURLWithPath: mntOn).lastPathComponent
                    if mntOn == "/" { displayName = "Macintosh HD" }

                    let devName = URL(fileURLWithPath: mntFrom).lastPathComponent
                    let bsdParent = devName.components(separatedBy: "s").first ?? devName
                    let smart = smartMap[bsdParent] ?? "良好"

                    results.append(DiskVolumeInfo(
                        name: displayName,
                        mountPoint: mntOn,
                        totalBytes: totalBytes,
                        freeBytes: freeBytes,
                        usedPercent: percent,
                        smartStatus: smart
                    ))
                }
            }
        }

        cachedDiskVolumes = results
        lastDiskSpaceCheckTime = now
        return results
    }

    private func getCachedSmartStatusMap() -> [String: String] {
        var map: [String: String] = [:]
        var iter: io_iterator_t = 0
        let match = IOServiceMatching("IOBlockStorageDevice")
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iter) == kIOReturnSuccess else { return map }
        defer { IOObjectRelease(iter) }

        var dev = IOIteratorNext(iter)
        while dev != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(dev, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let bsdName = dict["BSD Name"] as? String {
                if let smart = dict["SMART Status"] as? String {
                    if smart == "Verified" { map[bsdName] = "良好" }
                    else if smart == "Failing" { map[bsdName] = "故障" }
                    else { map[bsdName] = "不支持" }
                } else {
                    map[bsdName] = "不支持"
                }
            }
            IOObjectRelease(dev)
            dev = IOIteratorNext(iter)
        }
        return map
    }

    public func getRealTopProcesses() -> [TopProcess] {
        let task = Process()
        task.launchPath = "/bin/ps"
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
        let memPressure = getMemoryPressure()
        let net = getNetworkThroughput()
        let disk = getDiskThroughput()
        let temp = SMCReader.shared.getCPUTemperature()
        let power = SMCReader.shared.getSystemPower()
        let topProcs = getRealTopProcesses()
        let volumes = getDiskVolumesCached()

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
            memPressurePercent: mem.pressurePercent,
            memPressureLevel: memPressure.level,
            swapUsedMB: memPressure.swapMB,
            netRxBytesPerSec: net.rxSec,
            netTxBytesPerSec: net.txSec,
            totalRxBytes: net.totalRx,
            totalTxBytes: net.totalTx,
            diskReadBytesPerSec: disk.readSec,
            diskWriteBytesPerSec: disk.writeSec,
            topProcesses: topProcs,
            diskVolumes: volumes
        )
    }
}
