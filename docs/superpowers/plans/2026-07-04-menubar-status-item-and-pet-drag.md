# 實作計畫：常駐選單列狀態項 + 懸浮寵物拖曳修復與拖回瀏海

- 對應 spec：`docs/superpowers/specs/2026-07-04-menubar-status-item-and-pet-drag-design.md`
- 原則：exact file:line、與核准設計 1:1、不擴 scope。spec 若因診斷結果改變，先改 spec 再繼續。

## 驗證指令（各 task 引用）

- Build：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- 單元測試：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- 簡體字 guard：`swift scripts/check-simplified-chinese.swift`
- 全量回歸：`./scripts/test.sh`

---

## Task 1：Part B 根因執行期診斷（已完成 2026-07-05）

- [x] 在 NSView 層（`DetachedPetInteractionView`）加 log → 看到 `mouseDown=0`
- [x] 發現量錯層：真正生效的是視窗層 `DetachedIslandWindow.sendEvent`（`DetachedIslandWindowController.swift:15-33`）→ `handlePetMouseDown/Dragged/Up`（`:1065` 起），先攔截消化 leftMouse，NSView 那層拿不到
- [x] 在視窗層加 log 重測 → `handlePetMouseDown inside=true`、`handlePetMouseDragged` 98 筆 `active=true`、視窗 `setFrameOrigin` 逐格移動、`handlePetMouseUp active=true → endFloatingDrag`；另有 `mouseUp active=false → onPetTap`。拖曳與點擊皆正常
- [x] 回寫 spec「根因判定（執行期實測）」段
- [x] 移除所有 PETDRAG 暫時 log（本 task 一併清掉，不留到後面）

結論：現行 HEAD 拖曳與點擊都正常，「拖不動」無法重現。真正問題是設定無明顯入口（右鍵才開、無提示）+ 偶發卡頂（transient，重現不出）。兩者都由 Part A 常駐選單解決。Part B 縮編：Task 4 取消、Task 5 降為驗證。

## Task 2：StatusBarController 純邏輯 + 測試

- [ ] 新增 `PingIsland/App/StatusBarController.swift`：選單模型建構抽成純函式（輸入 `surfaceMode`、版本字串、是否 App Store 建置；輸出 item 清單含 title key、enabled、checkmark、action 種類），NSStatusItem/NSMenu 僅做薄殼綁定
- [ ] 選單內容依 spec 表：開啟設定、展示模式 submenu（停靠瀏海 / 獨立懸浮寵物 + checkmark）、分隔線、disabled 版本行 `Ping Island v<CFBundleShortVersionString> (build <CFBundleVersion>)`、檢查更新（`#if APP_STORE` 隱藏/走 stub，pattern 同 `NotchUserDriver.swift:4`/`:46`）、分隔線、離開 Ping Island
- [ ] `StatusBarController` 實作 `NSMenuDelegate.menuWillOpen`，刷新 checkmark 與版本行
- [ ] `PingIslandTests` 新增純邏輯測試：item 順序與種類、checkmark 跟隨 `surfaceMode`、版本字串格式、App Store 分支不含檢查更新
- 驗證：Build 指令通過；單元測試指令通過（新測試先 red 後 green）

## Task 3：接線 AppDelegate 與動作

- [ ] `PingIsland/App/AppDelegate.swift` 建立並持有 `StatusBarController`（app 啟動即建立，常駐、無隱藏設定）
- [ ] 動作接線：開啟設定 → `SettingsWindowController.shared.present()`；展示模式 → 只寫 `AppSettings.surfaceMode`（套用交給 `IslandPresentationCoordinator.swift:154-162` 的 `$surfaceMode` sink → `applySurfaceMode :108` → 需要時 `redockDetached :123`）；檢查更新 → 訂閱 `UpdateManager.shared.$state` + `checkForUpdates()`,用階段機把結果彈成 `NSAlert` 小視窗(最新 / 發現新版·是否安裝 / 錯誤),不開設定 GUI；離開 → `NSApp.terminate(nil)`
- 驗證：Build 通過。手動：兩種模式下狀態項可見；開啟設定成功；submenu 切換模式生效且 checkmark 正確（detached 時選停靠瀏海會 re-dock、無重複視窗）；版本行正確；離開可退出

## Task 4：寵物拖曳修復 —— 取消（Task 1 診斷證實無 bug）

現行 HEAD 拖曳與點擊實測正常，無可修之處。暫時 log 已於 Task 1 移除。此 task 不執行。

## Task 5：拖到頂部中央 re-dock —— 降為驗證既有行為（`#219` 已實作）

commit `805d4fb`（`#219`）已實作：`isPetAnchorInNotchZone`（`DetachedIslandWindowController.swift:1146`）+ `endFloatingDrag → onRedockRequested`（`:484-490`）→ `IslandPresentationCoordinator.redockDetached()`（`:123`）。

- [ ] 手動驗收：拖寵物到頂部中央放開 → re-dock 回停靠瀏海、docked notch 正常 click-open、無重複視窗
- [ ] 確認純點擊不觸發 re-dock（3pt 門檻既有）
- 無程式改動；若驗收發現行為不符再另開 task

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
