# TODO

持續記錄待辦。做完打 `[x]`，新項目往「待處理」加。

## 待處理

- [x] 懸浮寵物模式 lockout：拖曳離島變寵物後點不到寵物就開不了設定 — 逃生口已於 0.26.0 補上
  - desc: docked notch 拖曳可 detach 成獨立懸浮寵物（surfaceMode `.floatingPet`）。原本鎖死：變寵物後若點不到那隻寵物（被別視窗蓋住、拖到邊角、hit region 太小），沒有備援入口能開設定或 re-dock。0.26.0 加了常駐 menu bar 狀態列選單（`StatusBarController`；`AppDelegate` :59 無條件建立，只有測試跳過）當逃生口：開設定、「展示模式」子選單直接切回刈海（`.notch`）/ 懸浮寵物、退出。lockout 解除。殘留（非 lockout，UX polish、可另開小項）：「拖回頂部 re-dock」手勢仍不好發現，例如右鍵寵物選「回到刈海」或拖曳時提示。

- [x] 全 app 簡體中文清零（繁化總掃）— 完成，scanner 綠、build 綠、guard test 綠
  - desc: guard scanner `scripts/check-simplified-chinese.swift`（ICU Hans-Hant 逐字，key-aware：Simplified Swift literal 若是已解析 zh-Hant key 則放行；matcher 用 `// i18n:simplified-matcher-*` 區塊標記排除，非行號白名單）。實作分三路：(1) zh-Hant.lproj 2 筆殘留值就地改繁（占→佔 行 54/168）+ 補 en-only 缺的 1 key；(2) 40 個 lookup key（`Text(appLocalized:)`/`AppLocalization.format`）補 en + zh-Hant 值、保留簡體 key；(3) 113 個硬編/enum/插值 literal 就地繁化（quote-delimited 全字串比對，避免短詞誤傷長 literal）。matcher 保留簡體並加區塊標記：`SessionState` 4 個進度陣列 + `SessionStore` 2 個 Qoder 提問偵測函式；`SessionStore` 提問卡 DISPLAY 字串照樣繁化。回歸：`PingIslandTests/SimplifiedChineseGuardTests.swift`（zh-Hant 值 ICU 檢查 + scanner 檔存在）；scanner 併入 `scripts/test.sh` 第一步。`SettingsWindowControllerTests`（斷言簡體 key 存在）續綠。spec `docs/superpowers/specs/2026-07-04-full-app-traditional-chinese-sweep-design.md`；plan `docs/superpowers/plans/2026-07-04-full-app-traditional-chinese-sweep.md`。commit 待使用者確認 Jira ticket。

- [x] 通知 feed 自動彈開切開（auto-open decoupling）— 已發 0.25.0（含懸停延遲/動畫時長滑桿、助理回覆才算未讀）
  - desc: feed mode 下:開新 session/打字永不彈;提問/審批照彈且留;回覆完成 → 彈 feed banner 5 秒自收（hover 暫停、移開即收、自癒 re-arm）;session mode 逐位元組不變（決策 log 證明）。live 實測抓到並修掉 willSet-stale arming + stuck-open;既有完成卡 presenter 在本機從不 present = 既有謎、另開診斷（feed banner 已補位）。spec `docs/superpowers/specs/2026-07-02-feed-mode-auto-open-design.md`;證據 `.superpowers/sdd/feed-autoopen-selftest-report.md`。

- [x] 通知中心模式（notification feed）— 完成（0.24.12）。live 實測全過（證據 .superpowers/sdd/feed-selftest-report.md：徽章/開島 feed/點列 focus+清除/清除全部/重啟清空/關閉 parity 全部截圖驗證；實測抓到面板高度 bug 已修 67cbd9b）
  - desc: toggle `notificationFeedMode` 預設關。開時展開島只列未讀 session（`hasUnread` = lastActivity > lastSeenAt，記憶體、重啟清空、不受 30 分自動隱藏）、點列 focus 終端＋標已讀、右上清除全部、收合島顯示未讀數。spec `docs/superpowers/specs/2026-07-02-notification-feed-mode-design.md`；commits 6adec30 de0a83d 7542603 73bb8c8 301bdc6；全 suite 綠、各 task review Approved。


