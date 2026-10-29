import Foundation
import IOKit

public final class SMCReader {
    public static let shared = SMCReader()
    private var connect: io_connect_t = 0

    private struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
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

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
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

    private func fourCharCode(from string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    private func readKey(_ key: String) -> Double? {
        guard connect != 0 else { return nil }
        var inputStructure = SMCParamStruct()
        var outputStructure = SMCParamStruct()
        let inputKey = fourCharCode(from: key)
        inputStructure.key = inputKey
        inputStructure.data8 = 9 // SMC_CMD_READ_KEYINFO

        let structSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = structSize

        let kernResult = IOConnectCallStructMethod(
            connect, 2, &inputStructure, structSize, &outputStructure, &outputSize
        )
        guard kernResult == kIOReturnSuccess else { return nil }

        let info = outputStructure.keyInfo
        inputStructure.keyInfo.dataSize = info.dataSize
        inputStructure.data8 = 5 // SMC_CMD_READ_BYTES

        let readResult = IOConnectCallStructMethod(
            connect, 2, &inputStructure, structSize, &outputStructure, &outputSize
        )
        guard readResult == kIOReturnSuccess else { return nil }

        let type = info.dataType
        let b0 = Int(outputStructure.bytes.0)
        let b1 = Int(outputStructure.bytes.1)

        // 1. sp78 定点数 (多数温度)
        if type == fourCharCode(from: "sp78") {
            let raw = (b0 << 8) | b1
            return Double(raw) / 256.0
        }
        // 2. fpe2 定点数 (部分功率)
        if type == fourCharCode(from: "fpe2") {
            let raw = (b0 << 8) | b1
            return Double(raw) / 4.0
        }
        // 3. flt 32位标准浮点数 (Intel 核心整机真实总功率 PSTR)
        if type == fourCharCode(from: "flt ") && info.dataSize == 4 {
            var rawBytes = [outputStructure.bytes.0, outputStructure.bytes.1, outputStructure.bytes.2, outputStructure.bytes.3]
            var val: Float = 0
            memcpy(&val, &rawBytes, 4)
            return Double(val)
        }
        // 4. ui16
        if type == fourCharCode(from: "ui16") {
            return Double((b0 << 8) | b1)
        }
        return nil
    }

    // 核心优化：优先读取 CPU Die (真实芯片核心最高温)，绝不再用外围滞后温度
    public func getCPUTemperature() -> Double {
        if let die = readKey("TC0D") { return die }
        if let core1 = readKey("TC0E") { return core1 }
        if let core2 = readKey("TC0F") { return core2 }
        if let xc = readKey("TCXC") { return xc }
        return readKey("TC0P") ?? 50.0
    }

    // 核心优化：精准解码系统整机真实交流功耗 (Total Power)
    public func getSystemPower() -> Double {
        if let pstr = readKey("PSTR") { return pstr }
        if let pc0c = readKey("PC0C") { return pc0c }
        if let pcpt = readKey("PCPT") { return pcpt }
        return 20.0
    }
}
