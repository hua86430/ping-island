# 設計規格：常駐選單列狀態項 + 懸浮寵物拖曳修復與拖回瀏海

- 日期：2026-07-04
- 狀態：已核准（approved）
- 對應 plan：`docs/superpowers/plans/2026-07-04-menubar-status-item-and-pet-drag.md`

## 問題

PingIsland 是 accessory(輔助程式) 型 app（`NSApplication.setActivationPolicy(.accessory)`，由 `AppLaunchConfiguration` 設定），沒有 `NSStatusItem`。設定視窗唯二入口是點擊停靠瀏海或獨立懸浮寵物（`SettingsWindowController.shared.present()`）。在懸浮寵物模式（`AppSettings.surfaceMode = .floatingPet`，`PingIsland/Core/Settings.swift:230` 的 `IslandSurfaceMode { case notch, floatingPet }`，持久化 key `"surfaceMode"`）下，若寵物無法點擊或拖曳，使用者會被鎖在設定外，只剩改 `defaults` 一條路。

本規格分兩部分：

- Part A：常駐選單列狀態項，作為永遠可用的逃生口（escape hatch）。
- Part B：修復「寵物本體拖不動」的執行期問題，並新增「拖到螢幕頂部中央即重新停靠（re-dock）」。

---

## Part A：常駐選單列狀態項

### 結構

新增 `StatusBarController`（`PingIsland/App/StatusBarController.swift`，由 `AppDelegate` 持有生命週期），建立一個永遠可見的 `NSStatusItem`：

- 圖示：Ping Island template icon(範本圖示)，優先重用 bundled app icon / symbol 資產，找不到時退回 SF Symbol。
- 掛一個 `NSMenu`，`StatusBarController` 實作 `NSMenuDelegate`，在 `menuWillOpen` 時刷新 checkmark(勾選標記) 與版本字串。
- 常駐、無隱藏設定。不提供關閉此狀態項的選項（它就是逃生口，藏起來就失去意義）。

### 選單項目

| 項目 | 類型 | 行為 |
| --- | --- | --- |
| 開啟設定 | action | `SettingsWindowController.shared.present()` |
| 展示模式 | submenu | 見下表 |
| ──（分隔線） | separator | — |
| Ping Island v\<CFBundleShortVersionString\> (build \<CFBundleVersion\>) | disabled | 純顯示，`menuWillOpen` 時從 `Bundle.main` 重新讀值 |
| 檢查更新 | action | 呼叫既有 `UpdateManager.checkForUpdates()`（`PingIsland/Services/Update/NotchUserDriver.swift:204`）；App Store 建置以 `#if APP_STORE`（同 `NotchUserDriver.swift:4` / `:46` 的既有 pattern）隱藏或改用該 lane 的 stub |
| ──（分隔線） | separator | — |
| 離開 Ping Island | action | `NSApp.terminate(nil)` |

「展示模式」submenu：

| 項目 | checkmark 條件 | 行為 |
| --- | --- | --- |
| 停靠瀏海 | `AppSettings.surfaceMode == .notch` | 設 `AppSettings.surfaceMode = .notch`；若目前為 detached(分離) 狀態，等同重新停靠——`IslandPresentationCoordinator` 的 `$surfaceMode` sink（`IslandPresentationCoordinator.swift:154-162`）會經 `applySurfaceMode`（`:108`）套用，內部走 `redockDetached()`（`:123`） |
| 獨立懸浮寵物 | `AppSettings.surfaceMode == .floatingPet` | 設 `AppSettings.surfaceMode = .floatingPet`，同樣由 `$surfaceMode` sink 套用 |

狀態項只寫 `AppSettings.surfaceMode`，不直接呼叫 coordinator——沿用既有的單一套用路徑，避免第二條 mutation 路線。

### 選單動作流程

```mermaid
flowchart TD
    A[NSStatusItem 點擊] --> B[menuWillOpen<br/>刷新 checkmark + 版本字串]
    B --> C{選擇項目}
    C -->|開啟設定| D["SettingsWindowController.shared.present()"]
    C -->|展示模式 > 停靠瀏海| E["AppSettings.surfaceMode = .notch"]
    C -->|展示模式 > 獨立懸浮寵物| F["AppSettings.surfaceMode = .floatingPet"]
    E --> G["IslandPresentationCoordinator<br/>$surfaceMode sink (:154-162)<br/>→ applySurfaceMode (:108)<br/>→ 必要時 redockDetached() (:123)"]
    F --> G
    C -->|檢查更新| H["UpdateManager.checkForUpdates()<br/>APP_STORE 建置隱藏/stub"]
    C -->|離開 Ping Island| I["NSApp.terminate(nil)"]
```

### i18n

依 repo 慣例：localization key 用簡體（查找識別字），`zh-Hant.lproj` value 用繁體，`en.lproj` 補英文；全部須通過 `swift scripts/check-simplified-chinese.swift`。

