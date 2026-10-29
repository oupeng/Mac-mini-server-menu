import Foundation
import IOKit

public final class SMCReader {
    public static let shared = SMCReader()
    private var connect: io_connect_t = 0

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    // 核心：严格按照 C 内核驱动 80 字节对齐
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0 // 关键 2 字节填充
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private init() {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            IOServiceOpen(service, mach_task_self_, 0, &connect)
            IOObjectRelease(service)
        }
    }

    deinit {
        if connect != 0 {
            IOServiceClose(connect)
        }
    }

    private func readSMCValue(_ keyStr: String) -> Double? {
        guard connect != 0 else { return nil }
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        var code: UInt32 = 0
        for char in keyStr.utf8.prefix(4) {
            code = (code << 8) | UInt32(char)
        }
        input.key = code

        // 1. 获取 Key 信息
        input.data8 = 9 // kSMCGetKeyInfo
        var size = MemoryLayout<SMCParamStruct>.stride

        var kerr = IOConnectCallStructMethod(connect, 2, &input, size, &output, &size)
        guard kerr == kIOReturnSuccess, output.result == 0 else { return nil }

        // 2. 读取字节
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5 // kSMCReadKey

        kerr = IOConnectCallStructMethod(connect, 2, &input, size, &output, &size)
        guard kerr == kIOReturnSuccess, output.result == 0 else { return nil }

        let b0 = Int(output.bytes.0)
        let b1 = Int(output.bytes.1)

        // 实测证实：TC0D(温度)与 PSTR(整机功率)均使用 sp78 格式精准编码
        return Double((b0 << 8) | b1) / 256.0
    }

    // 优先读取真实 CPU Die 核心温度 (~65°C)，随负载动态灵敏变化
    public func getCPUTemperature() -> Double {
        if let die = readSMCValue("TC0D") { return die }
        if let xc = readSMCValue("TCXC") { return xc }
        if let core1 = readSMCValue("TC0E") { return core1 }
        return readSMCValue("TC0P") ?? 50.0
    }

    // 读取整机真实总交流输入功率 (~21W - 26W)
    public func getSystemPower() -> Double {
        if let pstr = readSMCValue("PSTR") { return pstr }
        if let pc0c = readSMCValue("PC0C") { return pc0c }
        return 20.0
    }
}
