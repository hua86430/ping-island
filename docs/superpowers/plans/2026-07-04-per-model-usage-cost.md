# 逐模型用量與花費 implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal**：統計頁的 token 用量與花費從單一 blend 費率改為逐模型（per-model）計算。Claude transcript 逐行依 `message.model` 分桶、Codex rollout 逐 thread 掛 model 並拆出 `cached_input_tokens`，每個 model 套各自官方費率，統計頁新增「各模型用量與花費」卡（多線圖 + 清單），既有「Token 費用預估」headline 改用逐 model 加總，升級前舊資料 fallback blend、不歸零。

**Architecture**：spec 選項 B。delta/baseline 引擎維持以 `sourceKey` 為單位，但 `AgentUsageTokenSourceBaseline` 內部改持 `totalsByModel: [String: AgentUsageTokenTotals]`，`recordTokenUsage` 收逐 model 累積 map、對每個 model 各算 delta，累加進 `AgentUsageDailyBucket.tokenTotalsByModel`（同時維護 aggregate `tokenTotals`）。`makeSnapshot` 由 bucket map 彙總出 `perModelBreakdown` 與 `perModelDailySpend`，花費採「逐 model 官方費率 + 殘量 blend」。分桶鍵在寫入時以 `AgentUsageModelPricing.normalizedKey` 正規化。

**Tech Stack**：Swift（Xcode 專案 `PingIsland` scheme）、SwiftUI 手刻 `Path` 圖表（不引入 Swift Charts）、XCTest（`PingIslandTests`）、JSON 持久化（`~/.ping-island/usage/agent-usage.json`）。

**Source spec（source of truth）**：`docs/superpowers/specs/2026-07-04-per-model-usage-cost-design.md`。實作前先整份讀完。

## Global Constraints

以下逐字抄自 spec，全程遵守：

1. 架構 B：「選項 B 把 baseline 內部改成逐 model：`AgentUsageTokenSourceBaseline` 持有 `totalsByModel: [String: AgentUsageTokenTotals]`，`recordTokenUsage` 收下逐 model 的當前累積 map、對每個 model 各算 delta。一個來源仍只有一筆 baseline」。且「不 bump `schemaVersion`、不清舊資料」。
2. 不變式：「`tokenTotals` 恆等於 `tokenTotalsByModel` 各值之和（就升級後寫入的資料而言）」。
3. delta 兩分支規則：「整份 baseline map 為空（legacy / 首見）走 first-sight，`recordInitialSnapshot:false` 時只 seed 不記 delta，避免把整份 transcript 歷史 dump 進當日；而『非空 map 缺單一鍵』代表同來源中途冒出新 model（如主線 opus 後出現 subagent haiku），該鍵全額計入才正確。兩者語意不同，不可混用。」
4. Codex model 鍵穩定（fable5 3b BLOCKER）：「`recordCodexUsageSnapshot` 解析鍵時，`snapshot.model` 為 nil 就沿用該 sourceKey 既有 baseline 的唯一 model 鍵（Codex baseline map 恆單鍵）；連前次鍵都沒有才用 `unknown`。如此同一 thread 的鍵不會翻轉。」
5. i18n：「所有新字串 key 沿專案慣例用簡體識別碼，en.lproj / zh-Hant.lproj 兩表都補值（zh-Hant 值必為繁體）。」
6. 費率結構：「`AgentUsageTokenPricing` 結構不動（`inputUSDPerMillion`、`outputUSDPerMillion`、`cacheCreationMultiplier = 1.25`、`cacheReadMultiplier = 0.1`）」，沿用既有 struct，不另造。
7. 分桶鍵：「鍵保留版本、只剝日期後綴」（`opus-4.8` 與 `opus-4.5` 分開；`claude-opus-4-8` 與 `claude-opus-4-8-20260101` 歸同鍵）。「`displayName` 是正規化鍵的決定性純函式」，不看「第一次見到」。
8. `AgentUsageDocument.init` 遷移迴圈：「遷移一律建成空 map（`totalsByModel: [:]`），空 map 走 first-sight 分支即安全」。

工程約束：

- 本機無簽章憑證，所有 xcodebuild 一律帶 `CODE_SIGNING_ALLOWED=NO`。
  - 單元測試：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
  - 建置：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- 若用管線（如 `| tail`、`| grep`）過濾 xcodebuild 輸出，或在背景執行後檢查結果，必須驗證 xcodebuild 本身的 exit code（bash 為 `${PIPESTATUS[0]}`、zsh 為 `${pipestatus[1]}`），不能拿尾端 grep 的 exit code 當成功依據。
- 專案用 Xcode filesystem-synchronized groups（`objectVersion = 77`），在 `PingIsland/`、`PingIslandTests/` 下新增 `.swift` 檔會自動進 target，不需要編輯 pbxproj。
- 非 UI 層（pricing、loader、store）不得呼叫 `AppLocalization`；`displayName` 對未知模型回傳簡體 i18n key 字串（如 `未知模型`），由 UI 以 `Text(appLocalized:)` 渲染。
- commit message 用英文 Conventional Commits。

任務順序相對 spec 檔案清單做了收斂：baseline 結構、`recordTokenUsage` 簽章、兩處 callsite（`recordCodexUsageSnapshot`、`SessionStore`）必須同 commit 才能編譯，合併為 Task 5；因此 Claude loader（Task 3）與 Codex model 掃描（Task 4）提前，讓 Task 5 改 callsite 時能直接傳真實逐 model map，避免中間 commit 出現 `unknown` 鍵翻轉造成雙計。

## File structure

| 檔案 | 動作 | 職責 |
|---|---|---|
| `PingIsland/Services/Usage/AgentUsageModelPricing.swift` | 新增 | 逐模型官方費率註冊表、`normalizedKey` / `pricing` / `displayName` / `estimateUSD(perModel:)` |
| `PingIsland/Services/Usage/AgentUsageAnalytics.swift` | 修改 | bucket 逐 model 儲存、baseline `totalsByModel`、`recordTokenUsage` 逐 model delta、`recordCodexUsageSnapshot` 鍵穩定、`CodexTokenUsage.cachedInputTokens`、snapshot 新欄位與殘量計價 |
| `PingIsland/Services/Usage/ClaudeTranscriptUsage.swift` | 修改 | 逐行取 `message.model` 分桶，snapshot 加 `tokenTotalsByModel` |
| `PingIsland/Services/Usage/CodexUsage.swift` | 修改 | `cached_input_tokens` 讀取、`turn_context.payload.model` 掃描、`CodexUsageSnapshot.model` Codable |
| `PingIsland/Services/State/SessionStore.swift` | 修改 | `recordClaudeFamilyTranscriptUsageIfAvailable` 改傳 `totalsByModel` |
| `PingIsland/UI/Views/Settings/Categories/AgentUsagePerModelViews.swift` | 新增 | `AgentUsagePerModelPanel` / `AgentUsagePerModelSpendChart` / `AgentUsageModelBreakdownList` |
| `PingIsland/UI/Views/Settings/Categories/AnalyticsSettingsView.swift` | 修改 | 在 spendCard 與 activityMapCard 之間插入新卡；傳 `usesPerModelPricing` 給 spend panel |
| `PingIsland/UI/Views/Settings/Categories/AgentUsageRows.swift` | 修改 | `AgentUsageSpendFooter` pricing label 改「按模型官方定价」（有逐 model 資料時） |
| `PingIsland/Resources/en.lproj/Localizable.strings` | 修改 | 6 個新 key 的英文值 |
| `PingIsland/Resources/zh-Hant.lproj/Localizable.strings` | 修改 | 6 個新 key 的繁體值 |
| `PingIslandTests/AgentUsageModelPricingTests.swift` | 新增 | 正規化每條規則、費率、displayName 純函式、`estimateUSD(perModel:)` |
| `PingIslandTests/AgentUsageAnalyticsTests.swift` | 修改 | bucket / baseline / delta / 遷移 / snapshot 新欄位 / 殘量計價測試 |
| `PingIslandTests/ClaudeTranscriptUsageLoaderTests.swift` | 修改 | 混 model 分桶測試、`recordTokenUsage` 新簽章 |
| `PingIslandTests/CodexUsageLoaderTests.swift` | 修改 | cached 拆分、turn_context model 掃描、snapshot Codable 相容 |
| `AGENTS.md` | 修改 | Usage 段落補逐模型計價入口（收尾） |
| `docs/superpowers/specs/2026-07-04-per-model-usage-cost-design.md` | 修改 | 實作完成後把狀態改為已實作（收尾） |

---

### Task 1: AgentUsageModelPricing 費率註冊表與 model id 正規化

**Files**

- Create: `PingIsland/Services/Usage/AgentUsageModelPricing.swift`
- Create: `PingIslandTests/AgentUsageModelPricingTests.swift`

**Interfaces**

- Consumes：`AgentUsageTokenTotals`、`AgentUsageTokenPricing`、`AgentUsageCostEstimator.blendedCodexClaudePricing`（`AgentUsageAnalytics.swift:33-218`，不動）。
- Produces：

```swift
enum AgentUsageModelPricing {
    nonisolated static func normalizedKey(forModel rawModel: String?) -> String
    nonisolated static func pricing(forModel rawModel: String?) -> AgentUsageTokenPricing
    nonisolated static func displayName(forModel rawModel: String?) -> String
    nonisolated static func estimateUSD(perModel totalsByModel: [String: AgentUsageTokenTotals]) -> Double
}
```

設計要點（超出 spec 字面、實作時必守）：`makeSnapshot` 會拿「已正規化的鍵」再呼叫 `displayName(forModel:)` / `pricing(forModel:)`，所以 `normalizedKey` 必須冪等：已是註冊表鍵或 `unknown` / `unknown:` 前綴者直接原樣通過，否則 `opus-4.8` 這種鍵會被 prefix 規則誤判成 `unknown:opus-4.8`。

**Steps**

- [x] 寫失敗測試 `PingIslandTests/AgentUsageModelPricingTests.swift`（覆蓋 spec「model id 正規化規則」每一條與 fallback）：

```swift
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
```

