import Foundation
import Darwin
import IOKit
import CSMART

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

public struct KernelHealthInfo: Codable {
    public let wiredMB: Int
    public let wiredPercent: Double
    public let openFiles: Int
    public let maxFiles: Int
    public let maxProc: Int
    public let mbufLimReached: Int
    public let mbufLimRecent60s: Int
    public let mbufCount: Int
    public let zleakActive: Int
    public let recentAlerts: Int
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
    public let memPressurePercent: Double
    public let memPressureLevel: Int
    public let swapUsedMB: Int
    public let netRxBytesPerSec: UInt64
    public let netTxBytesPerSec: UInt64
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let diskReadBytesPerSec: UInt64
    public let diskWriteBytesPerSec: UInt64
    public let processCount: Int
    public let topProcesses: [TopProcess]
    public let diskVolumes: [DiskVolumeInfo]
    public let kernelHealth: KernelHealthInfo
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

    // 10 分钟低频缓存：磁盘空间
    private var lastDiskSpaceCheckTime: Date = .distantPast
    private var cachedDiskVolumes: [DiskVolumeInfo] = []
    private let diskSpaceInterval: TimeInterval = 600

    // 外接盘 SMART 长周期缓存（6 小时更新一次，休眠绝不打扰）
    private var smartCache: [String: (status: String, checkedAt: Date)] = [:]
    private let externalSmartInterval: TimeInterval = 21600

    // 5 秒中频缓存：全系统 Top 进程
    private var lastProcessCheckTime: Date = .distantPast
    private var cachedTopProcesses: [TopProcess] = []
    private var cachedProcessCount: Int = 0
    private let processInterval: TimeInterval = 5.0

    // 60 秒低频缓存：内置 SSD 诊断报告哨兵
    private var lastAlertCheckTime: Date = .distantPast
    private var cachedRecentAlerts: Int = 0
    private let alertCheckInterval: TimeInterval = 60.0

    // Socket 缓冲溢出 60 秒滑动增量窗口
    private var lastMbufLimReached: Int?
    private var lastMbufSampleTime: Date = .distantPast
    private var recentMbufBurstSamples: [(time: Date, delta: Int)] = []

    public init() {
        _ = getCPUUsage()
        _ = getNetworkThroughput()
        _ = getDiskThroughput()
        _ = getDiskVolumesCached()
        _ = getRealTopProcesses()
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

        let userDiff = Double(cpuInfo.cpu_ticks.0 &- prev.cpu_ticks.0)
        let sysDiff  = Double(cpuInfo.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idleDiff = Double(cpuInfo.cpu_ticks.2 &- prev.cpu_ticks.2)
        let niceDiff = Double(cpuInfo.cpu_ticks.3 &- prev.cpu_ticks.3)
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff

        lastCPULoad = cpuInfo
        guard totalTicks > 0 else { return 0.0 }
        return ((userDiff + sysDiff + niceDiff) / totalTicks) * 100.0
    }

    public func getMemoryStats() -> (usedMB: Int, totalMB: Int, percent: Double, pressurePercent: Double, wiredMB: Int, wiredPercent: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / (1024 * 1024))
        guard result == KERN_SUCCESS else { return (0, totalMB, 0.0, 0.0, 0, 0.0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        let usedMB = Int(usedBytes / (1024 * 1024))
        let percent = (Double(usedBytes) / Double(totalBytes)) * 100.0
        let pressurePercent = (Double(wired + compressed) / Double(totalBytes)) * 100.0
        let wiredMB = Int(wired / (1024 * 1024))
        let wiredPercent = (Double(wired) / Double(totalBytes)) * 100.0

        return (usedMB, totalMB, percent, min(100.0, pressurePercent), wiredMB, wiredPercent)
    }

    public func getMemoryPressure() -> (level: Int, swapMB: Int) {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        var swapUsedMB = 0
        var buf = [UInt64](repeating: 0, count: 4)
        var bufSize = buf.count * MemoryLayout<UInt64>.size
        if sysctlbyname("vm.swapusage", &buf, &bufSize, nil, 0) == 0 {
            if buf.count >= 3 {
                swapUsedMB = Int(buf[2] / (1024 * 1024))
            }
        }
        return (Int(level), swapUsedMB)
    }

    private func readSysctlInt(_ name: String) -> Int {
        var val32: Int32 = 0
        var size32 = MemoryLayout<Int32>.size
        if sysctlbyname(name, &val32, &size32, nil, 0) == 0 {
            return Int(val32)
        }
        var val64: Int64 = 0
        var size64 = MemoryLayout<Int64>.size
        if sysctlbyname(name, &val64, &size64, nil, 0) == 0 {
            return Int(val64)
        }
        return 0
    }

    // 核心修复：优先从文件名提取真实的崩溃时间（如 2026-11-16-082719），绝不被系统归档改写 mtime 误导
    private func parseDiagnosticReportDate(filename: String, fullPath: String, formatter: DateFormatter) -> Date? {
        if let range = filename.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) {
            let dateStr = String(filename[range])
            if let parsed = formatter.date(from: dateStr) {
                return parsed
            }
        }
        // 兜底：若文件名无时间戳，只取文件创建时间 (creationDate)，不取会被 _analyticsd 改写的 modificationDate
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) {
            return attrs[.creationDate] as? Date
        }
        return nil
    }

