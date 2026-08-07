import Testing
@testable import DevBar

@MainActor
struct QuotaProgressBarTests {
    @Test func progressBandsHonorThresholdBoundaries() {
        #expect(QuotaProgressBand(percentage: 49) == .normal)
        #expect(QuotaProgressBand(percentage: 50) == .warning)
        #expect(QuotaProgressBand(percentage: 79) == .warning)
        #expect(QuotaProgressBand(percentage: 80) == .critical)
        #expect(QuotaProgressBand(percentage: 82) == .critical)
    }

    @Test func progressValueIsClampedToRenderableRange() {
        #expect(QuotaProgressBar(percentage: -1).clampedPercentage == 0)
        #expect(QuotaProgressBar(percentage: 82).clampedPercentage == 82)
        #expect(QuotaProgressBar(percentage: 101).clampedPercentage == 100)
    }
}
