import Testing
@testable import DevBar

struct MacSystemMetricsProviderTests {
    @Test func memoryPercentExcludesReclaimableFileCache() throws {
        let gibibyte = UInt64(1_073_741_824)
        let pageSize = UInt64(16_384)
        let totalBytes = 32 * gibibyte
        let cachedBytes = UInt64(7.77 * Double(gibibyte))
        let freeBytes = UInt64(0.12 * Double(gibibyte))

        let percent = try #require(MacSystemMetricsProvider.memoryPercent(
            totalBytes: totalBytes,
            pageSize: pageSize,
            freePageCount: freeBytes / pageSize,
            fileBackedPageCount: cachedBytes / pageSize,
            purgeablePageCount: 0
        ))

        #expect(percent == 75)
    }

    @Test func memoryPercentReturnsNilWithoutPhysicalMemory() {
        #expect(MacSystemMetricsProvider.memoryPercent(
            totalBytes: 0,
            pageSize: 16_384,
            freePageCount: 1,
            fileBackedPageCount: 1,
            purgeablePageCount: 1
        ) == nil)
    }

    @Test func memoryPercentClampsInvalidReclaimableTotal() {
        #expect(MacSystemMetricsProvider.memoryPercent(
            totalBytes: 1_024,
            pageSize: 1_024,
            freePageCount: 1,
            fileBackedPageCount: 1,
            purgeablePageCount: 1
        ) == 0)
    }
}