- [x] 跑測試確認編譯失敗（型別不存在即為預期失敗）：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageModelPricingTests`
- [x] 建立 `PingIsland/Services/Usage/AgentUsageModelPricing.swift`，最小實作：

```swift
import Foundation

// Per-model official list prices (USD per million tokens).
// Bucketing keys are normalized at WRITE time: keep the version, strip the date suffix.
enum AgentUsageModelPricing {
    private struct Entry {
        let displayName: String
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    // ponytail: Sonnet 5 rate is the pre-2026-09-01 list price; make date-aware if the switch materially skews history
    private nonisolated static let entries: [String: Entry] = [
        "fable-5": Entry(displayName: "Fable 5", inputUSDPerMillion: 10, outputUSDPerMillion: 50),
        "mythos-5": Entry(displayName: "Mythos 5", inputUSDPerMillion: 10, outputUSDPerMillion: 50),
        "opus-4.5": Entry(displayName: "Opus 4.5", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.6": Entry(displayName: "Opus 4.6", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.7": Entry(displayName: "Opus 4.7", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.8": Entry(displayName: "Opus 4.8", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.x": Entry(displayName: "Opus 4.x", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.0": Entry(displayName: "Opus 4", inputUSDPerMillion: 15, outputUSDPerMillion: 75),
        "opus-4.1": Entry(displayName: "Opus 4.1", inputUSDPerMillion: 15, outputUSDPerMillion: 75),
        "sonnet-5": Entry(displayName: "Sonnet 5", inputUSDPerMillion: 2, outputUSDPerMillion: 10),
        "sonnet-4.5": Entry(displayName: "Sonnet 4.5", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "sonnet-4.6": Entry(displayName: "Sonnet 4.6", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "sonnet": Entry(displayName: "Sonnet", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "haiku-4.5": Entry(displayName: "Haiku 4.5", inputUSDPerMillion: 1, outputUSDPerMillion: 5),
        "gpt-5.5": Entry(displayName: "GPT-5.5", inputUSDPerMillion: 5, outputUSDPerMillion: 30),
        "gpt-5.5-pro": Entry(displayName: "GPT-5.5 pro", inputUSDPerMillion: 30, outputUSDPerMillion: 180),
        "gpt-5.4-pro": Entry(displayName: "GPT-5.4 pro", inputUSDPerMillion: 30, outputUSDPerMillion: 180),
        "gpt-5.4": Entry(displayName: "GPT-5.4", inputUSDPerMillion: 2.5, outputUSDPerMillion: 15),
        "gpt-5.4-mini": Entry(displayName: "GPT-5.4 mini", inputUSDPerMillion: 0.75, outputUSDPerMillion: 4.5),
        "gpt-5.4-nano": Entry(displayName: "GPT-5.4 nano", inputUSDPerMillion: 0.2, outputUSDPerMillion: 1.25),
    ]

    nonisolated static func normalizedKey(forModel rawModel: String?) -> String {
        guard let raw = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return "unknown"
        }
        // Idempotence: already-normalized keys (registry keys, unknown, unknown:<raw>)
        // pass straight through, so pricing/displayName accept keys as well as raw ids.
        if raw == "unknown" || raw.hasPrefix("unknown:") || entries[raw] != nil {
            return raw
        }
        if raw.contains("fable") { return "fable-5" }
        if raw.contains("mythos") { return "mythos-5" }
        if raw.hasPrefix("claude-opus") { return opusKey(raw) }
        if raw.hasPrefix("claude-sonnet") { return sonnetKey(raw) }
        if raw.hasPrefix("claude-haiku") { return "haiku-4.5" }
        if raw.hasPrefix("gpt") { return gptKey(raw) }
        return "unknown:\(raw)"
    }

    nonisolated static func pricing(forModel rawModel: String?) -> AgentUsageTokenPricing {
        let key = normalizedKey(forModel: rawModel)
        guard let entry = entries[key] else {
            return AgentUsageCostEstimator.blendedCodexClaudePricing
        }
        return AgentUsageTokenPricing(
            inputUSDPerMillion: entry.inputUSDPerMillion,
            outputUSDPerMillion: entry.outputUSDPerMillion,
            label: entry.displayName
        )
    }

    // Deterministic pure function of the normalized key, never of the first-seen raw id.
    // For "unknown" this returns the Simplified localization key; render via Text(appLocalized:).
    nonisolated static func displayName(forModel rawModel: String?) -> String {
        let key = normalizedKey(forModel: rawModel)
        if let entry = entries[key] { return entry.displayName }
        if key == "unknown" { return "未知模型" }
        if key.hasPrefix("unknown:") { return String(key.dropFirst("unknown:".count)) }
        return key
    }

    nonisolated static func estimateUSD(perModel totalsByModel: [String: AgentUsageTokenTotals]) -> Double {
        totalsByModel.reduce(0) { partial, element in
            partial + pricing(forModel: element.key).estimateUSD(for: element.value)
        }
    }

    private nonisolated static func opusKey(_ raw: String) -> String {
        // claude-opus-4-8 / claude-opus-4-8-20260101 / claude-opus-4-1-20250805 / claude-opus-4-20250514
        let segments = raw.split(separator: "-").map(String.init)
        guard let fourIndex = segments.firstIndex(of: "4"), fourIndex + 1 < segments.count,
              let minor = Int(segments[fourIndex + 1]) else {
            return "opus-4.x"
        }
        if minor >= 1000 { return "opus-4.0" } // date suffix straight after "4" means plain Opus 4
        if (5...8).contains(minor) { return "opus-4.\(minor)" }
        if minor == 0 || minor == 1 { return "opus-4.\(minor)" }
        return "opus-4.x"
    }

    private nonisolated static func sonnetKey(_ raw: String) -> String {
        if raw.hasPrefix("claude-sonnet-5") { return "sonnet-5" }
        if raw.hasPrefix("claude-sonnet-4-5") { return "sonnet-4.5" }
        if raw.hasPrefix("claude-sonnet-4-6") { return "sonnet-4.6" }
        return "sonnet"
    }

    private nonisolated static func gptKey(_ raw: String) -> String {
        // Symmetric: -pro / -mini / -nano are only recognized for the listed 5.4 / 5.5
        // versions. Any other gpt variant (unlisted version, unreleased tier) → blend.
        if raw.hasPrefix("gpt-5.5") {
            if raw.contains("-pro") { return "gpt-5.5-pro" }
            if raw.contains("-mini") || raw.contains("-nano") { return "unknown:\(raw)" } // 5.5 mini/nano not listed
            return "gpt-5.5"
        }
        if raw.hasPrefix("gpt-5.4") {
            if raw.contains("-pro") { return "gpt-5.4-pro" }
            if raw.contains("-mini") { return "gpt-5.4-mini" }
            if raw.contains("-nano") { return "gpt-5.4-nano" }
            return "gpt-5.4"
        }
        return "unknown:\(raw)"
    }
}
```

- [x] 跑測試確認通過：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageModelPricingTests`
- [x] Commit：`feat: add AgentUsageModelPricing registry with per-model official rates`

---

### Task 2: AgentUsageDailyBucket 逐 model 儲存與 recordTokens(perModel:)

**Files**

- Modify: `PingIsland/Services/Usage/AgentUsageAnalytics.swift`（`AgentUsageDailyBucket`，378-415 行）
- Modify: `PingIslandTests/AgentUsageAnalyticsTests.swift`

**Interfaces**

- Produces：

```swift
struct AgentUsageDailyBucket: Codable, Equatable, Sendable {
    var tokenTotalsByModel: [String: AgentUsageTokenTotals]   // 新增，預設 [:]
    nonisolated mutating func recordTokens(perModel deltasByModel: [String: AgentUsageTokenTotals])
}
```

既有 `recordTokens(_ totals:)` 本 task 先保留（`recordTokenUsage` 還在用），Task 5 移除。

**Steps**

- [x] 在 `AgentUsageAnalyticsTests.swift` 加失敗測試：

```swift
    func testDailyBucketRecordTokensPerModelKeepsAggregateInvariant() {
        var bucket = AgentUsageDailyBucket(day: "2026-07-04")

        bucket.recordTokens(perModel: [
            "opus-4.8": AgentUsageTokenTotals(input: 100, cacheCreation: 10, cacheRead: 5, output: 40),
            "haiku-4.5": AgentUsageTokenTotals(input: 20, output: 8),
        ])

        XCTAssertEqual(
            bucket.tokenTotals,
            AgentUsageTokenTotals(input: 120, cacheCreation: 10, cacheRead: 5, output: 48)
        )
        var summed = AgentUsageTokenTotals()
        for totals in bucket.tokenTotalsByModel.values { summed.add(totals) }
        XCTAssertEqual(bucket.tokenTotals, summed, "aggregate must equal the sum of tokenTotalsByModel")
        XCTAssertEqual(bucket.tokenTotalsByModel.count, 2)
        XCTAssertEqual(bucket.activityCount, 1, "one activity per delta batch, not per model")
    }

    func testDailyBucketRecordTokensPerModelSkipsEmptyBatch() {
        var bucket = AgentUsageDailyBucket(day: "2026-07-04")
        bucket.recordTokens(perModel: ["opus-4.8": AgentUsageTokenTotals()])
        XCTAssertEqual(bucket.activityCount, 0)
        XCTAssertTrue(bucket.tokenTotalsByModel.isEmpty)
    }

    func testDailyBucketDecodesLegacyJSONWithoutPerModelMap() throws {
        let legacyJSON = """
        {"day":"2026-07-01","sessionIDsByAgent":{},"toolCounts":{},"tokenTotals":{"input":10,"cacheCreation":0,"cacheRead":0,"output":5},"activityCount":2}
        """
        let bucket = try JSONDecoder().decode(AgentUsageDailyBucket.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(bucket.tokenTotalsByModel, [:])
        XCTAssertEqual(bucket.tokenTotals, AgentUsageTokenTotals(input: 10, output: 5))
        XCTAssertEqual(bucket.activityCount, 2)
    }
```

- [x] 跑測試確認失敗：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageAnalyticsTests`
- [x] 修改 `AgentUsageDailyBucket`：加欄位、自訂 `init(from:)`（舊桶缺 key 解為空 map；有自訂 `CodingKeys` 時 `encode(to:)` 仍可用合成版，不必手寫）、加 `recordTokens(perModel:)`：

```swift
struct AgentUsageDailyBucket: Codable, Equatable, Sendable {
    var day: String
    var sessionIDsByAgent: [String: Set<String>]
    var toolCounts: [String: Int]
    var tokenTotals: AgentUsageTokenTotals
    var tokenTotalsByModel: [String: AgentUsageTokenTotals]
    var activityCount: Int

    nonisolated init(
        day: String,
        sessionIDsByAgent: [String: Set<String>] = [:],
        toolCounts: [String: Int] = [:],
        tokenTotals: AgentUsageTokenTotals = AgentUsageTokenTotals(),
        tokenTotalsByModel: [String: AgentUsageTokenTotals] = [:],
        activityCount: Int = 0
    ) {
        self.day = day
        self.sessionIDsByAgent = sessionIDsByAgent
        self.toolCounts = toolCounts
        self.tokenTotals = tokenTotals
        self.tokenTotalsByModel = tokenTotalsByModel
        self.activityCount = activityCount
    }

    private enum CodingKeys: String, CodingKey {
        case day, sessionIDsByAgent, toolCounts, tokenTotals, tokenTotalsByModel, activityCount
    }

    // Pre-upgrade buckets have no tokenTotalsByModel key: decode it as an empty map
    // so old data keeps loading (no schemaVersion bump, no wipe).
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        sessionIDsByAgent = try container.decodeIfPresent([String: Set<String>].self, forKey: .sessionIDsByAgent) ?? [:]
        toolCounts = try container.decodeIfPresent([String: Int].self, forKey: .toolCounts) ?? [:]
        tokenTotals = try container.decodeIfPresent(AgentUsageTokenTotals.self, forKey: .tokenTotals) ?? AgentUsageTokenTotals()
        tokenTotalsByModel = try container.decodeIfPresent([String: AgentUsageTokenTotals].self, forKey: .tokenTotalsByModel) ?? [:]
        activityCount = try container.decodeIfPresent(Int.self, forKey: .activityCount) ?? 0
    }

    // recordSession / recordTool / recordTokens(_:) 原樣保留

    // Invariant: tokenTotals always equals the sum of tokenTotalsByModel values for
    // data written through this method.
    nonisolated mutating func recordTokens(perModel deltasByModel: [String: AgentUsageTokenTotals]) {
        var combined = AgentUsageTokenTotals()
        for (model, delta) in deltasByModel {
            guard delta.hasTokens else { continue }
            tokenTotalsByModel[model, default: AgentUsageTokenTotals()].add(delta)
            combined.add(delta)
        }
        tokenTotals.add(combined)
        if combined.resolvedTotal > 0 {
            activityCount += 1
        }
    }
}
```

- [x] 跑測試確認通過（同上 `-only-testing:PingIslandTests/AgentUsageAnalyticsTests`）
- [x] Commit：`feat: track per-model token totals in AgentUsageDailyBucket`

---

### Task 3: ClaudeTranscriptUsageLoader 逐行 model 分桶

**Files**

- Modify: `PingIsland/Services/Usage/ClaudeTranscriptUsage.swift`（snapshot struct 3-9 行、`load` 33-64 行）
- Modify: `PingIslandTests/ClaudeTranscriptUsageLoaderTests.swift`

**Interfaces**

- Produces：

```swift
struct ClaudeTranscriptUsageSnapshot: Equatable, Sendable {
    let tokenTotals: AgentUsageTokenTotals                      // 彙總，保留
    let tokenTotalsByModel: [String: AgentUsageTokenTotals]    // 新增，鍵為 normalizedKey
}
```

- Consumes：`AgentUsageModelPricing.normalizedKey(forModel:)`（Task 1）。

**Steps**

- [x] 加失敗測試（`ClaudeTranscriptUsageLoaderTests.swift`）：

```swift
    func testLoadBucketsMixedModelTranscriptPerModel() throws {
        let transcriptURL = temporaryTranscriptURL(named: "mixed-model")
        defer { try? FileManager.default.removeItem(at: transcriptURL.deletingLastPathComponent()) }

        try writeJSONLLines([
            [
                "timestamp": "2026-04-10T00:00:00.000Z",
                "type": "assistant",
                "message": [
                    "role": "assistant",
                    "model": "claude-opus-4-8",
                    "usage": [
                        "input_tokens": 100,
                        "cache_creation_input_tokens": 20,
                        "cache_read_input_tokens": 30,
                        "output_tokens": 50,
                    ],
                ],
            ],
            [
                "timestamp": "2026-04-10T00:01:00.000Z",
                "type": "assistant",
                "message": [
                    "role": "assistant",
                    "model": "claude-haiku-4-5-20251001",
                    "usage": [
                        "input_tokens": 10,
                        "output_tokens": 4,
                    ],
                ],
            ],
        ], to: transcriptURL)

        let snapshot = try XCTUnwrap(ClaudeTranscriptUsageLoader.load(from: transcriptURL))

        XCTAssertEqual(
            snapshot.tokenTotalsByModel["opus-4.8"],
            AgentUsageTokenTotals(input: 100, cacheCreation: 20, cacheRead: 30, output: 50)
        )
        XCTAssertEqual(
            snapshot.tokenTotalsByModel["haiku-4.5"],
            AgentUsageTokenTotals(input: 10, output: 4)
        )
        XCTAssertEqual(snapshot.tokenTotalsByModel.count, 2)
        var summed = AgentUsageTokenTotals()
        for totals in snapshot.tokenTotalsByModel.values { summed.add(totals) }
        XCTAssertEqual(snapshot.tokenTotals, summed, "aggregate must equal the per-model sum")
    }

    func testLoadBucketsModellessLinesUnderUnknown() throws {
        let transcriptURL = temporaryTranscriptURL(named: "modelless")
        defer { try? FileManager.default.removeItem(at: transcriptURL.deletingLastPathComponent()) }

        try writeJSONLLines([
            [
                "timestamp": "2026-04-10T00:02:00.000Z",
                "usage": [
                    "prompt_tokens": 13,
                    "completion_tokens": 8,
                ],
            ],
        ], to: transcriptURL)

        let snapshot = try XCTUnwrap(ClaudeTranscriptUsageLoader.load(from: transcriptURL))

        XCTAssertEqual(snapshot.tokenTotalsByModel["unknown"], AgentUsageTokenTotals(input: 13, output: 8))
    }
```

- [x] 跑測試確認失敗：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/ClaudeTranscriptUsageLoaderTests`
- [x] 最小實作：snapshot 加欄位、`load` 逐行分桶、加 `modelIdentifier(from:)`：

```swift
struct ClaudeTranscriptUsageSnapshot: Equatable, Sendable {
    let sourceFilePath: String
    let capturedAt: Date?
    let fileSize: UInt64
    let contentHash: String
    let tokenTotals: AgentUsageTokenTotals
    let tokenTotalsByModel: [String: AgentUsageTokenTotals]
}
```

`load` 迴圈（38-51 行）改為：

```swift
        var totals = AgentUsageTokenTotals()
        var totalsByModel: [String: AgentUsageTokenTotals] = [:]
        var latestUsageDate: Date?

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let object = jsonObject(for: line),
                  let lineTotals = usageTotals(from: object) else {
                continue
            }

            totals.add(lineTotals)
            let modelKey = AgentUsageModelPricing.normalizedKey(forModel: modelIdentifier(from: object))
            totalsByModel[modelKey, default: AgentUsageTokenTotals()].add(lineTotals)
            if let lineDate = timestamp(from: object["timestamp"]),
               latestUsageDate == nil || lineDate > latestUsageDate! {
                latestUsageDate = lineDate
            }
        }
```

回傳處補 `tokenTotalsByModel: totalsByModel`，並加 helper：

```swift
    private nonisolated static func modelIdentifier(from object: [String: Any]) -> String? {
        if let message = object["message"] as? [String: Any],
           let model = message["model"] as? String, !model.isEmpty {
            return model
        }
        if let model = object["model"] as? String, !model.isEmpty {
            return model
        }
        return nil
    }
```

- [x] 跑測試確認通過（同 class filter；`ClaudeTranscriptUsageLoaderTests` 既有 5 個測試 —— 4 個 loader + 1 個 record —— 也必須綠，混 model 之外的 transcript 落在 `unknown` 鍵）
- [x] Commit：`feat: bucket Claude transcript usage per message model`

---

### Task 4: CodexUsage cached 拆分與 turn_context model 掃描

**Files**

- Modify: `PingIsland/Services/Usage/AgentUsageAnalytics.swift`（`CodexTokenUsage`，367-376 行）
- Modify: `PingIsland/Services/Usage/CodexUsage.swift`（`CodexUsageSnapshot` 18-73 行、`loadLatestSnapshot` 171-191 行、`snapshot(from:)` 254-281 行、`tokenUsage(from:)` 391-421 行）
- Modify: `PingIslandTests/AgentUsageAnalyticsTests.swift`、`PingIslandTests/CodexUsageLoaderTests.swift`

**Interfaces**

- Produces：

```swift
struct CodexTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int   // 新增，legacy 解碼預設 0
    let outputTokens: Int
    let totalTokens: Int
    nonisolated init(inputTokens: Int, cachedInputTokens: Int = 0, outputTokens: Int, totalTokens: Int)
    nonisolated var totals: AgentUsageTokenTotals   // input 扣 cached、cached 進 cacheRead
}

struct CodexUsageSnapshot {
    let model: String?   // 新增，來自最後一筆 turn_context.payload.model；補 CodingKeys 與 decodeIfPresent
}
```

- 注意：`CodexUsageSnapshot` 經 `UsageSnapshotCacheStore` 持久化（spec fable5 3d），`model` 必須同步進自訂 `CodingKeys` 與 `init(from:)` 的 `decodeIfPresent`。
- model 掃描位置在 `loadLatestSnapshot`（持有整段 suffix `contents`），不是 `snapshot(from:)`（只收到單一 token_count 行）。

**Steps**

- [x] 在 `AgentUsageAnalyticsTests.swift` 加失敗測試：

```swift
    func testCodexTokenUsageSplitsCachedInputTokens() {
        // Assumption backed by local rollout samples: input_tokens INCLUDES cached_input_tokens.
        let usage = CodexTokenUsage(inputTokens: 28_383, cachedInputTokens: 4_480, outputTokens: 424, totalTokens: 28_807)
        XCTAssertEqual(usage.totals, AgentUsageTokenTotals(input: 23_903, cacheRead: 4_480, output: 424))
    }

    func testCodexTokenUsageLegacyDecodeDefaultsCachedToZero() throws {
        let legacy = #"{"inputTokens":100,"outputTokens":50,"totalTokens":150}"#
        let usage = try JSONDecoder().decode(CodexTokenUsage.self, from: Data(legacy.utf8))
        XCTAssertEqual(usage.cachedInputTokens, 0)
        XCTAssertEqual(usage.totals, AgentUsageTokenTotals(input: 100, output: 50))
    }
```

- [x] 在 `CodexUsageLoaderTests.swift` 加失敗測試：

```swift
    func testLoadCapturesCachedInputTokensAndLatestTurnContextModel() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-model")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/07/04", isDirectory: true)
            .appendingPathComponent("rollout-model.jsonl")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-07-04T00:00:00.000Z",
                    type: "turn_context",
                    payload: ["model": "gpt-5.5", "cwd": "/tmp/example-project"]
                ),
                rolloutLine(
                    timestamp: "2026-07-04T00:01:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "input_tokens": 28_383,
                                "cached_input_tokens": 4_480,
                                "output_tokens": 424,
                                "total_tokens": 28_807,
                            ],
                        ],
                        "rate_limits": [
                            "primary": [
                                "used_percent": 10.0,
                                "window_minutes": 300,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        XCTAssertEqual(snapshot?.model, "gpt-5.5")
        XCTAssertEqual(snapshot?.tokenUsage?.cachedInputTokens, 4_480)
        XCTAssertEqual(
            snapshot?.tokenUsage?.totals,
            AgentUsageTokenTotals(input: 23_903, cacheRead: 4_480, output: 424)
        )
    }

    func testLoadModelIsNilWhenRolloutHasNoTurnContext() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-no-turn-context")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/07/04", isDirectory: true)
            .appendingPathComponent("rollout-no-context.jsonl")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-07-04T00:01:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "primary": ["used_percent": 10.0, "window_minutes": 300],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        XCTAssertNotNil(snapshot)
        XCTAssertNil(snapshot?.model)
    }

    func testSnapshotCodableRoundTripsModelAndToleratesLegacyJSON() throws {
        let snapshot = CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout-x.jsonl",
            capturedAt: nil,
            planType: "pro",
            limitID: "codex",
            tokenUsage: nil,
            model: "gpt-5.5",
            windows: []
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.model, "gpt-5.5")

        let legacy = #"{"sourceFilePath":"/tmp/rollout-x.jsonl","windows":[]}"#
        let legacyDecoded = try JSONDecoder().decode(CodexUsageSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyDecoded.model)
    }
```

- [x] 跑兩個 class 確認失敗：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageAnalyticsTests -only-testing:PingIslandTests/CodexUsageLoaderTests`
- [x] 改 `CodexTokenUsage`（`AgentUsageAnalytics.swift:367-376`）：

```swift
struct CodexTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    nonisolated init(inputTokens: Int, cachedInputTokens: Int = 0, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens, cachedInputTokens, outputTokens, totalTokens
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }

    nonisolated var totals: AgentUsageTokenTotals {
        // Assumption (verified against local rollout samples, not official semantics):
        // input_tokens INCLUDES cached_input_tokens (input + output == total, cached < input),
        // so subtract to avoid double-counting. Cache hits are billed at the 0.1x read rate.
        // cacheCreation stays 0: OpenAI has no cache-write surcharge.
        AgentUsageTokenTotals(
            input: max(0, inputTokens - cachedInputTokens),
            cacheRead: cachedInputTokens,
            output: outputTokens
        )
    }
}
```

- [x] 改 `CodexUsage.swift`：
  - `CodexUsageSnapshot` 加 `let model: String?`，memberwise init 於 `tokenUsage` 後加 `model: String? = nil`（既有呼叫點不用改），`CodingKeys` 加 `model`，`init(from:)` 加 `model = try container.decodeIfPresent(String.self, forKey: .model)`。
  - `tokenUsage(from:)` 加讀 cached：

```swift
        let cachedInputTokens = integer(from: usage["cached_input_tokens"]) ?? 0
        // ... return 改為
        return CodexTokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens
        )
```

  - `loadLatestSnapshot` 先掃 model 再找 token_count，`snapshot(from:)` 增加 `model` 參數：

```swift
    private nonisolated static func loadLatestSnapshot(
        from fileURL: URL,
        modifiedAt: Date,
        fileSize: UInt64,
        maxBytes: Int
    ) -> CodexUsageSnapshot? {
        guard fileSize > 0,
              maxBytes > 0,
              let contents = readSuffixText(from: fileURL, fileSize: fileSize, maxBytes: maxBytes) else {
            return nil
        }

        let model = latestTurnContextModel(in: contents)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            if line.contains("\"token_count\""),
               line.contains("\"rate_limits\""),
               let snapshot = snapshot(
                    from: String(line),
                    filePath: fileURL.path,
                    fallbackTimestamp: modifiedAt,
                    model: model
               ) {
                return snapshot
            }
        }
        return nil
    }