    private func getRecentDiagnosticAlertsCount(bootDate: Date) -> Int {
        let now = Date()
        if now.timeIntervalSince(lastAlertCheckTime) < alertCheckInterval {
            return cachedRecentAlerts
        }

        let dirPath = "/Library/Logs/DiagnosticReports"
        let cutoff = max(bootDate, now.addingTimeInterval(-86400))
        var alertCount = 0

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        if let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
            for name in files {
                let isJetsam = name.hasPrefix("JetsamEvent-") && name.hasSuffix(".diag")
                let isWatchdog = name.contains("userspace_watchdog_timeout") && name.hasSuffix(".spin")
                let isPanic = name.hasSuffix(".panic")

                if isJetsam || isWatchdog || isPanic {
                    let fullPath = dirPath + "/" + name
                    if let eventDate = parseDiagnosticReportDate(filename: name, fullPath: fullPath, formatter: formatter),
                       eventDate > cutoff {
                        alertCount += 1
                    }
                }
            }
        }

        cachedRecentAlerts = alertCount
        lastAlertCheckTime = now
        return alertCount
    }

    private func calculateRecentMbufLimDelta(currentLim: Int) -> Int {
        let now = Date()
        if lastMbufLimReached == nil || now.timeIntervalSince(lastMbufSampleTime) > 10.0 {
            lastMbufLimReached = currentLim
            lastMbufSampleTime = now
            recentMbufBurstSamples.removeAll()
            return 0
        }

        let prev = lastMbufLimReached ?? currentLim
        let delta = currentLim >= prev ? (currentLim - prev) : 0
        lastMbufLimReached = currentLim
        lastMbufSampleTime = now

        if delta > 0 {
            recentMbufBurstSamples.append((time: now, delta: delta))
        }
        recentMbufBurstSamples.removeAll { now.timeIntervalSince($0.time) > 60.0 }

        return recentMbufBurstSamples.reduce(0) { $0 + $1.delta }
    }

    public func getKernelHealth(wiredMB: Int, wiredPercent: Double, bootDate: Date) -> KernelHealthInfo {
        let limReached = readSysctlInt("kern.ipc.sbmb_limreached")
        let recent60s = calculateRecentMbufLimDelta(currentLim: limReached)

        return KernelHealthInfo(
            wiredMB: wiredMB,
            wiredPercent: wiredPercent,
            openFiles: readSysctlInt("kern.num_files"),
            maxFiles: readSysctlInt("kern.maxfiles"),
            maxProc: readSysctlInt("kern.maxproc"),
            mbufLimReached: limReached,
            mbufLimRecent60s: recent60s,
            mbufCount: readSysctlInt("kern.ipc.sbmb_cnt"),
            zleakActive: readSysctlInt("kern.zleak.active"),
            recentAlerts: getRecentDiagnosticAlertsCount(bootDate: bootDate)
        )
    }

    public func getNetworkThroughput() -> (rxSec: UInt64, txSec: UInt64, totalRx: UInt64, totalTx: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0, 0, 0) }

        var buffer = [Int8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0 else { return (0, 0, 0, 0) }

        var currentRx: UInt64 = 0
        var currentTx: UInt64 = 0

        buffer.withUnsafeBufferPointer { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            var cursor = base
            let end = cursor.advanced(by: len)

            while cursor < end && cursor.distance(to: end) >= MemoryLayout<if_msghdr>.size {
                let msgHdr = cursor.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
                if msgHdr.ifm_msglen == 0 { break }

                if msgHdr.ifm_type == RTM_IFINFO2 && cursor.distance(to: end) >= MemoryLayout<if_msghdr2>.size {
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
                    let isExternal = (mntOn != "/")
                    let smart = getSmartStatusSafely(mountPoint: mntOn, bsdName: devName, isExternal: isExternal, now: now)

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

    private func getSmartStatusSafely(mountPoint: String, bsdName: String, isExternal: Bool, now: Date) -> String {
        if isExternal, let cached = smartCache[mountPoint], now.timeIntervalSince(cached.checkedAt) < externalSmartInterval {
            return cached.status
        }

        let status = queryIOKitSmartStatus(forBSDName: bsdName, fallbackCache: smartCache[mountPoint]?.status)
        if status != "待机" {
            smartCache[mountPoint] = (status: status, checkedAt: now)
        }
        return status
    }

    private func isEntryAsleep(_ entry: io_registry_entry_t) -> Bool {
        guard entry != 0 else { return false }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let pm = dict["IOPowerManagement"] as? [String: Any] else {
            return false
        }
        if let currentPower = pm["CurrentPowerState"] as? Int,
           let maxPower = pm["MaxPowerState"] as? Int,
           currentPower < maxPower {
            return true
        }
        if let devPower = pm["DevicePowerState"] as? Int, devPower == 0 {
            return true
        }
        return false
    }

    private func queryIOKitSmartStatus(forBSDName bsdName: String, fallbackCache: String?) -> String {
        guard !bsdName.isEmpty,
              let match = IOBSDNameMatching(kIOMasterPortDefault, 0, bsdName) else {
            return fallbackCache ?? "不支持"
        }
        var current = IOServiceGetMatchingService(kIOMasterPortDefault, match)
        if current == 0 { return fallbackCache ?? "不支持" }

        var depth = 0
        while current != 0 && depth < 16 {
            if IOObjectConformsTo(current, "IOBlockStorageDevice") != 0 {
                var parent: io_registry_entry_t = 0
                let hasParent = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == kIOReturnSuccess
                let asleep = isEntryAsleep(current) || (hasParent && isEntryAsleep(parent))
                if hasParent { IOObjectRelease(parent) }

                if asleep {
                    IOObjectRelease(current)
                    return fallbackCache ?? "待机"
                }

                let code = csmart_check_service(current)
                IOObjectRelease(current)
                if code == 1 { return "良好" }
                if code == 2 { return "故障" }
                return fallbackCache ?? "不支持"
            }

            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr != kIOReturnSuccess { break }
            current = parent
            depth += 1
        }
        if current != 0 { IOObjectRelease(current) }
        return fallbackCache ?? "不支持"
    }

    public func getRealTopProcesses() -> (top: [TopProcess], processCount: Int) {
        let now = Date()
        if now.timeIntervalSince(lastProcessCheckTime) < processInterval && !cachedTopProcesses.isEmpty {
            return (cachedTopProcesses, cachedProcessCount)
        }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Aceo", "%cpu,rss,comm", "-m"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return (cachedTopProcesses, cachedProcessCount)
        }

        var result: [TopProcess] = []
        let lines = output.components(separatedBy: "\n")
        let totalCount = max(0, lines.count - 2)

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

        cachedTopProcesses = result
        cachedProcessCount = totalCount
        lastProcessCheckTime = now

        return (result, totalCount)
    }

    public func collectPayload() -> MetricsPayload {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        sysctl(&mib, 2, &bootTime, &size, nil, 0)
        let nowSec = time(nil)
        let uptime = max(0, Int(nowSec - bootTime.tv_sec))
        let bootDate = Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))

        let cpu = getCPUUsage()
        let mem = getMemoryStats()
        let memPressure = getMemoryPressure()
        let net = getNetworkThroughput()
        let disk = getDiskThroughput()
        let temp = SMCReader.shared.getCPUTemperature()
        let power = SMCReader.shared.getSystemPower()
        let processData = getRealTopProcesses()
        let volumes = getDiskVolumesCached()
        let kernelHealth = getKernelHealth(wiredMB: mem.wiredMB, wiredPercent: mem.wiredPercent, bootDate: bootDate)

        var load = [Double](repeating: 0.0, count: 3)
        getloadavg(&load, 3)

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
            processCount: processData.processCount,
            topProcesses: processData.top,
            diskVolumes: volumes,
            kernelHealth: kernelHealth
        )
    }
}