- [x] 殭屍卡：AskUserQuestion 提問卡清不掉 — 修好（commit 31f18d3，7 測試 + 全 suite 綠）
  - desc: `SessionStore.isQuestionToolPostToolUse` 要求 PostToolUse 的 `tool_use_id` 對上 intervention 存的 id 才清；當卡片來自無-id channel（Notification / routePromptsToTerminal suppress 路徑）時對不上 → 永不清 → 卡死。修法：PostToolUse 是 AskUserQuestion 且 intervention 沒有可比對 id 時直接清（tool 名相符即可），只有雙方都有 id 才嚴格比對。純邏輯、可單元測試。

- [x] AskUserQuestion 終端原生 picker + 島極簡唯讀提醒 — 定案（0.24.9）。0.24.6 只擋 hook 不夠；根因第二條路徑 applyClaudeTranscriptQuestionFallback（讀 transcript 重建，capture hook 實測證實）。0.24.7 全靜默 → 0.24.8 唯讀提醒 → 0.24.9 削成極簡單行「需要你回答 · 點一下到終端機作答」＋ 整卡可點 focus 終端（marker metadata["terminalRoutedReminder"] 僅 toggle 產生時打，routePromptsToTerminal 與一般問答卡不受影響；commit 609a6e0）。全 suite 綠。殭屍卡修正 31f18d3 自動生效。

- [x] AskUserQuestion reminder 點卡 focus 終端 — 0.24.11 修好兩個真 bug，使用者 2026-07-03 端到端確認通過（點擊 → 終端抬前）
  - desc: (1) `HoverSessionCard` 對 attention/dashboard 卡傳 `opensOnTap:false`，唯讀 reminder 卡的 tap 從不觸發 activate → 對 terminalRoutedReminder bypass 該 guard（commit c3fb37c）。驗：你 04:17 在含此修正的 build 上真實點擊，log 出現 `SessionLauncher Activate request ... cc-workspace`（修正前 0 筆）。(2) Ghostty focus AppleScript 只 `focus <terminal>`（切 tab）沒 `activate`（抬 app）→ tell block 開頭加 `activate`。驗：實跑 AppleScript，frontmost Finder→ghostty。卡渲染從 image 20 確認。限制：受工具限（無 cliclick、notch 未自動彈合成 session）沒能單獨跑「一次點擊→抬前」端到端，兩段各自驗。「有時沒卡」= 問題已解決（transcript 有 tool_result）為正確行為，非 bug。


- [x] 完成卡 presenter 在本機從不 present — 0.26.2 修好（根因是完成偵測時序競態）
  - desc: 根因不在 presenter，在完成判斷 `SessionCompletionStateEvaluator.isCompletedReadySession`。Claude 的 assistant 回覆在 `Stop→waitingForInput` 之後約 100ms+ 才從 transcript 解析進 chatItems，idle 期間沒有其他 parse 觸發，加上 claude-mem 在回覆後注入 trailing 工具活動，使「最後一個 chat item 是 assistant」永遠不成立 → `completedReady` 從沒到 1 → 完成音與完成卡 presenter 都不觸發。0.26.2 改用 `Stop` 權威訊號：`SessionState.assistantTurnCompleted`（`SessionStore.processHookEvent` 設、`isCompletedReadySession` 認）。實機驗證（CoreAudio process tap，log 05:15:09）：completedReady 在 Stop 當下 0→1、`notch OPEN reason=notification`、完成音有實際音訊輸出。完成 panel 本身共用同一 gate、應一併 present；建議實際看一次確認。commit 4e3571a、release 0.26.2。