    // A Codex thread is effectively pinned to one model; take the last turn_context in
    // the suffix window. Some rollouts have none (observed 1 of 8 local samples) → nil.
    private nonisolated static func latestTurnContextModel(in contents: String) -> String? {
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"turn_context\""),
                  let object = jsonObject(for: String(line)),
                  object["type"] as? String == "turn_context",
                  let payload = object["payload"] as? [String: Any],
                  let model = payload["model"] as? String,
                  !model.isEmpty else {
                continue
            }
            return model
        }
        return nil
    }
```

`snapshot(from:filePath:fallbackTimestamp:model:)` 的 return 補 `model: model`。

- [x] 跑兩個 class 確認通過（既有 `testLoadParsesLastTokenCountRateLimits` 的 `tokenUsage` 等值斷言因 `cachedInputTokens` 預設 0 仍成立）
- [x] Commit：`feat: split Codex cached input tokens and capture rollout model`

---

### Task 5: baseline totalsByModel、文件遷移與 recordTokenUsage 逐 model delta

這是原子改動：baseline 結構、`recordTokenUsage` 簽章、兩個 callsite（`recordCodexUsageSnapshot`、`SessionStore.recordClaudeFamilyTranscriptUsageIfAvailable`）必須同 commit 才能編譯。

**Files**

- Modify: `PingIsland/Services/Usage/AgentUsageAnalytics.swift`
  - `AgentUsageTokenSourceBaseline`（94-108 行）
  - `AgentUsageDocument.init` 遷移迴圈（433-438 行）與 `init(from:)` 遷移迴圈（476-481 行）
  - `recordCodexUsageSnapshot`（615-636 行）
  - `recordTokenUsage`（638-701 行）
  - 移除 `AgentUsageDailyBucket.recordTokens(_ totals:)`（本改動後唯一呼叫點消失）
- Modify: `PingIsland/Services/State/SessionStore.swift`（2819-2834 行）
- Modify: `PingIslandTests/AgentUsageAnalyticsTests.swift`、`PingIslandTests/ClaudeTranscriptUsageLoaderTests.swift`

**Interfaces**

- Produces：

```swift
struct AgentUsageTokenSourceBaseline: Codable, Equatable, Sendable {
    var totalsByModel: [String: AgentUsageTokenTotals]   // 取代 totals
    var fileSize: UInt64?
    var contentHash: String?
    nonisolated init(totalsByModel: [String: AgentUsageTokenTotals], fileSize: UInt64? = nil, contentHash: String? = nil)
}

