# Full-App Traditional Chinese Sweep — Implementation Plan

Date: 2026-07-04
Spec: `docs/superpowers/specs/2026-07-04-full-app-traditional-chinese-sweep-design.md`
Goal: Remove all user-visible Simplified Chinese (values, missing-key fallbacks, hardcoded literals, picker/dropdown labels) while keeping Simplified localization KEYS and Simplified agent-text MATCHERS intact. Add a guard so it cannot regress.

Conventions for this plan:
- All paths absolute-from-repo-root. Line numbers are as of 2026-07-04 HEAD; re-locate with ripgrep if drifted.
- Each task ends with a verification. The repeated guard command is defined in Task 0.
- KEYS (left of `=`, and `key` args) are NEVER edited. VALUES and rendered literals ARE.
- Trap words (spec §5.1) MUST use the context-correct form, not the ICU default: 复制→複製, 回复→回覆, 答复→答覆, 标准→標準, 准备→準備, …里(locative)→…裡, 关系→關係.

---

## Task 0 — Land the guard scanner first (fail-first)

- [ ] Create `scripts/check-simplified-chinese.swift` containing the ICU `Hans-Hant` per-character scanner (below). It scans `PingIsland/` app code (exclude `PingIslandTests/`, `PingIslandUITests/`) + `PingIsland/Resources/zh-Hant.lproj/Localizable.strings` VALUES, flags any character whose single-char Hans→Hant transform changes it, and exits non-zero on any hit not in the whitelist.
- [ ] Whitelist exactly the §4.5 matcher lines by `file:line` (SessionState + SessionStore ranges) so they are allowed to stay Simplified.
- [ ] Scanner logic (reuse the audit scanner):
  - `StringTransform("Hans-Hant")`; a char is flagged if `String(char).applyingTransform(t, reverse:false) != String(char)` and scalar in `0x3400…0x9FFF`.
  - `.strings`: parse `"key" = "value";`, check VALUE only.
  - Swift: extract string literals via regex, skip pure-comment lines, report `file:line` + literal.
  - Print each violation; `exit(1)` if any non-whitelisted violation remains.
- [ ] Run it now and confirm it FAILS with the known ~120 display + 2 value + 41 missing-key findings (proves the guard detects the problem before any fix).
- [ ] Verify: `swift scripts/check-simplified-chinese.swift; echo "exit=$?"` → prints violations, `exit=1`.

Add a repo entry point (choose one, keep it in `AGENTS.md` Build And Test):
- [ ] Add `./scripts/check-simplified-chinese.swift` invocation as a step in `scripts/test.sh` (non-fatal note now, fatal after the sweep) OR document it as a standalone check.
- [ ] Verify: `rg -n "check-simplified-chinese" scripts/test.sh AGENTS.md` returns matches.

Guard command referenced by later tasks:
```
swift scripts/check-simplified-chinese.swift
```

---

## Task 1 — Fix the two `.strings` VALUE survivors + the missing key

File: `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`

- [ ] Line 54 value: change `…的額度占用率與重置時間` → `…的額度佔用率與重置時間` (占→佔). Key unchanged.
- [ ] Line 168 value: change `最大日誌占用` → `最大日誌佔用` (占→佔). Key unchanged.
- [ ] Add a zh-Hant value for the key present only in `en.lproj`: `这会重新生成 %@ 的 Island 插件目录，并覆盖旧的 Island 托管版本。` → value `這會重新產生 %@ 的 Island 外掛目錄，並覆蓋舊的 Island 託管版本。` (verify 复盖→覆蓋, 旧→舊, 插件/外掛 wording matches sibling entries).
- [ ] Verify: `rg -n "占用" PingIsland/Resources/zh-Hant.lproj/Localizable.strings` returns zero. Guard scanner reports zero `.strings` value hits.

---

## Task 2 — Add zh-Hant (+en) VALUES for the 41 missing lookup keys (no Swift change)

Add entries to BOTH `PingIsland/Resources/zh-Hant.lproj/Localizable.strings` (Traditional value) and `PingIsland/Resources/en.lproj/Localizable.strings` (English value). Keys stay Simplified (spec §4.3 list). Work file-by-file so the guard shrinks visibly.

