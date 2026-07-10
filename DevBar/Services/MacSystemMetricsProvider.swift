import Darwin
import Foundation

struct MacSystemMetricsSnapshot: Sendable, Equatable {
    let cpuPercent: Int?
    let memoryPercent: Int?
    let networkDownBytesPerSecond: Int?
    let networkUpBytesPerSecond: Int?
}

final class MacSystemMetricsProvider {
    static let shared = MacSystemMetricsProvider()

    private var previousCPU: CPUSample?
    private var previousNetwork: NetworkSample?

    private init() {}

    func snapshot() -> MacSystemMetricsSnapshot {
        let network = networkSpeeds()
        return MacSystemMetricsSnapshot(
            cpuPercent: cpuPercent(),
            memoryPercent: memoryPercent(),
            networkDownBytesPerSecond: network?.downBytesPerSecond,
            networkUpBytesPerSecond: network?.upBytesPerSecond
        )
    }

    private func cpuPercent() -> Int? {
        guard let sample = currentCPUSample() else { return nil }
        defer { previousCPU = sample }

        guard let previousCPU else { return nil }
        let totalDelta = sample.total - previousCPU.total
        guard totalDelta > 0 else { return nil }

        let activeDelta = sample.active - previousCPU.active
        let percent = Double(activeDelta) / Double(totalDelta) * 100
        return clampedPercent(percent)
    }

    private func currentCPUSample() -> CPUSample? {
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var active: UInt64 = 0
        var total: UInt64 = 0
        for cpuIndex in 0..<Int(processorCount) {
            let offset = cpuIndex * Int(CPU_STATE_MAX)
            let user = UInt64(processorInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)])
            active += user + system + nice
            total += user + system + nice + idle
        }
        return CPUSample(active: active, total: total)
    }

    private func memoryPercent() -> Int? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = used + free
        guard total > 0 else { return nil }

        return clampedPercent(Double(used) / Double(total) * 100)
    }

    private func networkSpeeds() -> (downBytesPerSecond: Int?, upBytesPerSecond: Int?)? {
        guard let sample = currentNetworkSample() else { return nil }
        defer { previousNetwork = sample }

        guard let previousNetwork else { return (nil, nil) }
        let elapsed = sample.date.timeIntervalSince(previousNetwork.date)
        guard elapsed > 0 else { return (nil, nil) }

        let downDelta = sample.downBytes >= previousNetwork.downBytes
            ? sample.downBytes - previousNetwork.downBytes
            : 0
        let upDelta = sample.upBytes >= previousNetwork.upBytes
            ? sample.upBytes - previousNetwork.upBytes
            : 0
        return (
            downBytesPerSecond: Int(Double(downDelta) / elapsed),
            upBytesPerSecond: Int(Double(upDelta) / elapsed)
        )
    }

    private func currentNetworkSample() -> NetworkSample? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var downBytes: UInt64 = 0
        var upBytes: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard let address = current.pointee.ifa_addr,
                  flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = current.pointee.ifa_data else {
                continue
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            downBytes += UInt64(interfaceData.ifi_ibytes)
            upBytes += UInt64(interfaceData.ifi_obytes)
        }
        return NetworkSample(date: Date(), downBytes: downBytes, upBytes: upBytes)
    }

    private func clampedPercent(_ value: Double) -> Int {
        min(max(Int(value.rounded()), 0), 100)
    }

    private struct CPUSample {
        let active: UInt64
        let total: UInt64
    }

    private struct NetworkSample {
        let date: Date
        let downBytes: UInt64
        let upBytes: UInt64
    }
}