// AgentUsageStore
func recordTokenUsage(
    provider: SessionProvider,
    clientInfo: SessionClientInfo,
    sessionID: String?,
    sourceKey: String,
    totalsByModel currentTotalsByModel: [String: AgentUsageTokenTotals],   // 取代 totals
    capturedAt: Date,
    sourceFileSize: UInt64? = nil,
    sourceContentHash: String? = nil,
    recordInitialSnapshot: Bool = true,
    now: Date = Date()
) async
```

- Consumes：`ClaudeTranscriptUsageSnapshot.tokenTotalsByModel`（Task 3）、`CodexUsageSnapshot.model`（Task 4）、`AgentUsageDailyBucket.recordTokens(perModel:)`（Task 2）。
- 降版相容註記（spec fable5 1d）：舊版 app 讀新檔時 synthesized decoder 要求非 optional `totals` 而失敗、`load` 回空文件等同全清；降版非支援情境，實作時在 `AgentUsageTokenSourceBaseline` 加註解即可，不寫防護碼。

**Steps**

- [x] 在 `AgentUsageAnalyticsTests.swift` 加失敗測試（含 spec「測試」節的 recordTokenUsage B 全部情境）：

```swift
    func testLegacyBaselineShapeDecodesToEmptyPerModelMap() throws {
        let legacy = #"{"totals":{"input":10,"cacheCreation":0,"cacheRead":0,"output":5},"fileSize":128,"contentHash":"abc"}"#
        let baseline = try JSONDecoder().decode(AgentUsageTokenSourceBaseline.self, from: Data(legacy.utf8))
        XCTAssertEqual(baseline.totalsByModel, [:])
        XCTAssertEqual(baseline.fileSize, 128)
        XCTAssertEqual(baseline.contentHash, "abc")
    }

    func testCodexLegacyBaselineMigrationSeedsEmptyPerModelMap() throws {
        // fable5 1b: migrating codexTokenBaselines must NOT seed an "unknown" key,
        // otherwise the first real-model scan sees a missing key and dumps in full.
        let json = """
        {"schemaVersion":2,"buckets":{},"seenToolEventIDs":[],"codexTokenBaselines":{"thread-1":{"inputTokens":100,"outputTokens":50,"totalTokens":150}},"tokenBaselines":{}}
        """
        let document = try JSONDecoder().decode(AgentUsageDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.tokenBaselines["codex|thread-1"]?.totalsByModel, [:])
    }

    func testRecordTokenUsageSeedsWithoutCountingThenCountsPerModelDelta() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-per-model-delta-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let store = AgentUsageStore(fileURL: fileURL, calendar: calendar)
        let clientInfo = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude",
            name: "Claude Code",
            sessionFilePath: "/tmp/example/session.jsonl"
        )
        let sourceKey = "transcript|claude|session-1|/tmp/example/session.jsonl"

        // first sight + recordInitialSnapshot:false → seed only, nothing counted
        await store.recordTokenUsage(
            provider: .claude,
            clientInfo: clientInfo,
            sessionID: "session-1",
            sourceKey: sourceKey,
            totalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 100, output: 40)],
            capturedAt: now,
            sourceFileSize: 100,
            recordInitialSnapshot: false
        )
        var snapshot = await store.snapshot(range: .today, now: now)
        XCTAssertEqual(snapshot.tokenTotals.resolvedTotal, 0)

        // growth on an existing key = per-model delta; a NEW key against a non-empty
        // baseline (mid-source subagent model) is counted in full
        await store.recordTokenUsage(
            provider: .claude,
            clientInfo: clientInfo,
            sessionID: "session-1",
            sourceKey: sourceKey,
            totalsByModel: [
                "opus-4.8": AgentUsageTokenTotals(input: 160, output: 70),
                "haiku-4.5": AgentUsageTokenTotals(input: 30, output: 12),
            ],
            capturedAt: now,
            sourceFileSize: 200,
            recordInitialSnapshot: false
        )
        snapshot = await store.snapshot(range: .today, now: now)
        XCTAssertEqual(snapshot.tokenTotals, AgentUsageTokenTotals(input: 90, output: 42))

        await store.flush()
        let document = try JSONDecoder().decode(AgentUsageDocument.self, from: Data(contentsOf: fileURL))
        let bucket = try XCTUnwrap(document.buckets[AgentUsageStore.dayKey(for: now, calendar: calendar)])
        XCTAssertEqual(bucket.tokenTotalsByModel["opus-4.8"], AgentUsageTokenTotals(input: 60, output: 30))
        XCTAssertEqual(bucket.tokenTotalsByModel["haiku-4.5"], AgentUsageTokenTotals(input: 30, output: 12))
        var summed = AgentUsageTokenTotals()
        for totals in bucket.tokenTotalsByModel.values { summed.add(totals) }
        XCTAssertEqual(bucket.tokenTotals, summed)
    }

    func testRecordTokenUsageFileShrinkReseedsAllModelsWithoutCounting() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-per-model-reset-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let store = AgentUsageStore(fileURL: fileURL, calendar: calendar)
        let clientInfo = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude",
            name: "Claude Code",
            sessionFilePath: "/tmp/example/session.jsonl"
        )
        let sourceKey = "transcript|claude|session-2|/tmp/example/session.jsonl"

        await store.recordTokenUsage(
            provider: .claude, clientInfo: clientInfo, sessionID: "session-2",
            sourceKey: sourceKey,
            totalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 500, output: 200)],
            capturedAt: now, sourceFileSize: 500, recordInitialSnapshot: false
        )
        // file shrank (session restart / truncation): reset, re-seed only
        await store.recordTokenUsage(
            provider: .claude, clientInfo: clientInfo, sessionID: "session-2",
            sourceKey: sourceKey,
            totalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 50, output: 20)],
            capturedAt: now, sourceFileSize: 100, recordInitialSnapshot: false
        )
        var snapshot = await store.snapshot(range: .today, now: now)
        XCTAssertEqual(snapshot.tokenTotals.resolvedTotal, 0)

        // growth after re-seed counts against the reset baseline
        await store.recordTokenUsage(
            provider: .claude, clientInfo: clientInfo, sessionID: "session-2",
            sourceKey: sourceKey,
            totalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 80, output: 30)],
            capturedAt: now, sourceFileSize: 160, recordInitialSnapshot: false
        )
        snapshot = await store.snapshot(range: .today, now: now)
        XCTAssertEqual(snapshot.tokenTotals, AgentUsageTokenTotals(input: 30, output: 10))
    }

    func testLegacyDocumentOnDiskDoesNotDumpHistoryOnFirstScan() async throws {
        // The core "no history dump" guarantee via the real disk path: a legacy-shape
        // document (baseline with the old aggregate `totals` key, no `totalsByModel`)
        // decodes to an empty per-model map, so the next recordInitialSnapshot:false scan
        // takes the first-sight branch (previous != nil but totalsByModel.isEmpty) and
        // only re-seeds — today's bucket stays 0 instead of dumping the whole transcript.
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-legacy-doc-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("usage.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let sourceKey = "transcript|claude|legacy-session|/tmp/example/session.jsonl"

        // Hand-write a legacy document: baseline stored the pre-upgrade `totals` shape.
        let legacyDocumentJSON = """
        {"schemaVersion":2,"buckets":{},"seenToolEventIDs":[],"codexTokenBaselines":{},"tokenBaselines":{"\(sourceKey)":{"totals":{"input":900000,"cacheCreation":0,"cacheRead":5000000,"output":300000},"fileSize":4096,"contentHash":"legacy"}}}
        """
        try Data(legacyDocumentJSON.utf8).write(to: fileURL)

        let store = AgentUsageStore(fileURL: fileURL, calendar: calendar)
        let clientInfo = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude",
            name: "Claude Code",
            sessionFilePath: "/tmp/example/session.jsonl"
        )

        // First scan after upgrade: baseline exists but its totalsByModel is empty →
        // first-sight, recordInitialSnapshot:false → seed only, nothing counted.
        await store.recordTokenUsage(
            provider: .claude, clientInfo: clientInfo, sessionID: "legacy-session",
            sourceKey: sourceKey,
            totalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 950_000, cacheRead: 5_100_000, output: 320_000)],
            capturedAt: now, sourceFileSize: 5_000, recordInitialSnapshot: false
        )

        let snapshot = await store.snapshot(range: .today, now: now)
        XCTAssertEqual(snapshot.tokenTotals.resolvedTotal, 0, "legacy baseline must re-seed, not dump history")
    }
