# TODO

持續記錄待辦。做完打 `[x]`，新項目往「待處理」加。

## 待處理

- [ ] AskUserQuestion 劫持改非阻塞預覽 — spec 就緒，未實作
  - desc: 加一個 opt-in 設定 toggle（預設關）。開了 → Claude AskUserQuestion 非阻塞（終端 render 原生 picker），島只顯示唯讀預覽；關了維持現況。spec `docs/superpowers/specs/2026-07-01-askuserquestion-preview-design.md`。

- [ ] cursor-follow：島跨螢幕跟隨游標、消除搬移延遲 — 計畫就緒，未實作
  - desc: automatic 模式下 docked notch 依游標跨螢幕即時移動（reposition 不重建）＋ dwell 0.2s。spec `docs/superpowers/specs/2026-07-01-notch-follow-cursor-design.md`；plan `docs/superpowers/plans/2026-07-01-notch-follow-cursor.md`（commit d85e3fc）。

- [ ] Ctrl-C 退出的 session 殘留通知欄 — spec 就緒，未實作
  - desc: local Claude hook session `pid` 恆為 nil → 存活檢查跳過 → Ctrl-C 後卡 `.idle` 永不 `.ended`。修法：liveness sweep 對「本機 Claude、有 tty、無 pid」的 session 用 `ProcessTreeBuilder` 查該 tty 上是否還有 `claude`，有就補 pid、沒有就判 `.ended` 移除；remote/tmux-unresolvable 排除。spec `docs/superpowers/specs/2026-07-01-ctrlc-session-liveness-design.md`。

## 已完成

- [x] tty-scoped session dedup（同資料夾不同終端不再併成一列）— 已發 0.24.3
- [x] 全專案簡體→繁體、語系選單只剩繁體中文 — 已發 0.24.4
- [x] 外接／非 notch 螢幕收合列高度依選單列對齊（不再寫死 32）— 已發 0.24.5
- [x] 免簽章 CI 自動發版（`release-unsigned.yml`，push `v*` tag 自動出 release）＋ AGENTS.md runbook — 完成
