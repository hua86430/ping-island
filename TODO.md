# TODO

持續記錄待辦。做完打 `[x]`，新項目往「待處理」加。

## 待處理

- [x] 殭屍卡：AskUserQuestion 提問卡清不掉 — 修好（commit 31f18d3，7 測試 + 全 suite 綠）
  - desc: `SessionStore.isQuestionToolPostToolUse` 要求 PostToolUse 的 `tool_use_id` 對上 intervention 存的 id 才清；當卡片來自無-id channel（Notification / routePromptsToTerminal suppress 路徑）時對不上 → 永不清 → 卡死。修法：PostToolUse 是 AskUserQuestion 且 intervention 沒有可比對 id 時直接清（tool 名相符即可），只有雙方都有 id 才嚴格比對。純邏輯、可單元測試。

- [x] AskUserQuestion 終端原生 picker + 島極簡唯讀提醒 — 定案（0.24.9）。0.24.6 只擋 hook 不夠；根因第二條路徑 applyClaudeTranscriptQuestionFallback（讀 transcript 重建，capture hook 實測證實）。0.24.7 全靜默 → 0.24.8 唯讀提醒 → 0.24.9 削成極簡單行「需要你回答 · 點一下到終端機作答」＋ 整卡可點 focus 終端（marker metadata["terminalRoutedReminder"] 僅 toggle 產生時打，routePromptsToTerminal 與一般問答卡不受影響；commit 609a6e0）。全 suite 綠。殭屍卡修正 31f18d3 自動生效。

- [~] AskUserQuestion reminder 點卡 focus 終端 — 0.24.11 修好兩個真 bug（各自驗過，端到端待你一次確認）
  - desc: (1) `HoverSessionCard` 對 attention/dashboard 卡傳 `opensOnTap:false`，唯讀 reminder 卡的 tap 從不觸發 activate → 對 terminalRoutedReminder bypass 該 guard（commit c3fb37c）。驗：你 04:17 在含此修正的 build 上真實點擊，log 出現 `SessionLauncher Activate request ... cc-workspace`（修正前 0 筆）。(2) Ghostty focus AppleScript 只 `focus <terminal>`（切 tab）沒 `activate`（抬 app）→ tell block 開頭加 `activate`。驗：實跑 AppleScript，frontmost Finder→ghostty。卡渲染從 image 20 確認。限制：受工具限（無 cliclick、notch 未自動彈合成 session）沒能單獨跑「一次點擊→抬前」端到端，兩段各自驗。「有時沒卡」= 問題已解決（transcript 有 tool_result）為正確行為，非 bug。


- [ ] cursor-follow：島跨螢幕跟隨游標、消除搬移延遲 — 計畫就緒，未實作
  - desc: spec `docs/superpowers/specs/2026-07-01-notch-follow-cursor-design.md`；plan `docs/superpowers/plans/2026-07-01-notch-follow-cursor.md`（commit d85e3fc）。

- [ ] Ctrl-C 退出的 session 殘留通知欄 — spec 就緒，未實作
  - desc: local Claude hook session `pid` 恆為 nil → 存活檢查跳過 → Ctrl-C 後卡 `.idle` 永不 `.ended`。修法：liveness sweep 用 `ProcessTreeBuilder` 查該 tty 上是否還有 `claude`。spec `docs/superpowers/specs/2026-07-01-ctrlc-session-liveness-design.md`。

## 已完成

- [x] tty-scoped session dedup（同資料夾不同終端不再併成一列）— 已發 0.24.3
- [x] 全專案簡體→繁體、語系選單只剩繁體中文 — 已發 0.24.4
- [x] 外接／非 notch 螢幕收合列高度依選單列對齊 — 已發 0.24.5
- [x] 免簽章 CI 自動發版（`release-unsigned.yml`，push `v*` tag）＋ AGENTS.md runbook