```

- [x] 跑測試確認失敗（編譯錯誤即為預期）：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageAnalyticsTests`
- [x] 改 `AgentUsageTokenSourceBaseline`：

```swift
struct AgentUsageTokenSourceBaseline: Codable, Equatable, Sendable {
    var totalsByModel: [String: AgentUsageTokenTotals]
    var fileSize: UInt64?
    var contentHash: String?

    nonisolated init(
        totalsByModel: [String: AgentUsageTokenTotals],
        fileSize: UInt64? = nil,
        contentHash: String? = nil
    ) {
        self.totalsByModel = totalsByModel
        self.fileSize = fileSize
        self.contentHash = contentHash
    }

    private enum CodingKeys: String, CodingKey {
        case totalsByModel, fileSize, contentHash
    }

    // Legacy shape stored a single aggregate `totals`: decode it as an EMPTY map so the
    // next scan takes the first-sight branch and re-seeds per model without dumping
    // history (Claude/Codex callers use recordInitialSnapshot:false). No schemaVersion
    // bump, no data wipe. Downgrade note: an older app decoding the new shape fails on
    // the missing non-optional `totals` and loads an empty document; downgrades are
    // not a supported scenario.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalsByModel = try container.decodeIfPresent([String: AgentUsageTokenTotals].self, forKey: .totalsByModel) ?? [:]
        fileSize = try container.decodeIfPresent(UInt64.self, forKey: .fileSize)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
    }
}
```

- [x] 改 `AgentUsageDocument` 兩處遷移迴圈（433-438 與 476-481 行），一律建空 map：

```swift
        for (sourceKey, _) in codexTokenBaselines {
            let migratedKey = Self.codexTokenSourceKey(sourceKey)
            if !tokenBaselines.keys.contains(migratedKey) {
                // Empty map = first-sight branch on next scan; never seed an "unknown"
                // key here or the first real-model scan would double count (fable5 1b).
                tokenBaselines[migratedKey] = AgentUsageTokenSourceBaseline(totalsByModel: [:])
            }
        }
```

（memberwise `init` 內的迴圈同樣改法，注意該處是 `self.tokenBaselines`。）

- [x] 改 `recordTokenUsage`（638-701 行）：

```swift
    func recordTokenUsage(
        provider: SessionProvider,
        clientInfo: SessionClientInfo,
        sessionID: String?,
        sourceKey: String,
        totalsByModel currentTotalsByModel: [String: AgentUsageTokenTotals],
        capturedAt: Date,
        sourceFileSize: UInt64? = nil,
        sourceContentHash: String? = nil,
        recordInitialSnapshot: Bool = true,
        now: Date = Date()
    ) async {
        guard currentTotalsByModel.values.contains(where: \.hasTokens) else {
            return
        }

        var document = await loadDocument()
        let previous = document.tokenBaselines[sourceKey]
        let didReset = didTokenSourceReset(
            previous: previous,
            currentFileSize: sourceFileSize
        )
        document.tokenBaselines[sourceKey] = AgentUsageTokenSourceBaseline(
            totalsByModel: currentTotalsByModel,
            fileSize: sourceFileSize,
            contentHash: sourceContentHash
        )

        let deltasByModel: [String: AgentUsageTokenTotals]
        if let previous, !previous.totalsByModel.isEmpty, !didReset {
            // Per-model delta. A key missing from a NON-empty baseline is a model that
            // appeared mid-source (e.g. a subagent on haiku): count it in full. This is
            // distinct from the empty-map first-sight branch below; do not merge them.
            var deltas: [String: AgentUsageTokenTotals] = [:]
            for (model, current) in currentTotalsByModel {
                if let base = previous.totalsByModel[model] {
                    deltas[model] = AgentUsageTokenTotals(
                        input: max(0, current.input - base.input),
                        cacheCreation: max(0, current.cacheCreation - base.cacheCreation),
                        cacheRead: max(0, current.cacheRead - base.cacheRead),
                        output: max(0, current.output - base.output)
                    )
                } else {
                    deltas[model] = current
                }
            }
            deltasByModel = deltas
        } else if recordInitialSnapshot {
            // First sight of the whole source (nil baseline, legacy empty map, or reset).
            deltasByModel = currentTotalsByModel
        } else {
            // Seed the baseline only; counting starts from the next scan.
            self.document = document
            scheduleSave()
            return
        }

        guard deltasByModel.values.contains(where: \.hasTokens) else {
            self.document = document
            scheduleSave()
            return
        }

        let day = Self.dayKey(for: capturedAt, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        if let sessionID = nonEmpty(sessionID) {
            bucket.recordSession(
                agent: agentLabel(provider: provider, clientInfo: clientInfo),
                sessionID: sessionID
            )
        }
        bucket.recordTokens(perModel: deltasByModel)
        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }
```

