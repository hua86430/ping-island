# 實作計畫：常駐選單列狀態項 + 懸浮寵物拖曳修復與拖回瀏海

- 對應 spec：`docs/superpowers/specs/2026-07-04-menubar-status-item-and-pet-drag-design.md`
- 原則：exact file:line、與核准設計 1:1、不擴 scope。spec 若因診斷結果改變，先改 spec 再繼續。

## 驗證指令（各 task 引用）

- Build：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- 單元測試：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- 簡體字 guard：`swift scripts/check-simplified-chinese.swift`
- 全量回歸：`./scripts/test.sh`

---

## Task 1：Part B 根因執行期診斷（必須最先做）

背景：靜態讀碼已證偽核准稿的首要嫌疑——`petButton` 在 `DetachedIslandPanelView.swift:771` 無條件渲染（body `:745-774`），bubble 狀態下拖曳 overlay（`:972-987`）仍在，拖曳鏈全接通（`:1098` NSView → `:1072` bridge → props `:649-651` → `DetachedIslandWindowController.swift:270-271` → `updateFloatingDrag :465` → `setFrameOrigin :450`）。根因需執行期觀測。

- [ ] 在 `DetachedPetInteractionView`（`DetachedIslandPanelView.swift:1127-1158`）的 `mouseDown` / `mouseDragged` / `mouseUp` 加暫時 log（含 translation 與 `hasStartedDrag`）
- [ ] 在 `DetachedIslandWindowController.updateFloatingDrag`（`:465`）入口與 `setFrameOrigin`（`:450`）呼叫前加暫時 log
- [ ] Debug build 執行，在四種寵物狀態各重現一次拖曳：compact、hover bubble、notification bubble、pinned bubble；記錄鏈路斷在哪一段
- [ ] 依斷點逐一驗證 spec 候選表：暫時移除 `:969-971` 的 `.rotationEffect`/`.scaleEffect` 重試；檢查 nonactivating panel first-mouse（`isMovableByWindowBackground=false` `:253`）；檢查 `:465`/`endWindowDrag :497` 內的狀態閘門；檢查 bubble 與 petFrame 重疊時的 hitTest 命中者
- [ ] 可行時寫一個 red test（純邏輯層，例如把斷掉的閘門條件抽出可測）；若斷點在 AppKit 事件路由層無法單測，記錄手動重現步驟作為 red 基準
- [ ] 把確認的根因（file:line）回寫 spec「根因判定」段，取代候選表結論
- 驗證：診斷 log 明確指出斷鏈位置；spec 已更新；暫時 log 標記 TODO 待 Task 4 移除

## Task 2：StatusBarController 純邏輯 + 測試

- [ ] 新增 `PingIsland/App/StatusBarController.swift`：選單模型建構抽成純函式（輸入 `surfaceMode`、版本字串、是否 App Store 建置；輸出 item 清單含 title key、enabled、checkmark、action 種類），NSStatusItem/NSMenu 僅做薄殼綁定
- [ ] 選單內容依 spec 表：開啟設定、展示模式 submenu（停靠瀏海 / 獨立懸浮寵物 + checkmark）、分隔線、disabled 版本行 `Ping Island v<CFBundleShortVersionString> (build <CFBundleVersion>)`、檢查更新（`#if APP_STORE` 隱藏/走 stub，pattern 同 `NotchUserDriver.swift:4`/`:46`）、分隔線、離開 Ping Island
- [ ] `StatusBarController` 實作 `NSMenuDelegate.menuWillOpen`，刷新 checkmark 與版本行
- [ ] `PingIslandTests` 新增純邏輯測試：item 順序與種類、checkmark 跟隨 `surfaceMode`、版本字串格式、App Store 分支不含檢查更新
- 驗證：Build 指令通過；單元測試指令通過（新測試先 red 後 green）

## Task 3：接線 AppDelegate 與動作

- [ ] `PingIsland/App/AppDelegate.swift` 建立並持有 `StatusBarController`（app 啟動即建立，常駐、無隱藏設定）
- [ ] 動作接線：開啟設定 → `SettingsWindowController.shared.present()`；展示模式 → 只寫 `AppSettings.surfaceMode`（套用交給 `IslandPresentationCoordinator.swift:154-162` 的 `$surfaceMode` sink → `applySurfaceMode :108` → 需要時 `redockDetached :123`）；檢查更新 → `UpdateManager.checkForUpdates()`（`NotchUserDriver.swift:204`）；離開 → `NSApp.terminate(nil)`
- 驗證：Build 通過。手動：兩種模式下狀態項可見；開啟設定成功；submenu 切換模式生效且 checkmark 正確（detached 時選停靠瀏海會 re-dock、無重複視窗）；版本行正確；離開可退出