- [ ] AboutSettingsView keys (13): `静默更新中`→`靜默更新中`, `等待重启安装`→`等待重啟安裝`, `正在安装更新`→`正在安裝更新`, `正在后台检查更新`→`正在後台檢查更新`, `发现新版本 v%@，将静默下载并安装`→`發現新版本 v%@，將靜默下載並安裝`, `正在后台下载更新`→`正在後台下載更新`, `正在准备安装更新`→`正在準備安裝更新` (准→準!), `v%@ 已就绪，可立即重启安装，或等空闲时自动安装`→`v%@ 已就緒，可立即重啟安裝，或等空閒時自動安裝`, `正在静默安装并重启`→`正在靜默安裝並重啟`, `后台更新失败，点击后重新检查`→`後台更新失敗，點擊後重新檢查`.
- [ ] IntegrationSettingsView keys (13): `添加自定义配置`→`新增自訂設定`, `添加自定义 Hook 配置`→`新增自訂 Hook 設定`, `选择应用`→`選擇應用程式`, `请选择...`→`請選擇...`, `安装目录`→`安裝目錄`, `选择目录`→`選擇目錄`, the OpenClaw/Hermes directory blurbs, `安装后将写入: %@/%@`→`安裝後將寫入: %@/%@`, `安装后将写入: %@`, `选择 Hook 配置目录`→`選擇 Hook 設定目錄`, `选择`→`選擇`, `静默时长`→`靜默時長`.
- [ ] SettingsDetailRouter keys (5): `正在加载%@设置…`→`正在載入%@設定…`, `正在刷新显示器与用量展示状态`→`正在重新整理顯示器與用量展示狀態`, `正在扫描可用声音主题包`→`正在掃描可用聲音主題包`, `正在检查 Hooks、IDE 扩展与客户端安装状态`→`正在檢查 Hooks、IDE 擴充功能與用戶端安裝狀態`, `马上就好`→`馬上就好`.
- [ ] ChatView keys (4): `打开终端`→`開啟終端機`, `%@ 已在客户端中发起追问，请打开并继续回答。`→`%@ 已在用戶端發起追問，請開啟並繼續回答。`, `终端`→`終端機`, `已保留在终端中处理`→`已保留在終端機中處理`.
- [ ] SessionListView native-runtime keys (3): `Native runtime 正在处理…`→`Native runtime 正在處理…`, `Native session 已就绪`→`Native session 已就緒`, `Native session 已结束`→`Native session 已結束`.
- [ ] MascotSettingsView / MascotView keys (3): `空闲保护`→`空閒保護`, `%@ %@ 空闲保护中`→`%@ %@ 空閒保護中`, and the idle-protection long blurb `全局键鼠静默达到设定时长后，宠物右下角会显示绿色盾牌，表示后续新审批和提问将保留在终端。`→`全域鍵鼠靜默達到設定時長後，寵物右下角會顯示綠色盾牌，表示後續新審批和提問將保留在終端機。`.
- [ ] CodexSessionView / SessionHoverPreviewView shared key `终端`→`終端機` (same entry as ChatView; add once).
- [ ] DisplaySettingsView key `宠物大小`→`寵物大小`; RemoteSettingsView key `端口需为 1 到 65535`→`連接埠需為 1 到 65535`; RemoteConnectorManager key `下载地址无效：%@`→`下載位址無效：%@`.
- [ ] The three terminal-routed-notice callsites (`ChatView:683`, `CodexSessionView:197`, `SessionHoverPreviewView:667`) share the KEY `已保留在%@中处理。Ping Island 只提醒，不接管此处响应。` — add value `已保留在%@中處理。Ping Island 只提醒，不接管此處回應。` (this fixes all three without editing Swift).
- [ ] Verify: `swift scripts/check-simplified-chinese.swift` no longer lists any of these keys' callsites. Build succeeds: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug build`.

---

## Task 3 — Convert picker/dropdown enum labels (Settings.swift)

File: `PingIsland/Core/Settings.swift`. Convert the returned literals to Traditional (spec §4.4 table). These are `%@`-arg / `Text(appLocalized:)`-key sources; converting the literal makes every consumption path render Traditional.

- [ ] `UserIdleAutoProtectionDuration.title` (:164–170): `分钟`→`分鐘`, `小时`→`小時`.
- [ ] `FloatingPetSizeMode.title`/`subtitle` (:272–286): `标准`→`標準`, `较大`→`較大`, plus the three subtitles (`按显示器分辨率调整，高分屏会更醒目`→`依顯示器解析度調整，高解析螢幕會更醒目`, `固定为旧版悬浮宠物尺寸`→`固定為舊版懸浮寵物尺寸`, `在所有显示器上放大宠物形象`→`在所有顯示器上放大寵物形象`).
- [ ] `SubagentVisibilityMode.title`/`subtitle` (:299–310): `不显示`→`不顯示`, `显示`→`顯示`, and the two subtitles (`主列表里…`→`主列表裡…` — 里→裡 trap).
- [ ] Mascot style `title` (:345–361) and `subtitle` (:368–386): all entries per §4.4 (verify 团→糰? no — 团子 is a name; keep meaning, use 團 for 团: `团子猫`→`糰子貓`? Decide naming — use 團 unless a product name; confirm with existing mascot naming in `MascotView`/GIF assets before finalizing).
- [ ] `AppLanguage.title` `跟随系统`→`跟隨系統` (:36) if rendered raw; if via `Text(appLocalized:)` with a value, prefer adding a `.strings` value instead. Check consumption first: `rg -n "AppLanguage|appLanguage.*title|\.title\)" PingIsland/UI/Views/Settings`.
- [ ] Verify: guard scanner reports zero `Settings.swift` hits. Manual: open Settings, each of these dropdowns shows Traditional. Build succeeds.