- [x] 改 `recordCodexUsageSnapshot`（615-636 行）：一次到位帶入 model 鍵穩定規則（nil 時沿用既有 baseline 唯一鍵，連前次都沒有才 `unknown`），不留翻轉窗（spec fable5 3b 標 BLOCKER，不可分兩 commit）。Task 6 只補回歸測試守這段：

```swift
    func recordCodexUsageSnapshot(_ snapshot: CodexUsageSnapshot, now: Date = Date()) async {
        guard let currentUsage = snapshot.tokenUsage,
              currentUsage.totalTokens > 0 || currentUsage.inputTokens > 0 || currentUsage.outputTokens > 0 else {
            return
        }

        let sourceKey = snapshot.threadID ?? snapshot.sourceFilePath
        let baselineKey = AgentUsageDocument.codexTokenSourceKey(sourceKey)

        // Key stability (fable5 3b): a Codex thread is pinned to one model, but a scan
        // may miss the turn_context (model == nil). Reuse the baseline's sole key so the
        // map key never flips nil <-> model and double counts the thread. Only when there
        // is no previous key either does it fall back to "unknown". (loadDocument() is
        // cached, so reading the baseline first is cheap.)
        let existingBaseline = await loadDocument().tokenBaselines[baselineKey]
        let modelKey: String
        if let model = snapshot.model {
            modelKey = AgentUsageModelPricing.normalizedKey(forModel: model)
        } else if existingBaseline?.totalsByModel.count == 1,
                  let soleKey = existingBaseline?.totalsByModel.keys.first {
            modelKey = soleKey
        } else {
            modelKey = AgentUsageModelPricing.normalizedKey(forModel: nil)
        }

        await recordTokenUsage(
            provider: .codex,
            clientInfo: .codexCLI(),
            sessionID: snapshot.threadID,
            sourceKey: baselineKey,
            totalsByModel: [modelKey: currentUsage.totals],
            capturedAt: snapshot.capturedAt ?? now,
            recordInitialSnapshot: false
        )

        var document = await loadDocument()
        document.codexTokenBaselines[sourceKey] = currentUsage
        self.document = document
        scheduleSave()
    }
```

- [x] 刪除 `AgentUsageDailyBucket.recordTokens(_ totals: AgentUsageTokenTotals)`（此改動後無呼叫者）
- [x] 改 `SessionStore.recordClaudeFamilyTranscriptUsageIfAvailable`（2819-2834 行）：`totals: snapshot.tokenTotals` 改為 `totalsByModel: snapshot.tokenTotalsByModel`，其餘參數（含 `recordInitialSnapshot: false`、sourceKey）不動
- [x] 更新 `ClaudeTranscriptUsageLoaderTests.testRecordTranscriptUsageDoesNotDoubleCountRepeatedReads`：三處 `totals: firstSnapshot.tokenTotals` / `totals: secondSnapshot.tokenTotals` 改為 `totalsByModel: firstSnapshot.tokenTotalsByModel` / `totalsByModel: secondSnapshot.tokenTotalsByModel`（斷言不變；該測試未帶 `recordInitialSnapshot:` 走預設 true，首錄即計入，行為與改動前相同）
- [x] 跑整包確認通過（此 task 動到共用路徑）：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- [x] Commit：`feat: compute per-model token deltas against per-source baselines`

---

### Task 6: recordCodexUsageSnapshot model 鍵穩定回歸測試

model 鍵穩定的實作已在 Task 5 同 commit 落地（不留翻轉窗）；本 task 只補回歸測試把行為釘死。因此測試在 Task 5 之後應「一次就過」，屬回歸鎖而非 fail-first TDD；若它失敗代表 Task 5 的鍵解析被改壞。

**Files**

- Modify: `PingIslandTests/AgentUsageAnalyticsTests.swift`

**Interfaces**

- 只讀既有 `recordCodexUsageSnapshot`（Task 5 已含鍵解析：`snapshot.model` 為 nil 時沿用既有 baseline 唯一 model 鍵，連前次鍵都沒有才 `unknown`）。不改 product code。

**Steps**

- [x] 加回歸測試：

```swift
    func testRecordCodexUsageSnapshotReusesBaselineKeyWhenModelMissing() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-island-codex-key-stability-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = AgentUsageStore(fileURL: fileURL, calendar: calendar)
        let capturedAt = Date(timeIntervalSince1970: 1_775_520_000)
        let sourcePath = "/tmp/.codex/sessions/2026/04/10/rollout-2026-04-10T00-00-00-019db9a7-336a-7b62-9288-7304c3d2d4b9.jsonl"

        await store.recordCodexUsageSnapshot(CodexUsageSnapshot(
            sourceFilePath: sourcePath,
            capturedAt: capturedAt,
            planType: "pro",
            limitID: "codex",
            tokenUsage: CodexTokenUsage(inputTokens: 100, outputTokens: 50, totalTokens: 150),
            model: "gpt-5.5",
            windows: []
        ))
        // Same thread, but this scan could not see a turn_context (model == nil).
        // The key must NOT flip to "unknown", or the whole thread double counts.
        await store.recordCodexUsageSnapshot(CodexUsageSnapshot(
            sourceFilePath: sourcePath,
            capturedAt: capturedAt,
            planType: "pro",
            limitID: "codex",
            tokenUsage: CodexTokenUsage(inputTokens: 175, outputTokens: 80, totalTokens: 255),
            model: nil,
            windows: []
        ))

        let snapshot = await store.snapshot(range: .today, now: capturedAt)
        XCTAssertEqual(snapshot.tokenTotals, AgentUsageTokenTotals(input: 75, output: 30))

        await store.flush()
        let document = try JSONDecoder().decode(AgentUsageDocument.self, from: Data(contentsOf: fileURL))
        let day = AgentUsageStore.dayKey(for: capturedAt, calendar: calendar)
        let bucket = try XCTUnwrap(document.buckets[day])
        XCTAssertEqual(bucket.tokenTotalsByModel, ["gpt-5.5": AgentUsageTokenTotals(input: 75, output: 30)])
        let baselineKey = AgentUsageDocument.codexTokenSourceKey("019db9a7-336a-7b62-9288-7304c3d2d4b9")
        XCTAssertEqual(document.tokenBaselines[baselineKey]?.totalsByModel.keys.sorted() ?? [], ["gpt-5.5"])
    }
```

- [x] 跑 class 確認通過（回歸鎖：Task 5 已實作，應一次就過）：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AgentUsageAnalyticsTests`
- [x] Commit：`test: lock Codex per-model baseline key stability when model scan misses`

---

### Task 7: snapshot perModelBreakdown / perModelDailySpend 與殘量計價

**Files**

- Modify: `PingIsland/Services/Usage/AgentUsageAnalytics.swift`
  - 新 struct `AgentUsageModelBreakdownItem`、`AgentUsageModelDailySpend`（放 `AgentUsageDailySpendPoint` 附近，143-161 行區）
  - `AgentUsageDashboardSnapshot`（220-365 行）：新欄位、`empty`、`costMetric` / `dailySpendPoints` 改殘量計價、新增 `perModelDailySpend` helper
  - `makeSnapshot`（788-846 行）：彙總 `perModelBreakdown`、傳入新欄位
- Modify: `PingIslandTests/AgentUsageAnalyticsTests.swift`

**Interfaces**

- Produces（spec 原文結構）：

```swift
struct AgentUsageModelBreakdownItem: Identifiable, Equatable, Sendable {
    let modelKey: String       // 正規化後用於配色的穩定鍵
    let displayName: String
    let tokenTotals: AgentUsageTokenTotals
    let estimatedUSD: Double
    nonisolated var id: String { modelKey }
    nonisolated var tokenTotal: Int { tokenTotals.resolvedTotal }
}

struct AgentUsageModelDailySpend: Identifiable, Equatable, Sendable {
    let modelKey: String
    let displayName: String
    let points: [AgentUsageDailySpendPoint]   // 對齊 spendDayCount(30) 天，缺日補 0
    nonisolated var id: String { modelKey }
    nonisolated var totalUSD: Double { points.reduce(0) { $0 + $1.estimatedUSD } }   // computed，非 stored（fable5 6b）
}