## Task 4：寵物拖曳修復（依 Task 1 結果）

- [ ] 依 Task 1 確認的根因，在對應位置修復（候選落點：`DetachedIslandPanelView.swift:969-987` transform/overlay 順序、`DetachedIslandWindowController.swift:465`/`:497` 閘門、window first-mouse 設定 `:253` 一帶）；只改斷鏈那一段，不重構其他拖曳碼
- [ ] 若 Task 1 產出 red test，使其轉 green；否則以記錄的手動步驟驗收
- [ ] 移除 Task 1 的暫時 log
- [ ] 確認持久化路徑不變：放開後 `clampedPetAnchor`（`:945`）→ `onPetAnchorChanged`（`:491`）→ `endWindowDrag`（`:497`）
- 驗證：Build + 單元測試通過。手動：四種寵物狀態（compact / hover / notification / pinned bubble）按住本體拖曳皆移動視窗，放開後位置持久化（重啟 app 仍在）；純點擊仍開啟/互動

## Task 5：拖到頂部中央 re-dock

- [ ] 新增 re-dock 區純函式（`contains(petCenter:screenRect:) -> Bool`；zone = 以 `screenRect.midX` 為中心、寬 240pt、頂緣向下 60pt，見 spec 幾何表；放在 window controller 同層或 `PingIsland/Utilities/`）
- [ ] `PingIslandTests` 先寫 red test：zone 命中/未命中/邊界值、跨螢幕（不同 `screenRect`）情境
- [ ] `DetachedIslandWindowController` 拖曳中（`updateFloatingDrag :465` 之後）計算寵物中心是否在 zone，維護「即將停靠」旗標；`endWindowDrag`（`:497`）分流：在 zone 內 → 呼叫 `IslandPresentationCoordinator.redockDetached()`（`:123`），否則走現有 reposition + clamp 持久化
- [ ] 確認 3pt 門檻語意不變：純點擊永不觸發 re-dock
- 驗證：單元測試 green。手動：拖入頂部中央放開 → re-dock 成功、docked notch 正常 click-open、無重複視窗；拖到別處放開 → reposition 照舊；點一下 → 照舊互動

## Task 6：localization + 簡體字 guard

> 本節 backtick 內的簡體字串（`检查更新`、`退出应用`、`打开设置` 等）是 localization **key 識別碼**，非顯示文字；顯示一律走繁體 value。這是本專案 key-簡體 / value-繁體 慣例，非筆誤。

- [ ] 重用既有 key：`检查更新`（`zh-Hant.lproj/Localizable.strings:219`）；評估 `退出应用`（`:40`）是否合用「離開 Ping Island」，不合則新增
- [ ] 查設定視窗 surface-mode picker 既有 key（`:69`、`:103` 相鄰區段）決定「展示模式／停靠瀏海／獨立懸浮寵物」重用或新增；「開啟設定」新增 key
- [ ] 新 key 一律簡體 key + `zh-Hant.lproj` 繁體 value + `en.lproj` 英文 value；繁體 value 逐字檢查用字（瀏海，非「刈海」）
- 驗證：`swift scripts/check-simplified-chinese.swift` 通過；單元測試（含 `SettingsWindowControllerTests` 的 key 斷言）通過

## Task 7：AGENTS.md 同步 + 全量驗證

- [ ] `AGENTS.md`：Start Here 補 `PingIsland/App/StatusBarController.swift`；Change Routing 補「改狀態項選單 / surface-mode 入口時，連動 trace `StatusBarController`、`Settings.swift`、`IslandPresentationCoordinator`」與拖放 re-dock 的 trace 條目
- [ ] 若診斷改動了 spec 中的行為或幾何值，確認 spec 與程式碼 1:1
- [ ] `./scripts/test.sh` 全量回歸
- [ ] 手動 runtime 驗收清單（一次跑完）：狀態項全部選單動作；四種寵物狀態拖曳；drag-to-redock 與 redock 後再 drag-to-detach 來回一輪無重複視窗；App Store lane 建置（`PING_ISLAND_SKIP_APP_STORE_SIGNING=1 ./scripts/build-app-store.sh`）確認檢查更新分支
- 驗證：上列指令全綠；手動清單逐項打勾