---

## Task 4 — Convert remaining view-layer raw literals

Convert Simplified literals rendered via `Text(verbatim:)` / `Text(String)` / interpolation (spec §4.4 "View-layer" + enum/label sub-lists). Per file:

- [ ] `PingIsland/Core/SoundPackCatalog.swift:272`: `未选择`→`未選擇`.
- [ ] `PingIsland/UI/Views/Settings/SettingsCategory.swift:27,39,42`: `实验室`→`實驗室`, `Agent、Token 与工具`→`Agent、Token 與工具`, `试验性特性`→`試驗性特性`. (If consumed via `Text(appLocalized: category.title)`, adding `.strings` values is the alternative; converting the literal is simpler and uniform.)
- [ ] `PingIsland/UI/Views/NotchView.swift:750,1872`: `需要处理`→`需要處理`, `设置`→`設定`.
- [ ] `PingIsland/UI/Views/SessionListView.swift:385,386`: `选择 \(provider.displayName) Native Runtime 工作目录`→`選擇 …工作目錄`, `启动`→`啟動`.
- [ ] `PingIsland/UI/Views/Settings/Categories/AboutSettingsView.swift:21,23,29,59,60`: privacy/analytics labels + restart labels.
- [ ] `PingIsland/UI/Views/Settings/Categories/DisplaySettingsView.swift:35,99,100`: display-mode blurb, `宠物大小`→`寵物大小`, auto-mode blurb.
- [ ] `PingIsland/UI/Views/Settings/Categories/IntegrationSettingsView.swift:89,90,96,98,99`: idle-protection toggle labels/blurbs.
- [ ] `PingIsland/UI/Views/Settings/Categories/LabsSettingsView.swift:6,30,34`: `实验室`→`實驗室`, `暂无可用实验`→`暫無可用實驗`, blurb.
- [ ] `PingIsland/UI/Views/Settings/Categories/SoundSettingsView.swift:390`: `试听`→`試聽`.
- [ ] `PingIsland/UI/Views/Settings/Categories/RemoteSettingsView.swift:324`: `SSH attach 已断开: `→`SSH attach 已斷開: `.
- [ ] `PingIsland/UI/Views/Settings/SettingsPanelViewModel.swift:470`: Qoder CLI detection blurb (long; convert per §5).
- [ ] `PingIsland/UI/Components/MascotView.swift` `subtitle`/`defaultMascotName`/hook-summary lines (:81–113, :313–338): convert all mascot names/blurbs.
- [ ] Verify: guard scanner reports zero hits in these files. Build succeeds.

---

## Task 5 — Convert model-layer interpolated display strings (nonisolated; convert in place, do NOT call AppLocalization)

- [ ] `PingIsland/Models/SessionEvent.swift:382,383,452,453,467,469`: `\(actorName) 请求处理`→`\(actorName) 請求處理`, waiting/summary/question strings per §4.4.
- [ ] `PingIsland/Models/SessionProvider.swift:477,1081`: `\(ideTitle) 终端`→`\(ideTitle) 終端機`, intervention hint.
- [ ] `PingIsland/Services/Session/ConversationParser.swift:1045,1048,1240,1241,1258,1480,1481,1487`: `问题：`→`問題：`, `回答：`→`回答：`, Qoder question titles/messages.
- [ ] `PingIsland/Services/State/SessionStore.swift:4147,4148,4173,4198,4199,4205`: question card titles/messages (the DISPLAY block only — NOT 4243–4288).
- [ ] `PingIsland/Models/SessionState.swift` DISPLAY strings only: convert `providerDisplayName`/`clientDisplayName`-adjacent rendered strings if flagged, but LEAVE the matcher arrays at :725–731/:745–748/:797–818 (Task 7 whitelist).
- [ ] `PingIsland/Models/ClientProfile.swift:300–304` and the `subtitle:` fields (`管理 ~/.pi/agent/… 接入 Island`, etc.): convert to Traditional (`管理 ~/.pi/agent/extensions/ping_island，依 Pi 官方 extension 機制接入 Island`, …). `reinstallDescriptionFormat` cases (:300–304) become Traditional (matches the value added in Task 1).
- [ ] `PingIsland/Services/Remote/RemoteConnectorManager.swift:1841,2068,2395`: SSH/download error strings (`已断开`→`已斷開`, `写入远程文件失败`→`寫入遠端檔案失敗`, `无法从 GitHub Release 下载 Linux 远程 bridge：%@`→`無法從 GitHub Release 下載 Linux 遠端 bridge：%@`).
- [ ] Verify: guard scanner reports zero hits in these files (except whitelisted SessionStore matcher block). Build succeeds.