> 註：下表「key（簡體）」欄裡的簡體字（如 `检查更新`、`退出应用`、`打开设置`、`刘海屏方式`、`独立悬浮宠物`）是 localization **key 識別碼**，不是要顯示給使用者的文字。畫面實際顯示的一律是對應的繁體 value（例如 key `检查更新` → value「檢查更新」）。這是本專案刻意的慣例，guard scanner 只擋 `zh-Hant.lproj` 的 value 與 Swift 顯示字面量，不擋 key 也不掃 docs。

優先重用既有 key：

| 用途 | key（簡體） | 既有/新增 | 依據 |
| --- | --- | --- | --- |
| 檢查更新 | `检查更新` | 既有 | `zh-Hant.lproj/Localizable.strings:219`（value「檢查更新」） |
| 離開 Ping Island | 實作時先查 `退出应用`（`:40`，value「結束應用程式」）是否語意合用；選單需帶 app 名，若不合則新增 | 待定 | — |
| 開啟設定 | 新增（現無獨立「打开设置」key） | 新增 | grep 無 bare key |
| 展示模式 / 停靠瀏海 / 獨立懸浮寵物 | 實作時先查設定視窗 surface-mode picker 既有 key（`zh-Hant.lproj` 已有「刘海屏方式」`:69`、「独立悬浮宠物…」`:103` 等相鄰文案），有就重用，否則新增 | 待定 | — |

註：核准稿中「停靠刈海」判定為「停靠瀏海」的錯字（「刈」U+5208 為形近誤字；repo zh-Hant 既有 value 一律用「瀏海」），本規格採「瀏海」。

---

## Part B：寵物拖曳修復 + 拖到頂部中央重新停靠

### 既有拖曳鏈（靜態確認完整）

以下鏈路已逐段讀碼確認全部接通：

1. `DetachedPetInteractionView`（NSView，`DetachedIslandPanelView.swift:1098`）：`mouseDown`/`mouseDragged`/`mouseUp`（`:1127-1158`），3pt 門檻（`:1104`, `:1141`），`hitTest` 回傳 self（`:1123-1125`），`acceptsFirstMouse` 為 true（`:1119-1121`）。
2. 經 `DetachedPetInteractionBridge`（`:1072`）以最上層 `.overlay` 安裝（`:972-987`）。
3. callback props `onPetDragStarted`/`onPetDragChanged`/`onPetDragEnded`（`:649-651`）→ `DetachedIslandWindowController.onPetDragChanged`（`DetachedIslandWindowController.swift:270-271`）→ `updateFloatingDrag(translation:)`（`:465`）→ `setFrameOrigin`（`:450`）。

### 根因判定

**核准稿的首要嫌疑（petButton 只在 compact 狀態渲染、bubble 狀態沒有拖曳 handler）經讀碼證偽**：`DetachedIslandPanelView.body`（`DetachedIslandPanelView.swift:745-774`）中 `petButton` 在 `:771` 無條件渲染，與 `bubbleView`（`:848`，hover / notification / pinned bubble）並存於同一 ZStack——寵物本體在任何 bubble 狀態下都掛著拖曳 overlay。因此「bubble 狀態缺 handler」不是根因。

**結論：靜態讀碼無法定根因，需要執行期觀測釐清**（此為依 `:771` 證據所下的判斷，非臆測性填補）。剩餘候選，依可疑度排序：

| 候選 | 位置 | 驗證方式 |
| --- | --- | --- |
| `.rotationEffect` / `.scaleEffect` 在 `.overlay` 之前套用，拖曳中 transform(變形) 造成命中座標偏移或事件中斷 | `DetachedIslandPanelView.swift:969-971` vs `:972-987` | 暫時移除 transform 後重試拖曳 |
| nonactivating panel + first-mouse 互動（視窗未啟用時首次 mouseDown 的事件路由；`isMovableByWindowBackground = false` 在 `DetachedIslandWindowController.swift:253`） | window controller | 記錄 `mouseDown`/`mouseDragged` 是否真的抵達 NSView |
| `updateFloatingDrag`（`:465`）/ `endWindowDrag`（`:497`）內的狀態閘門在特定 bubble / hover 狀態下擋掉位移 | `DetachedIslandWindowController.swift` | 在 `:465` 入口與 `setFrameOrigin`（`:450`）前打 log 比對 |
| bubble 展開時 bubble 視圖與 petFrame 重疊，hit-testing 被 bubble 搶走 | `DetachedIslandPanelView.swift:745-774` layout | 各 bubble 狀態下記錄 hitTest 命中者 |

Plan 的 Task 1 即為此執行期診斷步驟；後續修復 task 以診斷結果為準。

### 行為契約（behavior contract）

| 情境 | 預期行為 |
| --- | --- |
| 在寵物本體按下並拖曳（任何寵物狀態：compact、hover bubble、notification bubble、pinned bubble） | 懸浮視窗跟隨移動；放開後以 clamp(夾限) 後的 anchor 持久化（`clampedPetAnchor` `DetachedIslandWindowController.swift:945`、`onPetAnchorChanged` `:491`、`endWindowDrag` `:497`） |
| 拖曳中進入頂部中央 re-dock 區並放開 | 呼叫 `IslandPresentationCoordinator.redockDetached()`（`IslandPresentationCoordinator.swift:123`）回到停靠瀏海 |
| 拖曳到其他位置放開 | 純 reposition（重新定位），維持現行為 |
| 點一下（未達 3pt 門檻） | 照舊開啟 / 互動（`onTap`），不觸發拖曳或 re-dock |

