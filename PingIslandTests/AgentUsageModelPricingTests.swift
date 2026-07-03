import XCTest
@testable import Ping_Island

final class AgentUsageModelPricingTests: XCTestCase {
    func testNilOrEmptyModelMapsToUnknownWithBlend() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: nil), "unknown")
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "   "), "unknown")
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: nil), "未知模型")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: nil).inputUSDPerMillion, 2.375, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: nil).outputUSDPerMillion, 14.5, accuracy: 0.000_001)
    }

    func testFableAndMythosMapping() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-fable-5"), "fable-5")
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-mythos-5-20260301"), "mythos-5")
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "claude-fable-5"), "Fable 5")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-fable-5").inputUSDPerMillion, 10, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-mythos-5").outputUSDPerMillion, 50, accuracy: 0.000_001)
    }

    func testOpusMinorVersionMapping() {
        // minor 5-8 → opus-4.<minor>，5/25
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4-8"), "opus-4.8")
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4-8-20260101"), "opus-4.8")
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4-5"), "opus-4.5")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-opus-4-8").inputUSDPerMillion, 5, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-opus-4-8").outputUSDPerMillion, 25, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "claude-opus-4-8-20260101"), "Opus 4.8")
        // minor 1 → opus-4.1，15/75
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4-1-20250805"), "opus-4.1")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-opus-4-1-20250805").inputUSDPerMillion, 15, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "claude-opus-4-1-20250805"), "Opus 4.1")
        // 「4-」後直接接長數字（日期後綴）= 4.0，15/75
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4-20250514"), "opus-4.0")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-opus-4-20250514").outputUSDPerMillion, 75, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "claude-opus-4-20250514"), "Opus 4")
        // 無法判定 → opus-4.x，5/25
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-opus-4"), "opus-4.x")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-opus-4").inputUSDPerMillion, 5, accuracy: 0.000_001)
    }

    func testSonnetMapping() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-sonnet-5-20260401"), "sonnet-5")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-sonnet-5").inputUSDPerMillion, 2, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-sonnet-5").outputUSDPerMillion, 10, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-sonnet-4-5-20250929"), "sonnet-4.5")
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-sonnet-4-6"), "sonnet-4.6")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-sonnet-4-6").outputUSDPerMillion, 15, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-sonnet-3-7"), "sonnet")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-sonnet-3-7").inputUSDPerMillion, 3, accuracy: 0.000_001)
    }

    func testHaikuMapping() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "claude-haiku-4-5-20251001"), "haiku-4.5")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-haiku-4-5-20251001").inputUSDPerMillion, 1, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "claude-haiku-4-5-20251001").outputUSDPerMillion, 5, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testGPTMapping() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.5"), "gpt-5.5")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.5").inputUSDPerMillion, 5, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.5").outputUSDPerMillion, 30, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.5-pro"), "gpt-5.5-pro")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.5-pro").inputUSDPerMillion, 30, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.4-pro"), "gpt-5.4-pro")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.4-pro").outputUSDPerMillion, 180, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.4"), "gpt-5.4")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.4").inputUSDPerMillion, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.4-mini"), "gpt-5.4-mini")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.4-mini").outputUSDPerMillion, 4.5, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.4-nano"), "gpt-5.4-nano")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.4-nano").inputUSDPerMillion, 0.2, accuracy: 0.000_001)
        // Symmetric: mini/nano are only listed for 5.4; a 5.5 mini/nano is NOT listed → blend
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5.5-mini"), "unknown:gpt-5.5-mini")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5.5-mini").inputUSDPerMillion, 2.375, accuracy: 0.000_001)
        // 其餘 gpt（含 gpt-5-codex、未列版本）→ unknown:<raw>，blend
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "gpt-5-codex"), "unknown:gpt-5-codex")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "gpt-5-codex").inputUSDPerMillion, 2.375, accuracy: 0.000_001)
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "gpt-5-codex"), "gpt-5-codex")
    }

    func testUnrecognizedModelKeepsRawIdentity() {
        XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: "Gemini-3-Pro"), "unknown:gemini-3-pro")
        XCTAssertEqual(AgentUsageModelPricing.displayName(forModel: "Gemini-3-Pro"), "gemini-3-pro")
        XCTAssertEqual(AgentUsageModelPricing.pricing(forModel: "Gemini-3-Pro").outputUSDPerMillion, 14.5, accuracy: 0.000_001)
    }

    func testNormalizedKeyIsIdempotentAndDisplayNameIsPureFunctionOfKey() {
        let rawIDs = [
            "claude-opus-4-8", "claude-opus-4-8-20260101", "claude-opus-4-1-20250805",
            "claude-opus-4-20250514", "claude-sonnet-5", "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001", "claude-fable-5", "gpt-5.5", "gpt-5.4-mini",
            "gpt-5-codex", "totally-new-model", "",
        ]
        for raw in rawIDs {
            let key = AgentUsageModelPricing.normalizedKey(forModel: raw)
            XCTAssertEqual(AgentUsageModelPricing.normalizedKey(forModel: key), key, "key not idempotent for \(raw)")
            XCTAssertEqual(
                AgentUsageModelPricing.displayName(forModel: raw),
                AgentUsageModelPricing.displayName(forModel: key),
                "displayName must be a pure function of the normalized key for \(raw)"
            )
        }
    }

    func testPricingKeepsExistingCacheMultipliers() {
        let pricing = AgentUsageModelPricing.pricing(forModel: "claude-opus-4-8")
        XCTAssertEqual(pricing.cacheCreationMultiplier, 1.25, accuracy: 0.000_001)
        XCTAssertEqual(pricing.cacheReadMultiplier, 0.1, accuracy: 0.000_001)
    }

    func testEstimateUSDPerModelSumsOfficialRates() {
        let cost = AgentUsageModelPricing.estimateUSD(perModel: [
            "opus-4.8": AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000),   // 5 + 25 = 30
            "haiku-4.5": AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000),  // 1 + 5 = 6
        ])
        XCTAssertEqual(cost, 36.0, accuracy: 0.000_001)
    }
}
