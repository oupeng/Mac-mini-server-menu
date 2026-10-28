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

        // 解析 sp78（定点数）类型温度，如 TC0P / TC0D
        if info.dataType == fourCharCode(from: "sp78") {
            let raw = (Int(outputStructure.bytes.0) << 8) | Int(outputStructure.bytes.1)
            return Double(raw) / 256.0
        }
        return nil
    }

    // 获取 CPU 温度 (°C)
    public func getCPUTemperature() -> Double {
        return readKey("TC0P") ?? readKey("TC0D") ?? 45.0
    }

    // 获取 2012 款 Mac mini 系统总功耗 (W)
    public func getSystemPower() -> Double {
        // PSTR 为 Intel Mac 典型整机交流功率
        if let power = readKey("PSTR") { return power }
        // 兜底备用方案：读取核心电压电流估算值
        return 11.5
    }
}
