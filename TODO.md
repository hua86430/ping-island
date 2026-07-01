# TODO

持續記錄待辦。做完打 `[x]`，新項目往「待處理」加。

## 待處理

- [ ] AskUserQuestion 劫持改非阻塞預覽 — brainstorming 進行中
  - desc: PingIsland 現在把 Claude Code 的 AskUserQuestion 攔成阻塞卡片、在島裡作答並回填終端（`expectsResponse` blocking）。想改成：島只做非阻塞「預覽」（看得到有問題＋選項），問答輸出留在終端原生流程，不劫持。現成參考：`HookPayloadMapper` 的 `routePromptsToTerminal`、QoderWork 的 notify-only 模型。

- [ ] cursor-follow：島跨螢幕跟隨游標、消除搬移延遲 — 計畫就緒，未實作
  - desc: automatic 模式下 docked notch 依游標跨螢幕即時移動（reposition 不重建）＋ dwell 0.2s。spec `docs/superpowers/specs/2026-07-01-notch-follow-cursor-design.md`；plan `docs/superpowers/plans/2026-07-01-notch-follow-cursor.md`（commit d85e3fc）。

- [ ] Ctrl-C 退出的 session 殘留通知欄 — 已查根因，未 brainstorming／未修
  - desc: local hook session 的 `pid` 恆為 nil，`pruneOrphanedSessions` / `sweepDeadOrEndedSessions` 遇 nil pid 都跳過；Ctrl-C 沒送 clean Stop → session 卡 `.idle` 永不 `.ended` → 通知欄殘留。修法方向：用 tty 判該終端是否還有活著的 `claude`。

## 已完成

- [x] tty-scoped session dedup（同資料夾不同終端不再併成一列）— 已發 0.24.3
- [x] 全專案簡體→繁體、語系選單只剩繁體中文 — 已發 0.24.4
- [x] 外接／非 notch 螢幕收合列高度依選單列對齊（不再寫死 32）— 已發 0.24.5
- [x] 免簽章 CI 自動發版（`release-unsigned.yml`，push `v*` tag 自動出 release）＋ AGENTS.md runbook — 完成