### 拖曳狀態機

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Pressed : mouseDown
    Pressed --> Idle : mouseUp（未達 3pt）→ onTap 開啟/互動
    Pressed --> Dragging : 位移 ≥ 3pt → onDragStarted
    Dragging --> Dragging : mouseDragged → updateFloatingDrag → setFrameOrigin
    Dragging --> Redock : mouseUp 且寵物中心在 re-dock 區
    Dragging --> Reposition : mouseUp 且不在 re-dock 區
    Redock --> [*] : IslandPresentationCoordinator.redockDetached()
    Reposition --> Idle : clampedPetAnchor 持久化（onPetAnchorChanged / endWindowDrag）
```

### Re-dock 區幾何

鏡射停靠側 drag-to-detach 既有機制（`NotchViewModel` 的 `DockedDetachmentTracking` + `onDetachmentRequested/Updated/Finished`，coordinator 側 `beginDetachment/updateDetachment/finishDetachment`，binding 位於 `IslandPresentationCoordinator.swift:142-152`）。

| 參數 | 值 | 說明 |
| --- | --- | --- |
| 判定點 | 寵物 hit frame 中心（螢幕座標） | 拖曳中每次位移後計算 |
| 區域 | 以目前螢幕 `screenRect.midX` 為中心、寬 240pt、自螢幕頂緣向下 60pt 的矩形 | 對準停靠瀏海位置；數值為初始值，實作時可依 notch 實寬微調，但變更須回寫本表 |
| 觸發條件 | mouseUp 時中心在區域內，且拖曳已越過 3pt 門檻 | 純點擊永不觸發 |
| 判定實作 | 純函式 `contains(petCenter:screenRect:) -> Bool` | 可單元測試，不依賴視窗 |
| 拖曳中回饋 | 進入區域時視窗端切換一個「即將停靠」狀態旗標（最小實作：無視覺亦可，但旗標須存在以供測試與後續 UI 掛載） | 不做新動畫，避免超出範圍 |

### 檔案改動清單

| 檔案 | 改動 |
| --- | --- |
| `PingIsland/App/StatusBarController.swift`（新增） | NSStatusItem + NSMenu + NSMenuDelegate；選單建構抽成純邏輯以便測試 |
| `PingIsland/App/AppDelegate.swift` | 持有並初始化 `StatusBarController` |
| `PingIsland/UI/Views/DetachedIslandPanelView.swift` | 依 Task 1 診斷結果修復拖曳（候選：`:969-987` transform/overlay 順序） |
| `PingIsland/UI/Window/DetachedIslandWindowController.swift` | 拖曳中計算 re-dock 區命中；`endWindowDrag`（`:497`）分流 redock vs reposition |
| `PingIsland/App/IslandPresentationCoordinator.swift` | 曝露/重用 `redockDetached()`（`:123`）給拖放 re-dock 呼叫 |
| Re-dock 區純函式（新增，跟隨 window controller 同層或 Utilities） | zone 幾何 + 單元測試 |
| `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`、`en.lproj/Localizable.strings` | Part A 新增字串 |
| `PingIslandTests/`（root Xcode 測試 target） | 選單建構、re-dock zone、clamp 相關純邏輯測試 |
| `AGENTS.md` | 補 StatusBarController 入口與 change-routing 條目 |

### 邊界條件

- App Store 建置：`檢查更新` 以 `#if APP_STORE` 隱藏或走 stub `UpdateManager`（`NotchUserDriver.swift:46-86`），不得引入 Sparkle 相依。
- 多螢幕：re-dock 區以寵物視窗當下所在螢幕的 `screenRect` 計算，不寫死主螢幕。
- 停靠模式下狀態項仍常駐；「展示模式 > 停靠瀏海」在已停靠時為 no-op（sink 套用同值）。
- 拖放 re-dock 與 submenu 切模式最終走同一條 `redockDetached()` 路徑，不得出現重複視窗（對應 AGENTS.md 驗證清單的 detach/re-dock 條目）。
- 右鍵寵物開設定的既有行為不受拖曳修復影響。

### 成功條件

1. 任何模式下選單列都有 Ping Island 狀態項；開啟設定、切換展示模式、檢查更新、離開全部可用；checkmark 與版本字串在 `menuWillOpen` 時正確。
2. 懸浮寵物在 compact 與各 bubble 狀態下，按住本體拖曳都能移動視窗並持久化 clamp 後位置。
3. 拖到頂部中央區放開會 re-dock；其他位置放開為 reposition；純點擊行為不變。
4. `swift scripts/check-simplified-chinese.swift`、`./scripts/test.sh`、root `PingIslandTests` 全數通過；主 scheme 可建置。