// AgentUsageDashboardSnapshot 新欄位
let perModelBreakdown: [AgentUsageModelBreakdownItem]     // 依 estimatedUSD 降序，範圍隨 selectedRange
let perModelDailySpend: [AgentUsageModelDailySpend]       // 30 天，逐 model 一條線，依 totalUSD 降序
```

- 計價公式（spec 原文）：`residual = componentwiseMax0(bucket.tokenTotals - sum(bucket.tokenTotalsByModel.values))`；`dayCost = estimateUSD(perModel: bucket.tokenTotalsByModel) + AgentUsageCostEstimator.estimateUSD(for: residual)`。純升級後桶殘量 = 0；純舊桶 map 空、殘量 = 整個 aggregate（blend）；升級當天混合桶殘量 = 升級前那段（fable5 6a）。

**Steps**

- [x] 加失敗測試：

```swift
    func testMakeSnapshotBuildsPerModelBreakdownAndDailySpend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let today = AgentUsageStore.dayKey(for: now, calendar: calendar)
        let opus = AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000)   // 5 + 25 = 30 USD
        let haiku = AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000)  // 1 + 5 = 6 USD
        var aggregate = AgentUsageTokenTotals()
        aggregate.add(opus)
        aggregate.add(haiku)

        let document = AgentUsageDocument(
            buckets: [
                today: AgentUsageDailyBucket(
                    day: today,
                    tokenTotals: aggregate,
                    tokenTotalsByModel: ["opus-4.8": opus, "haiku-4.5": haiku],
                    activityCount: 1
                ),
            ]
        )

        let snapshot = AgentUsageStore.makeSnapshot(range: .sevenDays, document: document, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.perModelBreakdown.map(\.modelKey), ["opus-4.8", "haiku-4.5"])
        XCTAssertEqual(snapshot.perModelBreakdown.first?.displayName, "Opus 4.8")
        XCTAssertEqual(snapshot.perModelBreakdown.first?.estimatedUSD ?? 0, 30.0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.perModelBreakdown.last?.estimatedUSD ?? 0, 6.0, accuracy: 0.000_001)

        XCTAssertEqual(snapshot.perModelDailySpend.map(\.modelKey), ["opus-4.8", "haiku-4.5"])
        XCTAssertTrue(snapshot.perModelDailySpend.allSatisfy { $0.points.count == 30 })
        XCTAssertEqual(snapshot.perModelDailySpend.first?.totalUSD ?? 0, 30.0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.perModelDailySpend.first?.points.last?.estimatedUSD ?? 0, 30.0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.perModelDailySpend.first?.points.first?.estimatedUSD ?? -1, 0, accuracy: 0.000_001)

        // headline：逐 model 官方費率，Opus 4.8 桶以 5/25 計、非 blend
        XCTAssertEqual(snapshot.spendSummary.today.estimatedUSD, 36.0, accuracy: 0.000_001)
    }

    func testLegacyBucketCostFallsBackToBlend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let today = AgentUsageStore.dayKey(for: now, calendar: calendar)
        let aggregate = AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000)

        let document = AgentUsageDocument(
            buckets: [
                // pre-upgrade bucket: empty per-model map, aggregate only
                today: AgentUsageDailyBucket(day: today, tokenTotals: aggregate, activityCount: 1),
            ]
        )

        let snapshot = AgentUsageStore.makeSnapshot(range: .today, document: document, now: now, calendar: calendar)

        XCTAssertTrue(snapshot.perModelBreakdown.isEmpty)
        XCTAssertEqual(snapshot.spendSummary.today.estimatedUSD, 16.875, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.spendSummary.dailyPoints.last?.estimatedUSD ?? 0, 16.875, accuracy: 0.000_001)
    }

    func testMixedUpgradeDayBucketChargesResidualAtBlend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_775_520_000)
        let today = AgentUsageStore.dayKey(for: now, calendar: calendar)

        let document = AgentUsageDocument(
            buckets: [
                today: AgentUsageDailyBucket(
                    day: today,
                    tokenTotals: AgentUsageTokenTotals(input: 2_000_000, output: 2_000_000),
                    tokenTotalsByModel: ["opus-4.8": AgentUsageTokenTotals(input: 1_000_000, output: 1_000_000)],
                    activityCount: 2
                ),
            ]
        )

        let snapshot = AgentUsageStore.makeSnapshot(range: .today, document: document, now: now, calendar: calendar)

        // 30 (official opus) + 16.875 (blend on the pre-upgrade residual 1M/1M)
        XCTAssertEqual(snapshot.spendSummary.today.estimatedUSD, 46.875, accuracy: 0.000_001)
    }
```

- [x] 跑測試確認失敗（同 class filter）
- [x] 實作。新 struct 照 Interfaces 區塊原樣加入。`AgentUsageDashboardSnapshot` 加兩個 `let` 欄位；`empty` 補 `perModelBreakdown: []`、`perModelDailySpend: []`。加殘量計價 helper（放 `AgentUsageDashboardSnapshot` extension 區）：

```swift
    // Per-bucket cost: official per-model rates for the mapped share, blended rate for
    // the residual. Post-upgrade buckets: residual == 0 (invariant). Legacy buckets:
    // empty map, whole aggregate stays blended. Mixed upgrade-day buckets: the
    // pre-upgrade share stays blended so it does not vanish (fable5 6a).
    fileprivate nonisolated static func bucketCost(_ bucket: AgentUsageDailyBucket) -> Double {
        var perModelSum = AgentUsageTokenTotals()
        for totals in bucket.tokenTotalsByModel.values {
            perModelSum.add(totals)
        }
        let residual = AgentUsageTokenTotals(
            input: max(0, bucket.tokenTotals.input - perModelSum.input),
            cacheCreation: max(0, bucket.tokenTotals.cacheCreation - perModelSum.cacheCreation),
            cacheRead: max(0, bucket.tokenTotals.cacheRead - perModelSum.cacheRead),
            output: max(0, bucket.tokenTotals.output - perModelSum.output)
        )
        return AgentUsageModelPricing.estimateUSD(perModel: bucket.tokenTotalsByModel)
            + AgentUsageCostEstimator.estimateUSD(for: residual)
    }
