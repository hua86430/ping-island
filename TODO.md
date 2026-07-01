# TODO

持續記錄待辦。做完打 `[x]`，新項目往「待處理」加。

## 待處理

- [ ] 殭屍卡：AskUserQuestion 提問卡清不掉 — 根因已定，實作中（獨立先做）
  - desc: `SessionStore.isQuestionToolPostToolUse` 要求 PostToolUse 的 `tool_use_id` 對上 intervention 存的 id 才清；當卡片來自無-id channel（Notification / routePromptsToTerminal suppress 路徑）時對不上 → 永不清 → 卡死。修法：PostToolUse 是 AskUserQuestion 且 intervention 沒有可比對 id 時直接清（tool 名相符即可），只有雙方都有 id 才嚴格比對。純邏輯、可單元測試。

- [ ] AskUserQuestion 島唯讀預覽 + 終端作答（B）— 待殭屍卡修完再做
  - desc: A 方案（非阻塞 + 島預覽）實測不可行（Claude 非阻塞時直接 dismiss 問題，無終端原生 picker）已 revert（c35acc4、14b84e3）。改 B：Settings toggle 預設關；開時 HookInstaller 把 Claude 的 PermissionRequest + PreToolUse 的 AskUserQuestion 排除（終端原生 picker）、toggle 改變 reinstall；島從 Notification channel 顯示唯讀預覽（`suppressInAppPromptControls`），點卡 focus 終端。實測確認 PermissionRequest 排除 → 終端原生 render 成立。

- [ ] cursor-follow：島跨螢幕跟隨游標、消除搬移延遲 — 計畫就緒，未實作
  - desc: spec `docs/superpowers/specs/2026-07-01-notch-follow-cursor-design.md`；plan `docs/superpowers/plans/2026-07-01-notch-follow-cursor.md`（commit d85e3fc）。

- [ ] Ctrl-C 退出的 session 殘留通知欄 — spec 就緒，未實作
  - desc: local Claude hook session `pid` 恆為 nil → 存活檢查跳過 → Ctrl-C 後卡 `.idle` 永不 `.ended`。修法：liveness sweep 用 `ProcessTreeBuilder` 查該 tty 上是否還有 `claude`。spec `docs/superpowers/specs/2026-07-01-ctrlc-session-liveness-design.md`。

## 已完成

- [x] tty-scoped session dedup（同資料夾不同終端不再併成一列）— 已發 0.24.3
- [x] 全專案簡體→繁體、語系選單只剩繁體中文 — 已發 0.24.4
- [x] 外接／非 notch 螢幕收合列高度依選單列對齊 — 已發 0.24.5
- [x] 免簽章 CI 自動發版（`release-unsigned.yml`，push `v*` tag）＋ AGENTS.md runbook