---

## Task 6 — Convert update-driver + release-notes strings

- [ ] `PingIsland/Services/Update/NotchUserDriver.swift` (17 sites, :37–603): convert all status/error literals to Traditional (§4.4). `@MainActor` — convert in place (minimal) or route through `AppLocalization` if you prefer key/value; either is acceptable here.
- [ ] `PingIsland/Services/Update/UpdateReleaseNotes.swift:35,39,47` (spec §4.6 — matcher against Traditional notes): `亮点`→`亮點`, `修复`→`修復`, `关联 pr`→`關聯 pr`. This both removes Simplified AND fixes icon selection for Traditional release notes. Keep the English `.contains("highlight"/"fix"/"related pr")` branches.
- [ ] Verify: guard scanner reports zero hits in these two files. Build succeeds. Sanity: a Traditional-authored release note section titled `亮點` now selects the `sparkles` icon.

---

## Task 7 — Confirm matchers stay Simplified (whitelist audit)

These MUST remain Simplified (spec §4.5) because they match Simplified agent output. Verify no task touched them.

- [ ] `PingIsland/Models/SessionState.swift:725,726,728,729,731,745,746,748,797,798,800,801,817,818` unchanged.
- [ ] `PingIsland/Services/State/SessionStore.swift:4243,4244,4252,4253,4268,4269,4270,4271,4280,4281,4287,4288` unchanged.
- [ ] Confirm the scanner whitelist covers exactly these lines and nothing else.
- [ ] Verify: `git diff PingIsland/Models/SessionState.swift PingIsland/Services/State/SessionStore.swift` shows no change inside these ranges.

---

## Task 8 — Guard test in the Xcode test target

Turn the scanner into a regression test so CI fails on reappearance.

- [ ] Add `PingIslandTests/SimplifiedChineseGuardTests.swift` with one test that:
  - Reads `zh-Hant.lproj/Localizable.strings` from the test bundle, asserts no VALUE contains a Simplified character (reuse the ICU `Hans-Hant` per-char check).
  - Asserts the guard script exists and (optionally, if the test host allows spawning) shells out to `scripts/check-simplified-chinese.swift` and asserts exit 0.
  - Keeps the §4.5 whitelist in sync with `scripts/check-simplified-chinese.swift` (single source of truth: have the test read the script's whitelist, or duplicate with a comment cross-referencing the spec).
- [ ] Keep the existing `SettingsWindowControllerTests` zh-Hant assertions intact (they assert Simplified KEYS exist — that is the KEY convention, not a violation).
- [ ] Verify: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests` passes, including the new guard test and unchanged `SettingsWindowControllerTests`.

---

## Task 9 — Final verification + docs

- [ ] Guard clean: `swift scripts/check-simplified-chinese.swift; echo "exit=$?"` → `exit=0` (only §4.5 whitelist remains Simplified).
- [ ] `rg` spot-checks return zero in zh-Hant values and converted files, e.g.:
  - `rg -n "占用|后台|发现|标准|准备|终端(?!機)" PingIsland --glob '*.swift' --glob '!*Tests*'` (adjust; expect only whitelisted matcher hits).
- [ ] Build: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug build` succeeds.
- [ ] Unit tests: `xcodebuild … test -only-testing:PingIslandTests` green.
- [ ] Full regression: `./scripts/test.sh`.
- [ ] Manual GUI pass: every Settings dropdown/picker (display mode, pet size, subagent visibility, mascot style, sound theme + pack fallback, idle duration, language, category sidebar) + About update states + session cards/notices show zero Simplified.
- [ ] Update `AGENTS.md` Build And Test with the new guard command and note the KEY-Simplified / VALUE-Traditional / MATCHER-Simplified rule so future contributors don't "fix" the whitelist.
- [ ] Mark the TODO.md item done and record commits.

---

## Verification summary (per the spec success criteria)

| Criterion | Check |
|---|---|
| zh-Hant values Traditional-only | Task 1, guard scanner, Task 8 test |
| No missing-key Simplified fallback | Task 2, guard scanner |
| Hardcoded literals Traditional | Tasks 3–6, guard scanner |
| Trap words correct (複製/回覆/答覆/標準/準備/裡/關係) | Tasks 2–6 manual review vs spec §5.1 |
| Build green | `xcodebuild … build` |
| SettingsWindowControllerTests green | Task 8 |
| Regression guard exists | Tasks 0 + 8 |
| Matchers untouched | Task 7 |