```

`costMetric` 改為逐桶加總（`tokenTotals` 聚合維持原邏輯，`estimatedUSD` 換算法）：

```swift
    private nonisolated static func costMetric(
        range: AgentUsageRange,
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> AgentUsageCostMetric {
        let today = calendar.startOfDay(for: now)
        var totals = AgentUsageTokenTotals()
        var estimatedUSD: Double = 0

        for offset in 0..<range.dayCount {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let key = AgentUsageStore.dayKey(for: date, calendar: calendar)
            guard let bucket = buckets[key] else { continue }
            totals.add(bucket.tokenTotals)
            estimatedUSD += bucketCost(bucket)
        }

        return AgentUsageCostMetric(range: range, tokenTotals: totals, estimatedUSD: estimatedUSD)
    }
```

（原 `tokenTotals(for:now:buckets:calendar:)` 若因此無其他呼叫者則一併移除。）`dailySpendPoints` 的 `estimatedUSD:` 改為 `buckets[key].map(Self.bucketCost) ?? 0`。新增 30 天逐 model helper：

```swift
    fileprivate nonisolated static func perModelDailySpend(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> [AgentUsageModelDailySpend] {
        let today = calendar.startOfDay(for: now)
        let dayEntries: [(date: Date, bucket: AgentUsageDailyBucket?)] = (0..<spendDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return (date, buckets[AgentUsageStore.dayKey(for: date, calendar: calendar)])
        }

        var modelKeys: Set<String> = []
        for entry in dayEntries {
            if let bucket = entry.bucket {
                modelKeys.formUnion(bucket.tokenTotalsByModel.keys)
            }
        }

        return modelKeys
            .map { key in
                let points = dayEntries.map { entry -> AgentUsageDailySpendPoint in
                    let totals = entry.bucket?.tokenTotalsByModel[key] ?? AgentUsageTokenTotals()
                    return AgentUsageDailySpendPoint(
                        date: entry.date,
                        tokenTotals: totals,
                        estimatedUSD: AgentUsageModelPricing.pricing(forModel: key).estimateUSD(for: totals)
                    )
                }
                return AgentUsageModelDailySpend(
                    modelKey: key,
                    displayName: AgentUsageModelPricing.displayName(forModel: key),
                    points: points
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalUSD == rhs.totalUSD { return lhs.modelKey < rhs.modelKey }
                return lhs.totalUSD > rhs.totalUSD
            }
    }
```

`makeSnapshot` 內在既有彙總迴圈補逐 model 聚合，並把新欄位傳進 snapshot：

```swift
        var perModelTotals: [String: AgentUsageTokenTotals] = [:]
        for bucket in includedBuckets {
            for (model, totals) in bucket.tokenTotalsByModel {
                perModelTotals[model, default: AgentUsageTokenTotals()].add(totals)
            }
        }
        let perModelBreakdown = perModelTotals
            .map { key, totals in
                AgentUsageModelBreakdownItem(
                    modelKey: key,
                    displayName: AgentUsageModelPricing.displayName(forModel: key),
                    tokenTotals: totals,
                    estimatedUSD: AgentUsageModelPricing.pricing(forModel: key).estimateUSD(for: totals)
                )
            }
            .sorted { lhs, rhs in
                if lhs.estimatedUSD == rhs.estimatedUSD { return lhs.modelKey < rhs.modelKey }
                return lhs.estimatedUSD > rhs.estimatedUSD
            }
```

回傳處補：

```swift
            perModelBreakdown: perModelBreakdown,
            perModelDailySpend: AgentUsageDashboardSnapshot.perModelDailySpend(
                now: now,
                buckets: document.buckets,
                calendar: calendar
            ),
```

- [x] 跑整包確認通過：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`。既有 `testSnapshotAggregatesSelectedRange` 的 `sevenDays.estimatedUSD == blend(140/60)` 斷言必須仍綠（舊桶 map 空、殘量 = aggregate、blend 對加總線性），這是舊資料 fallback 的回歸保護，不得改斷言來遷就實作
- [x] Commit：`feat: expose per-model breakdown and daily spend in usage snapshot`

---

### Task 8: i18n 新 key

**Files**

- Modify: `PingIsland/Resources/en.lproj/Localizable.strings`（統計區塊，615-632 行附近）
- Modify: `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`（同區塊，608-631 行附近）

**Interfaces**

- Produces：spec i18n 表的 6 個 key，簡體識別碼、`Text(appLocalized:)` / `AppLocalization.format` 查表。

**Steps**

- [x] `en.lproj/Localizable.strings` 在 `"Codex / Claude Code 均价"` 那行後加入：

```text
"各模型用量与花费" = "Per-Model Usage & Cost";
"按模型官方定价" = "Official per-model pricing";
"其他" = "Other";
"未知模型" = "Unknown model";
"每日花费" = "Daily cost";
"还没有可展示的模型数据" = "No per-model data yet";
```

- [x] `zh-Hant.lproj/Localizable.strings` 同位置加入（值必為繁體，逐字檢查用字）：

```text
"各模型用量与花费" = "各模型用量與花費";
"按模型官方定价" = "按模型官方定價";
"其他" = "其他";
"未知模型" = "未知模型";
"每日花费" = "每日花費";
"还没有可展示的模型数据" = "尚無可展示的模型資料";
```

- [x] 驗證兩檔語法：`plutil -lint PingIsland/Resources/en.lproj/Localizable.strings && plutil -lint PingIsland/Resources/zh-Hant.lproj/Localizable.strings`
- [x] Commit：`feat: add per-model usage i18n strings`

---

### Task 9: UI 各模型卡、多線圖、清單與 footer label

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/AgentUsagePerModelViews.swift`
- Modify: `PingIsland/UI/Views/Settings/Categories/AnalyticsSettingsView.swift`（`AgentUsageAnalyticsContent.body` 60-64 行、`spendCard` 106-112 行）
- Modify: `PingIsland/UI/Views/Settings/Categories/AgentUsageRows.swift`（`AgentUsageSpendPanel` 183-208 行、`AgentUsageSpendFooter` 211-271 行）

**Interfaces**

- Consumes：`AgentUsageModelBreakdownItem` / `AgentUsageModelDailySpend`（Task 7）、`AgentUsageSparklineStroke` + `smoothPath`（`AgentUsageCharts.swift:113-154`）、`AgentUsageEmptyLine` / `AgentUsageInsetDivider`（`AgentUsageRows.swift:507-529`）、`AgentUsageFormat.compactTokenCount` / `compactUSD` / `usd`、`TerminalColors`、`SettingsCategory.analytics.tint`、i18n key（Task 8）。
- Produces：

```swift
struct AgentUsagePerModelPanel: View {
    let breakdown: [AgentUsageModelBreakdownItem]
    let dailySpend: [AgentUsageModelDailySpend]
}
struct AgentUsagePerModelSpendChart: View { let series: [AgentUsagePerModelChartSeries] }
struct AgentUsageModelBreakdownList: View {
    let items: [AgentUsageModelBreakdownItem]
    let colorsByKey: [String: Color]
}
```

**Steps**

- [x] 建立 `PingIsland/UI/Views/Settings/Categories/AgentUsagePerModelViews.swift`：

```swift
import AppKit
import SwiftUI

private let perModelPalette: [Color] = [
    SettingsCategory.analytics.tint,
    TerminalColors.blue,
    TerminalColors.amber,
    TerminalColors.green,
    TerminalColors.cyan,
]
private let perModelOtherColor = Color.white.opacity(0.38)

// Deterministic color from the modelKey (not rank): the same model keeps its color
// across snapshots even when its ranking shifts. Chart, legend, and list share it.
// FNV-1a keeps the same hash on every launch, unlike String.hashValue (seeded per run).
private func perModelColor(forKey modelKey: String) -> Color {
    if modelKey == "__other__" { return perModelOtherColor }
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in modelKey.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return perModelPalette[Int(hash % UInt64(perModelPalette.count))]
}

struct AgentUsagePerModelChartSeries: Identifiable {
    let modelKey: String
    let displayName: String
    let values: [Double]   // 30 daily USD values, aligned with perModelDailySpend points
    let color: Color

    var id: String { modelKey }
}

struct AgentUsagePerModelPanel: View {
    let breakdown: [AgentUsageModelBreakdownItem]
    let dailySpend: [AgentUsageModelDailySpend]

    private static let maxLines = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if breakdown.isEmpty && dailySpend.isEmpty {
                AgentUsageEmptyLine(title: "还没有可展示的模型数据")
                    .padding(.vertical, 12)
            } else {
                Text(appLocalized: "每日花费")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))

                AgentUsagePerModelSpendChart(series: series)
                    .frame(height: 104)

                AgentUsagePerModelLegend(series: series)

                AgentUsageModelBreakdownList(items: breakdown, colorsByKey: colorsByKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Top 5 lines by totalUSD (dailySpend is already sorted descending); the rest are
    // merged pointwise into a single gray "其他" line.
    private var series: [AgentUsagePerModelChartSeries] {
        let top = Array(dailySpend.prefix(Self.maxLines))
        let rest = Array(dailySpend.dropFirst(Self.maxLines))

        var lines = top.map { spend in
            AgentUsagePerModelChartSeries(
                modelKey: spend.modelKey,
                displayName: spend.displayName,
                values: spend.points.map(\.estimatedUSD),
                color: perModelColor(forKey: spend.modelKey)
            )
        }

        if !rest.isEmpty {
            let dayCount = rest.first?.points.count ?? 0
            var merged = [Double](repeating: 0, count: dayCount)
            for spend in rest {
                for (index, point) in spend.points.enumerated() where index < merged.count {
                    merged[index] += point.estimatedUSD
                }
            }
            lines.append(AgentUsagePerModelChartSeries(
                modelKey: "__other__",
                displayName: "其他",
                values: merged,
                color: perModelOtherColor
            ))
        }

        return lines
    }

    // Same key, same color across chart, legend, and list rows.
    private var colorsByKey: [String: Color] {
        var colors: [String: Color] = [:]
        for line in series {
            colors[line.modelKey] = line.color
        }
        return colors
    }
}

struct AgentUsagePerModelSpendChart: View {
    let series: [AgentUsagePerModelChartSeries]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(series.flatMap(\.values).max() ?? 0, 0.000_1)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                ForEach(series) { line in
                    AgentUsageSparklineStroke(
                        points: points(for: line.values, in: proxy.size, maxValue: maxValue)
                    )
                    .stroke(
                        line.color.opacity(0.88),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    // y normalized against the max daily cost across ALL models and days.
    private func points(for values: [Double], in size: CGSize, maxValue: Double) -> [CGPoint] {
        let count = max(values.count - 1, 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(count) * size.width
            let y = size.height - CGFloat(value / maxValue) * (size.height * 0.84) - size.height * 0.08
            return CGPoint(x: x, y: y)
        }
    }
}

struct AgentUsagePerModelLegend: View {
    let series: [AgentUsagePerModelChartSeries]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(series) { line in
                HStack(spacing: 5) {
                    Circle()
                        .fill(line.color)
                        .frame(width: 7, height: 7)
                    Text(appLocalized: line.displayName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AgentUsageModelBreakdownList: View {
    let items: [AgentUsageModelBreakdownItem]
    let colorsByKey: [String: Color]

    var body: some View {
        if items.isEmpty {
            AgentUsageEmptyLine(title: "还没有可展示的模型数据")
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AgentUsageModelBreakdownRow(
                        item: item,
                        color: colorsByKey[item.modelKey] ?? perModelOtherColor
                    )
                    if index < items.count - 1 {
                        AgentUsageInsetDivider()
                    }
                }
            }
        }
    }
}

struct AgentUsageModelBreakdownRow: View {
    let item: AgentUsageModelBreakdownItem
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(appLocalized: item.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .help(item.modelKey)

            Spacer(minLength: 8)

            Text(verbatim: AppLocalization.format(
                "%@ Tokens",
                AgentUsageFormat.compactTokenCount(item.tokenTotal)
            ))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .help(AgentUsageFormat.integer(item.tokenTotal))

            Text(verbatim: AgentUsageFormat.compactUSD(item.estimatedUSD))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(TerminalColors.blue.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 56, alignment: .trailing)
                .help(AgentUsageFormat.usd(item.estimatedUSD))
        }
        .padding(.vertical, 9)
    }
}
```

- [x] 改 `AnalyticsSettingsView.swift`：`body` 的 `spendCard` 與 `activityMapCard` 之間插入 `perModelCard`，並新增：

```swift
    private var perModelCard: some View {
        SettingsSectionCard(title: "各模型用量与花费") {
            AgentUsagePerModelPanel(
                breakdown: viewModel.snapshot.perModelBreakdown,
                dailySpend: viewModel.snapshot.perModelDailySpend
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
```

`spendCard` 改為傳 pricing 標示旗標：

```swift
    private var spendCard: some View {
        SettingsSectionCard(title: "Token 费用预估") {
            AgentUsageSpendPanel(
                summary: viewModel.snapshot.spendSummary,
                // footer 呈現 30 天彙總，旗標用範圍無關的 perModelDailySpend（恆 30 天），
                // 不用隨 selectedRange 變動的 perModelBreakdown，避免旗標與 footer 範圍錯位。
                usesPerModelPricing: !viewModel.snapshot.perModelDailySpend.isEmpty
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
```

- [x] 改 `AgentUsageRows.swift`：`AgentUsageSpendPanel` 加 `let usesPerModelPricing: Bool` 並把它傳給 footer（`AgentUsageSpendFooter(summary: summary, usesPerModelPricing: usesPerModelPricing)`）；`AgentUsageSpendFooter` 加同名欄位，`pricingLabel` 改為：

```swift
    private var pricingLabel: some View {
        // 有逐 model 資料時標示官方定價；純舊資料（全 blend）維持均價標示。
        Text(appLocalized: usesPerModelPricing
            ? "按模型官方定价"
            : AgentUsageCostEstimator.blendedCodexClaudePricing.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.42))
            .lineLimit(1)
            .truncationMode(.middle)
    }
```

- [x] 建置確認綠：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`（若接管線過濾輸出，驗 `${PIPESTATUS[0]}` / zsh `${pipestatus[1]}`）
- [x] 跑整包單元測試確認綠：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- [x] Commit：`feat: add per-model usage and cost card to analytics settings`

---

### Task 10: 收尾驗證與文件同步

**Files**

- Modify: `AGENTS.md`（`PingIsland/Services/Usage` 兩處描述）
- Modify: `docs/superpowers/specs/2026-07-04-per-model-usage-cost-design.md`（狀態行）

**Steps**

- [x] 全量回歸：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`，再跑一次 Debug build，兩者 exit code 都必須為 0
- [x] 對照 spec 成功條件逐項檢核：新卡出現（清單依花費降序、多線圖含「其他」）、Opus 4.8 以 5/25 計、Haiku 1/5、gpt-5.5 5/30、未知走 blend、Codex cached 0.1x、headline 逐 model 加總、舊資料不歸零、英文介面無簡體洩漏（切 en 語系目視統計頁）
- [x] `AGENTS.md` 的 `PingIsland/Services/Usage` 兩處描述補「per-model official pricing / per-model usage breakdown」字樣，讓路由層反映 `AgentUsageModelPricing.swift` 與逐模型統計入口
- [x] spec 檔狀態行「待實作」改為「已實作（2026-07-04 plan 完成）」；若實作過程中任何決策偏離 spec，先改 spec 再收尾
- [x] Commit：`docs: sync AGENTS.md and spec status for per-model usage cost`
