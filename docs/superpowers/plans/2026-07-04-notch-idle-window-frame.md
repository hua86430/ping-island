# Notch 閒置視窗框縮減 實作計畫

Spec：`docs/superpowers/specs/2026-07-04-notch-idle-window-frame-design.md`（已核准）
日期：2026-07-04

行號以 2026-07-04 為準；動手前先 `rg` 確認未漂移。

驗證指令：

- Build：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- 單元測試：`xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
- 簡體字守門：`swift scripts/check-simplified-chinese.swift`
- 全回歸：`./scripts/test.sh`

## Task 1：TDD——先寫紅測試

擴充 `PingIslandTests/NotchWindowControllerFrameTests.swift`（現有 2 個 `dockedWindowFrame` 測試 `:7-19`，保留不動）。

- [ ] 新增 `closedWindowFrame(screenFrame:closedHeight:)` 測試：給 `screenFrame = (0, 0, 1440, 900)`、`closedHeight = 38`，斷言回傳滿寬、貼頂、高度 = `38 + NotchWindowController.closedFrameSlack`（即 `y = 900 − (38 + slack)`）
- [ ] 新增 offset 外接螢幕版本（`screenFrame = (1440, 0, 2560, 1440)`）斷言 x 原點與貼頂 y 都跟著螢幕走
- [ ] 新增 `targetWindowFrame(status:screenFrame:closedHeight:)` 逐 status 測試：`.closed` → 等於 `closedWindowFrame` 結果（窄條高）；`.opened` 與 `.popping` → 等於 `dockedWindowFrame` 結果（750）
- [ ] 新增「moveToScreen 保持逐 status 高度」測試：對兩個不同 `screenFrame` 分別以 `.closed` 與 `.opened` 呼叫 `targetWindowFrame`，斷言高度只由 status 決定、x/寬/貼頂 y 由螢幕決定（`moveToScreen` 實作將直接呼叫這個 resolver，見 Task 2；純函式測試即覆蓋，不需在測試裡建整個 `NotchWindowController`）
- [ ] 新增 hitTest 即時高度測試（可放同檔或 `NotchViewControllerTransparencyTests.swift` 旁，擇一，參考該檔既有的 view controller 建構方式）：把 `NotchViewController.view` 裝進一個高度 ≠ `geometry.windowHeight` 的 NSWindow，斷言 `hitTestRect()` 的 y 以視窗實際高度為基準；再斷言 view 不在 window 內時 fallback 到 `geometry.windowHeight`（等同今日行為）
- [ ] 測試中的螢幕座標一律用合成值（如上），不用本機真實路徑或真實螢幕尺寸假設
- [ ] 跑 `xcodebuild ... test -only-testing:PingIslandTests`，確認新測試**紅**（符號尚不存在會編譯失敗，屬預期的紅）

驗證：新測試因缺少 `closedWindowFrame` / `targetWindowFrame` / hitTest 改動而失敗；既有測試不受影響。

## Task 2：`NotchWindowController` 框縮放

檔案：`PingIsland/UI/Window/NotchWindowController.swift`

- [ ] 在 `:18` `static let windowHeight: CGFloat = 750` 附近新增兩個具名常數：`closedFrameSlack: CGFloat = 96`（註解寫明它必須蓋住：popping/boot 放大的第一幀競態、mascot 溢出 pill 下緣的繪製）與縮小延遲 `closedFrameShrinkDelay: TimeInterval = 0.30`（註解註明 > `NotchViewModel.swift:240-241` 的 0.25s `.easeOut` 收合動畫）
- [ ] 在 `:21-28` `dockedWindowFrame` 之後新增 companion：`static func closedWindowFrame(screenFrame: CGRect, closedHeight: CGFloat) -> NSRect`——滿寬、`height = closedHeight + closedFrameSlack`、`y = screenFrame.maxY − height`
- [ ] 新增 resolver：`static func targetWindowFrame(status: NotchStatus, screenFrame: CGRect, closedHeight: CGFloat) -> NSRect`——`.closed` → `closedWindowFrame`；`.opened` / `.popping` → `dockedWindowFrame`
- [ ] 改 `updateWindowPresentation`（`:194-240`）：
  - `:199` hover sensor 更新、`:201-209` `shouldHideWindowPresentation` orderOut early-return——**不動**
  - 把 `:211-213`（無條件 `setFrame(fullWindowFrame)`）換成：status 為 `.opened` / `.popping` 且 `window.frame != fullWindowFrame` → **立即** `setFrame(fullWindowFrame, display: true)`（必須留在 `:215-217` `orderFront` 之前，同一 runloop 先長大再顯示）；status 為 `.closed` 且 `window.frame != 窄條框` → `DispatchQueue.main.asyncAfter(deadline: .now() + closedFrameShrinkDelay)`，callback 內**重查 `viewModel.status == .closed`**（弱參照 window / viewModel），通過才 `setFrame(窄條框)` 並補 `hasShadow = false` + `invalidateShadow()` 重申；不通過直接 return。不加 generation token——每個 callback 各自重查即冪等
  - `:219-230` ignoresMouseEvents / activate 分支、`:236-239` 陰影 async 重申——**不動**
- [ ] 改 `moveToScreen`（`:243-248`）：`fullWindowFrame`（`:14`）仍存全畫布框並照舊更新與 guard，但 `window?.setFrame` 改套 `targetWindowFrame(status: viewModel.status, ...)`，`closedHeight` 用 `viewModel.closedHeight`；setFrame 後補同款陰影重申
- [ ] 跑單元測試：Task 1 中 `closedWindowFrame` / `targetWindowFrame` / resolver 測試轉綠

驗證：`xcodebuild ... test -only-testing:PingIslandTests` 框相關測試全綠；Debug build 成功。

## Task 3：`NotchViewController` hitTest 讀即時高度

檔案：`PingIsland/UI/Window/NotchViewController.swift`

- [ ] `hitTestRect` closure（`:75-108`）內 `:82` 的 `let windowHeight = geometry.windowHeight` 改為 `let windowHeight = self.view.window?.frame.height ?? geometry.windowHeight`
- [ ] `:93`（`.opened` 的 `y = windowHeight − panelHeight`）與 `:103`（`.closed`/`.popping` 的 `y = windowHeight − closedSize.height − 5`）沿用該區域變數，不需再改
- [ ] 跑單元測試：Task 1 的 hitTest 即時高度 + fallback 測試轉綠

驗證：hitTest 測試綠；`NotchViewControllerTransparencyTests` 既有測試不退。

## Task 4：釘死 slack 實測值

- [ ] Debug build 跑起 app，觀察 `.closed` 靜置與 boot `.popping` 放大瞬間，確認 pill 下緣以下（mascot 溢出、popping 初幀）全部落在窄條內、無裁切閃爍
- [ ] 若 96pt 不足或過寬，調整 `closedFrameSlack` 並更新常數註解與 spec 資料契約表的值；若 96pt 剛好，維持並在 spec 標記「已實測」

驗證：肉眼無裁切；spec 與程式碼常數一致（plan/spec 同步原則）。

## Task 5：全回歸 + 手動運行時驗證

自動化部分：

- [ ] `swift scripts/check-simplified-chinese.swift` 通過（本次新增的 doc 為繁體中文，需過守門）
- [ ] `./scripts/test.sh` 全綠
- [ ] `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build` 成功

手動運行時驗證（需要真實視窗 + 截圖工具，無法寫成單元測試；對照 AGENTS.md notch sizing / docked-detached change routing）：

- [ ] **擷取選取器**：開任一 CGWindowList 視窗選取式截圖工具，關閉狀態下 notch 只被框成貼頂細帶（menu bar 帶高度量級），不再蓋住前景 app 內容；開啟狀態下仍可被完整擷取（`sharingType` 未動）
- [ ] **click-open**：關閉狀態點 pill 正常展開（全域 NSEvent monitor 走螢幕座標，應與框無關）
- [ ] **hover-open**：hover pill 正常預覽展開（獨立 `NotchHoverSensorWindow` 應不受影響）
- [ ] **drag-to-detach / re-dock**：關閉與開啟狀態都能拖出 detach、再 re-dock，無殘留視窗
- [ ] **開合時序**：點開瞬間內容不被窄框裁切（先長大再開）；關閉時收合動畫播完（~0.25s）後才縮框，無閃爍；快速連續開-關-開不會被延遲縮小誤縮
- [ ] **`.popping` / boot / completion popup**：重啟 app 看 boot 放大動畫、觸發一次 session 完成 popup，皆不被裁切
- [ ] **多螢幕**：接外接螢幕把 notch 搬過去（`moveToScreen`），關閉狀態搬過去是窄條、開啟狀態搬過去是全畫布，且窄條高度隨該螢幕的 `closedHeight` 變
- [ ] **隱藏路徑**：fullscreen edge-reveal、quiet-background、idle-auto-hide、切 detached 模式，orderOut 隱藏／恢復行為與改動前一致
- [ ] **macOS 26 陰影**：每條路徑（開、延遲縮、搬螢幕）之後 notch 周圍無殘留陰影
- [ ] **開啟狀態按鈕**：展開面板內按鈕全部可點（hitTest 高度來源改動後 opened 路徑仍正確）

驗證：以上全勾。

## Task 6：文件同步

- [ ] 檢視 `AGENTS.md`「If you change notch sizing, opening behavior, or visibility」條目：本次讓停靠視窗框變成 status-scaled，於該條目補一句視窗框現在依 `NotchViewModel.status` 在窄條與 750 全畫布間切換、chokepoint 在 `NotchWindowController.updateWindowPresentation`
- [ ] 若實作過程與 spec 產生任何偏離，先改 spec 再繼續（plan/spec doc 同步原則）；完工時 spec 與程式碼 1:1

驗證：冷讀 spec 與 AGENTS.md，與實際程式碼一致。