- [x] cursor-follow：島跨螢幕跟隨游標、消除搬移延遲 — 實作完成，執行期實測核心行為通過
  - desc: spec `docs/superpowers/specs/2026-07-01-notch-follow-cursor-design.md`；plan `docs/superpowers/plans/2026-07-01-notch-follow-cursor.md`（commit d85e3fc）。實作 commits 7f7fc05（`NotchWindowController.moveToScreen` + frame helper，2 test）、7c6dd26（純 `NotchScreenMigrationDecider`，7 test）、3ca6de8（`WindowManager` 訂閱 `EventMonitors.mouseLocation`、走 `updateScreen`→`moveToScreen` cheap path、focus 遷移改用 `migrate`；AGENTS.md）。全 `PingIslandTests` 綠。執行期實測（2 外接螢幕、合成 mouseMoved 事件驅動 fresh Debug build）：0→1 遷移 PASS（notch x=0→2560）、dwell gate 不即時遷移 PASS、cheap path 無 rebuild（migrate() 不碰 setupNotchWindow）。未執行期驗：specific-screen 不遷移（僅 decider guard 單元測試）、內建↔外接 notch 高度（測時 clamshell 無 active 內建）。

- [x] 設定視窗原生化重寫（NavigationSplitView + macOS 26 Liquid Glass）— 已發 0.25.3
  - desc: 6900+ 行 `SettingsWindowView.swift` 單體檔重構為一檔一責模組（`PingIsland/UI/Views/Settings/`：SettingsRootView 殼 + SettingsSidebarView + SettingsDetailRouter + SettingsPanelViewModel + Components/ + Categories/ 十分類各一檔），搬移不改行為。視窗換原生 titled chrome（真紅綠燈／可拖／最小化／縮放、原生陰影），移除 popover 死碼。sidebar 扁平單行 + 彩色 icon + 原生選中高亮；chrome 改用原生 safe area + `hostingController.sizingOptions = []`（不 hardcode 位移／尺寸）。CI 用 macOS 26 SDK（release-unsigned.yml select Xcode 26）編 → macOS 26 上 sidebar 採 Liquid Glass；deployment target 維持 14。spec `docs/superpowers/specs/2026-07-03-settings-navigation-split-design.md`、plan `docs/superpowers/plans/2026-07-03-settings-navigation-split.md`；merge b3e8ef1、release d4bd7ac。build／unit／UI 全綠（Xcode 26 SDK）。

- [ ] 簽章發版（release-packages.yml）補 Xcode 26 select — 未做
  - desc: 目前只有 `release-unsigned.yml` 加了「Select Xcode 26」步驟。`release-packages.yml`（Developer ID + notarize、workflow_dispatch-only、tag 不觸發）仍是 macos-15 預設 Xcode 16，走簽章發版出的包在 macOS 26 上不會有 Liquid Glass。要比照補同樣 select 步驟。

- [x] macOS 26 SDK 全 app 外觀掃查 — 使用者確認 OK

- [ ] Ctrl-C 退出的 session 殘留通知欄 — spec 就緒，未實作
  - desc: local Claude hook session `pid` 恆為 nil → 存活檢查跳過 → Ctrl-C 後卡 `.idle` 永不 `.ended`。修法：liveness sweep 用 `ProcessTreeBuilder` 查該 tty 上是否還有 `claude`。spec `docs/superpowers/specs/2026-07-01-ctrlc-session-liveness-design.md`。

## 已完成

- [x] tty-scoped session dedup（同資料夾不同終端不再併成一列）— 已發 0.24.3
- [x] 全專案簡體→繁體、語系選單只剩繁體中文 — 已發 0.24.4
- [x] 外接／非 notch 螢幕收合列高度依選單列對齊 — 已發 0.24.5
- [x] 免簽章 CI 自動發版（`release-unsigned.yml`，push `v*` tag）＋ AGENTS.md runbook
