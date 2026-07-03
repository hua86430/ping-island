# Settings NavigationSplitView 重寫 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to execute this plan task-by-task with review checkpoints.

**Spec:** `docs/superpowers/specs/2026-07-03-settings-navigation-split-design.md`（先讀完 spec 再動工）

**Goal:** 把 6922 行的 `SettingsWindowView.swift` 單體檔重寫為原生 macOS 視窗 chrome + SwiftUI `NavigationSplitView`，並完整拆分為一檔一責的 `Settings/` 目錄結構，同時移除 `.popover` 死碼全鏈路，行為零變更。

**Architecture:** 兩個進入點（`PingIslandApp` 的 Settings scene 與 `SettingsWindowController.shared`）都渲染 `SettingsWindowView` 薄包裝，內部是 `SettingsRootView`（`NavigationSplitView`）→ 原生 `List(selection:)` sidebar + detail router → 各分類獨立 view 檔。跨分類狀態（selection、refresh、labs 解鎖、analytics consent）留在 root；分類專屬 sheet/@State 下沉到分類 view；`SettingsPanelViewModel` 只在 root `@StateObject` 一份，向下以 `@ObservedObject` 傳遞。

**Tech Stack:** Swift 5 / SwiftUI + AppKit（NSHostingController、NSWindow chrome）、XCTest（PingIslandTests、PingIslandUITests）、xcodebuild。

## Global Constraints

- 分支：`settings-navigation-split`（已自 main 分出；所有工作在此分支，不碰 main）。
- Commit：ticket-less Conventional Commits（英文）；本 plan 採每 task 一 commit（比 spec 的每 stage 一 commit 更細，stage 邊界不變，方便中斷續作與回退）。
- 每個 task 結束必須 Debug build 通過才能 commit；merge 前跑完 Task 17 全量驗證。
- Deployment target macOS 14.0（`Config/App.xcconfig`），不需 availability guard。
- Xcode 專案使用 `PBXFileSystemSynchronizedRootGroup`（`project.pbxproj:59-79`）：`PingIsland/` 下新增 `.swift` 檔自動加入 target，不手改 pbxproj。
- 行為零變更：所有設定功能、binding、localization key（`Text(appLocalized:)` 字串逐字保留）、category refresh 排程、hook 安裝流程、labs 解鎖彩蛋、跨視窗分類跳轉通知原樣保留。搬遷 = 剪貼 + 移除 `private`（同 module 內改為 internal），不重寫 view body。
- 原生 chrome 配方逐字採用（spec「Window chrome」節，本 session 稍早已實測）：`styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`、`titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、`isMovableByWindowBackground = true`、`isOpaque = false`、`backgroundColor = .clear`、移除 `hasShadow = false`、`hostingController.safeAreaRegions = []`。
- 工作樹已有未提交變更（`PingIsland/UI/Views/NotificationFeedView.swift`）：不碰、不 revert、不納入本計畫的 commit。
- 本文行號以 main@f4be14d 的檔案為準；執行時以符號名為錨、行號僅供定位（前面 task 會使行號位移）。
- 指令代號（後文引用）：
  - `BUILD` = `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build` → 預期尾行 `** BUILD SUCCEEDED **`
  - `UNIT-TEST` = `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests` → 預期尾行 `** TEST SUCCEEDED **`
  - `UI-TEST` = `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGN_IDENTITY=- test -only-testing:PingIslandUITests` → 預期尾行 `** TEST SUCCEEDED **`（runner 若被 launch-suspend，先查 `amfid` / `AppleSystemPolicy` log，見 AGENTS.md）
  - `RUN-APP` = `open "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')/PingIsland.app"`（先跑 BUILD 再開；驗完 `pkill -x PingIsland`）

---

## Stage 1：popover 死碼移除

### Task 1: NotchViewModel 移除 `isSettingsPopoverPresented`（測試先行）

死碼證據（2026-07-03 全 repo grep 覆核）：`setSettingsPopoverPresented` 是 `isSettingsPopoverPresented` 唯一 setter 且零 caller → 該 @Published 恆為 `false`，`shouldAutoCollapseHoverPreview` 的 `!isSettingsPopoverPresented` 分支與 `handleMouseDown` 的 guard 恆定。

**Files**

- Modify: `PingIslandTests/NotchViewModelTests.swift`（lines 66–90，`testHoverAutoCollapseWaitsWhileInlineTextInputIsActive`）
- Modify: `PingIsland/Core/NotchViewModel.swift`（lines 54, 116–130, 532–537, 861–868, 935–937）

**Interfaces**

- Consumes: 現有 `static func shouldAutoCollapseHoverPreview(isHovering:status:openReason:isSettingsPopoverPresented:isInlineTextInputActive:autoCollapseOnLeave:) -> Bool`
- Produces: `static func shouldAutoCollapseHoverPreview(isHovering: Bool, status: NotchStatus, openReason: NotchOpenReason, isInlineTextInputActive: Bool, autoCollapseOnLeave: Bool) -> Bool`（語意不變：恆假的參數移除）

**Steps**

- [ ] `git -C /Users/jack.huang/my_project/ping-island checkout settings-navigation-split && git status` → 確認在分支上、只有 `NotificationFeedView.swift` 為既有未提交變更
- [ ] 覆核死碼證據：`rg -n 'setSettingsPopoverPresented' PingIsland PingIslandTests PingIslandUITests Prototype` → 預期只有 `NotchViewModel.swift:935-936` 定義處一個 match
- [ ] RED — 先改測試：`PingIslandTests/NotchViewModelTests.swift` 刪除兩處傳參行 `isSettingsPopoverPresented: false,`（line 73 與 line 84），其餘引數與斷言不動
- [ ] 跑 `UNIT-TEST` → 預期編譯失敗（`missing argument for parameter 'isSettingsPopoverPresented'`），確認測試已鎖定新簽章
- [ ] GREEN — 改 `PingIsland/Core/NotchViewModel.swift`：
  - 刪 line 54：`@Published private(set) var isSettingsPopoverPresented = false`
  - `shouldAutoCollapseHoverPreview`（116–130）：刪參數行 `isSettingsPopoverPresented: Bool,` 與 body 中 `&& !isSettingsPopoverPresented`
  - `handleMouseDown`（532–537）：刪 `if isSettingsPopoverPresented { return }` 三行
  - `hoverCloseTick`（861–868）：刪傳參行 `isSettingsPopoverPresented: isSettingsPopoverPresented,`
  - 刪 `setSettingsPopoverPresented(_:)` 整個 func（935–937）
- [ ] 跑 `UNIT-TEST` → `** TEST SUCCEEDED **`
- [ ] `rg -n 'isSettingsPopoverPresented|setSettingsPopoverPresented' PingIsland PingIslandTests` → 預期 0 match（`SettingsWindowView.swift` 本來就不引用它）
- [ ] `git add PingIsland/Core/NotchViewModel.swift PingIslandTests/NotchViewModelTests.swift && git commit -m "refactor: drop unused settings popover state from NotchViewModel"`

### Task 2: SettingsWindowView / SettingsWindowController 移除 popover 呈現模式與 onMinimize 鏈

**Files**

- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（lines 659–662, 2242–2246, 2251–2253, 2304, 2327, 2340, 2443–2517, 2531–2533, 2640–2646, 3084–3087, 3833–3856）
- Modify: `PingIsland/UI/Window/SettingsWindowController.swift`（lines 123–130）

**Interfaces**

- Consumes: `SettingsWindowView(onClose: (() -> Void)? = nil, onMinimize: (() -> Void)? = nil)`、`SettingsPanelContentView(presentation:onClose:onMinimize:)`
- Produces: `struct SettingsWindowView: View { var onClose: (() -> Void)? = nil }`、`SettingsPanelContentView(onClose:)`（`onClose` 保留：`replayNotchDetachmentHint`（line 3092）仍呼叫 `onClose?()`）

**Steps**

- [ ] 刪 `private enum SettingsPanelPresentation`（659–662）
- [ ] `SettingsPanelMetrics`（2238–2248）：刪 `popoverSize`、`popoverSidebarWidth`、`popoverContentTopInset` 三行，保留 window 系常數與 `windowContentTopInset`、`outerPadding`
- [ ] `SettingsPanelContentView`（2250–2253）：刪 `let presentation: SettingsPanelPresentation` 與 `var onMinimize: (() -> Void)? = nil`，保留 `var onClose: (() -> Void)? = nil`
- [ ] 刪八個 presentation switch 計算屬性 `minimumWidth`/`maximumWidth`/`idealWidth`/`minimumHeight`/`maximumHeight`/`idealHeight`/`sidebarWidth`/`contentTopInset`（2443–2517 內），並把用點改為直接常數：
  - body 的 `.frame(minWidth: minimumWidth, ...)` → `.frame(minWidth: SettingsPanelMetrics.windowMinSize.width, idealWidth: SettingsPanelMetrics.windowSize.width, maxWidth: SettingsPanelMetrics.windowMaxSize.width, minHeight: SettingsPanelMetrics.windowMinSize.height, idealHeight: SettingsPanelMetrics.windowSize.height, maxHeight: SettingsPanelMetrics.windowMaxSize.height, alignment: .topLeading)`
  - `.padding(.top, contentTopInset)` → `.padding(.top, SettingsPanelMetrics.windowContentTopInset)`
  - sidebar 的 `.frame(width: sidebarWidth)` → `.frame(width: SettingsPanelMetrics.windowSidebarWidth)`
- [ ] onAppear（line 2304）：`let isVisible = presentation == .popover || currentWindow?.isVisible == true` → `let isVisible = currentWindow?.isVisible == true`
- [ ] 兩個 onReceive 的 guard（2327、2340）：刪去 `presentation == .window,` 條件，其餘保留
- [ ] sidebar（2531–2533）：`if presentation == .window { sidebarWindowControls }` → 直接 `sidebarWindowControls`（假紅綠燈本 task 先保留，Task 3 隨原生 chrome 一起刪）
- [ ] `sidebarWindowControls` 黃燈按鈕（2640–2646）：closure 改為單行 `currentWindow?.miniaturize(nil)`（原 `if let onMinimize {...} else {...}` 摺疊為 fallback 行為，實際效果相同）
- [ ] `resetSettingsPanelSize`（3084–3087）：刪 `guard presentation == .window else { return }`
- [ ] `SettingsWindowView`（3833–3847）：刪 `var onMinimize`，body 改為 `SettingsPanelContentView(onClose: onClose)`（`presentation:` 引數一併移除），`.accessibilityIdentifier("settings.root")` 保留
- [ ] 刪 `struct NotchSettingsPopoverView`（3849–3856）
- [ ] `SettingsWindowController.swift`（123–130）：`hostingController.rootView = SettingsWindowView(onClose: { [weak self] in self?.dismiss() })`，刪 `onMinimize:` closure
- [ ] `rg -n 'popover|Popover' PingIsland/UI/Views/SettingsWindowView.swift` 與 `rg -n 'onMinimize' PingIsland` → 各 0 match
- [ ] 跑 `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP` runtime 驗證：開 Settings 視窗 → 假紅燈關窗（隱藏不退出，重開後狀態保留）、假黃燈最小化、拖曳區可拖、10 個分類全部照舊渲染
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: remove dead popover presentation mode from settings window"`

---

## Stage 2：原生 chrome + NavigationSplitView 殼（仍在單體檔內改）

### Task 3: 視窗 chrome 換原生 titled + body 換 NavigationSplitView

先換殼再拆檔：之後每個搬遷 task 的 runtime 驗證都在最終視窗形態下進行。

**Files**

- Modify: `PingIsland/UI/Window/SettingsWindowController.swift`（lines 93–107, 100 後插入一行）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`：
  - body（2274–2299 的 ZStack/HStack 佈局）
  - `sidebar`（2528–2628）、刪 `sidebarWindowControls`（2630–2654）、刪 `SettingsSidebarSection`（2195–2200）與 `sidebarSections`（2519–2526）
  - `detail`（2694–2747 的手刻外框 background/overlay/shadow）
  - 刪 `SettingsWindowDragHandle`（2222–2236）、刪 `WindowControlButton`（3937–3953）
  - `selectSidebarCategory`（2762–2781）labs 跳轉時序修正
  - 刪 `panelBackgroundColor`（2506–2508）；`SettingsPanelMetrics` 刪 `windowContentTopInset`、`outerPadding`

**Interfaces**

- Consumes: `SettingsCategory.visibleCategories(labsUnlocked:)`、`SidebarItemView(category:isSelected:showsNoticeDot:)`、`SettingsPanelViewModel.hasIntegrationNotice`
- Produces: `SettingsPanelContentView.body` = `NavigationSplitView { sidebar } detail: { detail }`；sidebar = `List(selection: $selectedCategory)`；selection 型別維持 `SettingsCategory?`，`currentCategory` fallback 邏輯不動

**Steps**

- [ ] `SettingsWindowController.swift` init（93–98）：`styleMask: [.borderless, .resizable]` → `styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`
- [ ] 刪 line 107 `window.hasShadow = false`（回到 titled 預設 `true`，取得原生陰影）
- [ ] `window.contentViewController = hostingController`（line 100）之後插入：`hostingController.safeAreaRegions = []`（關鍵：內容延伸到透明 titlebar 下，紅綠燈浮在 sidebar 上）。其餘屬性（`titleVisibility`、`titlebarAppearsTransparent`、`isMovableByWindowBackground`、`isOpaque`、`backgroundColor`、min/maxSize、`collectionBehavior`、`tabbingMode`、`isReleasedWhenClosed`、delegate、`SettingsPanelWindow` 的 cmd-W 攔截、`windowShouldClose` → `dismiss()`）全部不動
- [ ] `SettingsPanelContentView.body`：把 `ZStack { HStack { sidebar / detail } ... }` 換成（body 上既有的 `.onAppear`/`.onDisappear`/`.task`/三個 `.onReceive`/`.onChange`/全部 `.alert`/`.sheet` modifier 原封不動接在後面）：

  ```swift
  var body: some View {
      NavigationSplitView {
          sidebar
              .navigationSplitViewColumnWidth(
                  min: SettingsPanelMetrics.windowSidebarWidth,
                  ideal: SettingsPanelMetrics.windowSidebarWidth,
                  max: SettingsPanelMetrics.windowSidebarWidth + 60
              )
      } detail: {
          detail
      }
      .navigationSplitViewStyle(.balanced)
      .frame(
          minWidth: SettingsPanelMetrics.windowMinSize.width,
          idealWidth: SettingsPanelMetrics.windowSize.width,
          maxWidth: SettingsPanelMetrics.windowMaxSize.width,
          minHeight: SettingsPanelMetrics.windowMinSize.height,
          idealHeight: SettingsPanelMetrics.windowSize.height,
          maxHeight: SettingsPanelMetrics.windowMaxSize.height
      )
      .preferredColorScheme(.dark)
      .environment(\.mascotAnimationsEnabled, arePreviewAnimationsActive)
      // ...既有 modifier 鏈原樣...
  }
  ```

  同時刪除：`.padding(.top, ...)`/`.padding(.horizontal, ...)`/`.padding(.bottom, ...)` 外層 padding、`.background(panelBackgroundColor)`、`.ignoresSafeArea()`、`.clipShape(RoundedRectangle(cornerRadius: 18, ...))`
- [ ] `sidebar` 整段換成原生 List（`SidebarItemView` 列內容沿用；`.listRowBackground(Color.clear)` 保留自繪選中底色、避免原生 accent 高亮疊加；頂部 padding 讓出紅綠燈）：

  ```swift
  private var sidebar: some View {
      List(selection: $selectedCategory) {
          ForEach(SettingsCategory.visibleCategories(labsUnlocked: settings.labsSettingsUnlocked)) { category in
              SidebarItemView(
                  category: category,
                  isSelected: selectedCategory == category,
                  showsNoticeDot: category == .integration && viewModel.hasIntegrationNotice
              )
              .tag(category)
              .listRowBackground(Color.clear)
              .simultaneousGesture(
                  TapGesture().onEnded {
                      selectSidebarCategory(category)
                  }
              )
              .accessibilityIdentifier("settings.sidebar.\(category.rawValue)")
          }
      }
      .listStyle(.sidebar)
      .padding(.top, 52)
  }
  ```

  `simultaneousGesture` 是 labs 彩蛋的關鍵：`List(selection:)` binding 在「重複點選已選中的 general」時不會再次觸發，連點 6 次永遠數不到；tap gesture 每次點擊都觸發 `selectSidebarCategory`，計數與 refresh 照舊（selection binding 與 gesture 都會寫 `selectedCategory`，收斂到同值；`scheduleCategoryRefresh` 先 cancel 再排程，重複呼叫無害）
- [ ] 刪 `sidebarWindowControls`（2630–2654）、`WindowControlButton`（3937–3953）、`SettingsWindowDragHandle`（2222–2236）、`SettingsSidebarSection`（2195–2200）、`sidebarSections`（2519–2526）；`SettingsPanelMetrics` 刪 `windowContentTopInset`、`outerPadding`
- [ ] `selectSidebarCategory` labs 跳轉加 runloop hop（List binding 可能在 gesture handler 之後才寫入 `.general`，直接同步設 `.labs` 會被蓋掉）：

  ```swift
  private func selectSidebarCategory(_ category: SettingsCategory) {
      selectedCategory = category

      if !settings.labsSettingsUnlocked, category != .general {
          consecutiveGeneralTapCount = 0
      } else if !settings.labsSettingsUnlocked, category == .general {
          consecutiveGeneralTapCount += 1
      }

      if !settings.labsSettingsUnlocked, consecutiveGeneralTapCount >= 6 {
          settings.labsSettingsUnlocked = true
          // List 的 selection binding 可能在本 handler 之後寫回 .general，
          // 延後一個 runloop turn 讓跳轉到 .labs 生效。
          DispatchQueue.main.async {
              selectedCategory = .labs
              scheduleCategoryRefresh(for: .labs, showLoading: shouldShowLoading(for: .labs))
          }
          return
      }

      let categoryToRefresh = currentCategory
      scheduleCategoryRefresh(
          for: categoryToRefresh,
          showLoading: shouldShowLoading(for: categoryToRefresh)
      )
  }
  ```
- [ ] `detail`：保留 `ScrollView` + 內部 VStack/switch + `.id(currentCategory)` + `.accessibilityIdentifier("settings.detail.\(currentCategory.rawValue)")`，刪掉其後整段 `.background(UnevenRoundedRectangle...)`、`.overlay(UnevenRoundedRectangle...strokeBorder...)`、`.shadow(...)`（手刻視窗殼的一部分，由原生欄背景取代）。卡片層 `SettingsSectionCard` + `SettingsGlassSurface(.hudWindow)` 不動
- [ ] 跑 `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP` runtime 驗證（Stage 2 是視覺驗收點，使用者確認後才進 Stage 3）：
  - 原生紅綠燈浮在 sidebar 上、無空白 title 條（若擋到列表第一列，微調 `.padding(.top, 52)` 的值後重 build 目測校準）；關閉=隱藏不退出、最小化、zoom 三顆都作用；原生視窗陰影存在
  - cmd-W 關窗照舊；視窗背景可拖曳；邊緣縮放尊重 min/max；display 分類「重置」按鈕恢復預設尺寸
  - 10 個分類逐一點選都切換 detail 且渲染與改動前一致；integration notice dot 照舊
  - display / sound / integration 切入時 loading 遮罩短暫出現後消失
  - labs 彩蛋：未解鎖時 labs 不在 sidebar；連點 general 6 次（含重複點已選中的 general）解鎖並自動跳到 labs
  - 從 notch 觸發 `SettingsWindowController.present(category:)` 跳到指定分類（跨視窗通知路徑走 root 的 onReceive → `selectSidebarCategory`，不受 List 化影響）
  - NavigationSplitView 若出現原生 sidebar 折疊 toolbar 按鈕或欄寬可拖，屬可接受的原生行為紅利；欄寬上下限已由 `navigationSplitViewColumnWidth` 釘住
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "feat: native titled window chrome + NavigationSplitView shell for settings"`

---

## Stage 3：foundation 機械搬遷（每檔一搬一 build）

搬遷通則（下同）：剪下的 top-level 型別若帶 `private`，貼到新檔時移除 `private`（同 target 內 internal 即可）；本來就非 private 的型別（`SettingsCategory`、`SettingsPanelViewModel`、`QoderCLIHookRefreshNoticeGate`、`ClosedNotchUsageAvailability`、`AccessibilityPermissionStatus`、`HookInstallOptionsMode`、`HookInstallOptionsRequest`、`IslandSurfaceModeSelector`、`IslandSurfaceModeCard`）搬檔不改存取層級。新檔開頭 import 依內容補齊（基本組合：`import SwiftUI` + 需要時 `import AppKit` / `import Combine` / `import Carbon.HIToolbox` / `import ServiceManagement` / `import UniformTypeIdentifiers`，以 build 錯誤為準補）。

### Task 4: `Settings/SettingsCategory.swift` + gating 單元測試

**Files**

- Create: `PingIsland/UI/Views/Settings/SettingsCategory.swift`（來源：單體檔 lines 8–87）
- Create: `PingIslandTests/SettingsCategoryTests.swift`
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪 8–87）

**Interfaces**

- Produces（原樣搬出，不改）: `enum SettingsCategory: String, CaseIterable, Identifiable`，含 `title`/`subtitle`/`icon`/`tint`/`static func visibleCategories(labsUnlocked: Bool) -> [SettingsCategory]`。`rawValue` 同時是 accessibility identifier 與跨視窗跳轉通知 payload，不可改名

**Steps**

- [ ] `mkdir -p PingIsland/UI/Views/Settings/Components PingIsland/UI/Views/Settings/Categories`
- [ ] 剪下單體檔 lines 8–87 的 `enum SettingsCategory` 整段，貼入新檔 `Settings/SettingsCategory.swift`，檔頭加 `import SwiftUI`
- [ ] RED — 新增 `PingIslandTests/SettingsCategoryTests.swift`（先寫測試；enum 已搬出仍同 target，立即可測）：

  ```swift
  import XCTest
  @testable import PingIsland

  final class SettingsCategoryTests: XCTestCase {
      func testVisibleCategoriesHideLabsWhenLocked() {
          let categories = SettingsCategory.visibleCategories(labsUnlocked: false)
          XCTAssertFalse(categories.contains(.labs))
          XCTAssertEqual(categories, SettingsCategory.allCases.filter { $0 != .labs })
      }

      func testVisibleCategoriesKeepDeclaredOrderWhenUnlocked() {
          XCTAssertEqual(
              SettingsCategory.visibleCategories(labsUnlocked: true),
              SettingsCategory.allCases
          )
      }
  }
  ```

  （此測試對現有正確實作直接綠：這裡的 TDD 價值是把 gating 行為釘死，防後續搬遷改壞）
- [ ] 跑 `UNIT-TEST` → `** TEST SUCCEEDED **`（含新測試 2 條）
- [ ] 跑 `BUILD` → `** BUILD SUCCEEDED **`（驗證 PBXFileSystemSynchronizedRootGroup 有把新檔納入 target；若 build 找不到型別，停下檢查 pbxproj 的 synchronized group 設定而不是手加檔案參照）
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract SettingsCategory into Settings/ with gating tests"`

### Task 5: `Settings/SettingsPanelViewModel.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/SettingsPanelViewModel.swift`（來源：單體檔 lines 89–657）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪該區段）

**Interfaces**

- Produces（原樣搬出）: `struct QoderCLIHookRefreshNoticeGate`（89–107）、`struct ClosedNotchUsageAvailability: Equatable`（108–152）、`enum AccessibilityPermissionStatus`（153–172）、`@MainActor final class SettingsPanelViewModel: ObservableObject`（173–657，含 `refresh(for:)`、`refreshInitialState()`、`refreshAccessibilityStatus()`、`refreshLocalizedState()`、`installHooks`/`reinstallHooks`/`uninstallHooks`/`uninstallAllHooks`、`currentHookSelection(for:)`、`hasIntegrationNotice`）

**Steps**

- [ ] 確認搬遷邊界：`sed -n '88,90p;172,175p;655,660p' PingIsland/UI/Views/SettingsWindowView.swift`（以 Task 4 後的實際行號對齊符號錨點：起於 `struct QoderCLIHookRefreshNoticeGate`，迄於 `SettingsPanelViewModel` 的收尾 `}`，即原 line 657）
- [ ] 剪下四個型別整段貼入新檔；檔頭 import 先放 `import AppKit`、`import Combine`、`import SwiftUI`、`import ServiceManagement`，以 build 錯誤增刪
- [ ] 跑 `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract SettingsPanelViewModel and hook-state types into Settings/"`

### Task 6: `Settings/Components/`（跨分類共用元件 + GlassSurface + SettingsScreenPicker）

歸屬由 callsite grep 定案（已於 2026-07-03 預查）：進 Components 的是「至少兩個分類使用」者。`SettingsClientIcon`（callsites 4824、5409 都在 integration 型別內）與 `SettingsStatusLine`（callsite 3420 僅 integration）依 spec 的單一使用者規則跟 integration 檔走（Task 14），不進 Components——此處與 spec 檔案地圖表格不同，但符合 spec 自己的歸屬規則。

**Files**

- Create: `PingIsland/UI/Views/Settings/Components/SettingsComponents.swift`（來源：`SettingsSectionCard` 3955–4025、`SettingsLineDivider` 4026–4033、`HookManagementButton` 5519–5555（display 2948/3074 與 integration 3284 等跨分類共用）、`SettingsToggleLine` 5556–5588、`private extension View`（`settingsMenuPicker` 等）5589–5605、`SettingsInfoLine` 5606–5635、`SettingsActionLine` 5673–5708、`SettingsCodeCapsule` 5748–5777、`SettingsValueLine` 5778–5799、`SettingsSliderLine` 5800–5855；另新增 `SettingsScreenPicker`）
- Create: `PingIsland/UI/Views/Settings/Components/SettingsGlassSurface.swift`（來源：2202–2220）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述區段；刪 `screenPicker` 3663–3672、`screenSelectionBinding` 3684–3707、`screenToken` 3716–3719；generalContent line 2850 與 displayContent line 2919 的 `screenPicker` 引用改為 `SettingsScreenPicker()`）

**Interfaces**

- Produces: 上列元件原樣（移除 `private`）；`extension View`（原 `private extension View`）
- Produces（新增，唯一的非純搬遷元件；因 `screenPicker` 同時被 general 與 display 使用，成員 var 必須升級為獨立 view）:

  ```swift
  struct SettingsScreenPicker: View {
      @ObservedObject private var screenSelector = ScreenSelector.shared

      var body: some View {
          Picker("显示器", selection: screenSelectionBinding) {
              Text(appLocalized: "自动").tag("automatic")
              ForEach(screenSelector.availableScreens, id: \.self) { screen in
                  Text(screen.localizedName).tag(screenToken(for: screen))
              }
          }
          .labelsHidden()
          .settingsMenuPicker(width: 168)
      }

      // screenSelectionBinding：逐字搬自單體檔 lines 3684–3707（Binding<String>，
      // get 讀 screenSelector.selectionMode / selectedScreen，
      // set 走 selectAutomatic()/selectScreen(_:) 並 post didChangeScreenParametersNotification）
      // screenToken(for:)：逐字搬自 lines 3716–3719（ScreenIdentifier 組 token）
  }
  ```

**Steps**

- [ ] 建 `SettingsGlassSurface.swift`：剪貼 2202–2220，`private struct` → `struct`，import `SwiftUI` + `AppKit`
- [ ] 建 `SettingsComponents.swift`：依 Files 清單逐段剪貼（每段各自把 `private struct` → `struct`、`private extension View` → `extension View`）；先各段搬完再一次 build（同檔內互相引用，分段 build 無意義）
- [ ] 在 `SettingsComponents.swift` 加入 `SettingsScreenPicker`（上方 Interfaces 的完整程式碼 + 逐字搬入的 `screenSelectionBinding`、`screenToken`）
- [ ] 單體檔：刪 `screenPicker`/`screenSelectionBinding`/`screenToken` 三個成員；generalContent 與 displayContent 中的 `screenPicker` 引用（原 2850、2919）改為 `SettingsScreenPicker()`
- [ ] 跑 `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP` runtime 驗證：general 與 display 兩個分類的顯示器 Picker 都能列出螢幕並切換（驗證 SettingsScreenPicker 升級無行為變更）；任一分類的卡片（SettingsSectionCard 玻璃底）渲染照舊
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract shared settings components into Settings/Components"`

---

## Stage 4：分類逐一搬遷（由簡到繁；每分類一 task 一 commit）

每個分類 task 的固定收尾：`BUILD` → `RUN-APP` 開該分類對照渲染與代表性控件 → commit。搬遷後單體檔中對應 `xxxContent` 計算屬性刪除、`detail` 的 switch case 改指新 view。

### Task 7: `Categories/AboutSettingsView.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/AboutSettingsView.swift`（來源：`aboutContent` 3464–3573 + about 專用 helper `appVersion` 3721–3723、`appBuild` 3725–3727、`versionMetadata` 3729–3745、`previousVersion` 3747–3754、`updateTitle` 3756–3771、`updateSubtitle` 3773–3801、`updateAccessory` 3803–3821、`handleUpdateAction` 3823–3830 — callsite 皆僅 aboutContent 內）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述；`detail` switch `case .about: aboutContent` → `case .about: AboutSettingsView(viewModel: viewModel)`）

**Interfaces**

- Produces:

  ```swift
  struct AboutSettingsView: View {
      @ObservedObject var viewModel: SettingsPanelViewModel
      @ObservedObject private var settings = AppSettings.shared
      @ObservedObject private var updateManager = UpdateManager.shared

      var body: some View {
          // 逐字貼入原 aboutContent 的 body（VStack(alignment: .leading, spacing: 18) { ... }）
      }

      // 逐字貼入八個 about helper
  }
  ```

  （aboutContent 依賴 grep 結果：`viewModel`、`settings`、`updateManager`；singleton 直接引用、viewModel 由 init 傳入）

**Steps**

- [ ] 歸屬覆核：`rg -n 'appVersion|versionMetadata|previousVersion|updateTitle|updateSubtitle|updateAccessory|handleUpdateAction' PingIsland/UI/Views/SettingsWindowView.swift` → 確認 callsite 全在 aboutContent 範圍內
- [ ] 建新檔（Interfaces 骨架 + 逐字剪貼），import `SwiftUI` + `AppKit`
- [ ] 單體檔刪 `aboutContent` 與八個 helper；switch case 改 `AboutSettingsView(viewModel: viewModel)`
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「关于」→ 版本號/build/安裝 metadata 顯示、「检查更新」按鈕可按且 updateManager 狀態文案照舊
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract about settings category view"`

### Task 8: `Categories/LabsSettingsView.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/LabsSettingsView.swift`（來源：`labsContent` 3456–3463 + `LabsEmptyStateView` 5466–5518，callsite 僅 labs）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述；`case .labs: labsContent` → `case .labs: LabsSettingsView()`）

**Interfaces**

- Produces: `struct LabsSettingsView: View`（無 init 參數；labsContent body 逐字貼入；內部若引用 `settings` 則補 `@ObservedObject private var settings = AppSettings.shared`，以 build 錯誤為準）；`struct LabsEmptyStateView: View`（去 `private`，同檔）

**Steps**

- [ ] 建新檔、剪貼 `labsContent` body 與 `LabsEmptyStateView`；單體檔刪除、switch case 改指新 view
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：解鎖狀態下（`defaults` 已解鎖或重走 6 連點）開「实验室」→ 內容/空狀態渲染照舊
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract labs settings category view"`

### Task 9: `Categories/ShortcutsSettingsView.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/ShortcutsSettingsView.swift`（來源：`shortcutsContent` 3118–3157、`shortcutBinding(for:)` 3709–3714（callsite 僅 shortcuts：3123、3128）、`ShortcutSettingsLine` 5856–5871、`ShortcutRecorderControl` 5872–6047、`ShortcutIconButtonStyle` 6048–6094）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述；`case .shortcuts: shortcutsContent` → `case .shortcuts: ShortcutsSettingsView()`）

**Interfaces**

- Produces:

  ```swift
  struct ShortcutsSettingsView: View {
      @ObservedObject private var settings = AppSettings.shared

      var body: some View { /* 逐字貼入 shortcutsContent body */ }

      private func shortcutBinding(for action: GlobalShortcutAction) -> Binding<GlobalShortcut?> {
          Binding(
              get: { settings.shortcut(for: action) },
              set: { settings.setShortcut($0, for: action) }
          )
      }
  }
  ```

**Steps**

- [ ] 建新檔（含三個 Shortcut* 型別去 `private` 同檔搬入），import `SwiftUI` + `AppKit` + `Carbon.HIToolbox`（ShortcutRecorderControl 需要 keycode）
- [ ] 單體檔刪除來源區段；switch case 改指新 view
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「快捷键」→ 錄製控件可進入錄製狀態、錄一組快捷鍵成功寫入並顯示、清除鈕作用
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract shortcuts settings category view"`

### Task 10: `Categories/GeneralSettingsView.swift`

`replayNotchDetachmentHint` / `replayFirstRunOnboardingDemo` 的 callsite grep 結果與 spec 的初步歸屬猜測不同：`replayNotchDetachmentHint` 唯一 callsite 在 displayContent（line 2951）→ 歸 display（Task 11）；`replayFirstRunOnboardingDemo` 唯一 callsite 在 integrationContent（line 3397）→ 歸 integration（Task 14）。general 不帶任何 replay helper（spec 的歸屬規則「由 callsite 定」優先於其表格例示）。

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/GeneralSettingsView.swift`（來源：`generalContent` 2828–2911 + `appLanguagePicker` 3674–3682（callsite 僅 generalContent line 2835））
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述；`case .general: generalContent` → `case .general: GeneralSettingsView(viewModel: viewModel)`）

**Interfaces**

- Produces:

  ```swift
  struct GeneralSettingsView: View {
      @ObservedObject var viewModel: SettingsPanelViewModel
      @ObservedObject private var settings = AppSettings.shared

      var body: some View { /* 逐字貼入 generalContent body；其中 screenPicker 已在 Task 6 改為 SettingsScreenPicker() */ }

      private var appLanguagePicker: some View { /* 逐字搬入 3674–3682 */ }
  }
  ```

**Steps**

- [ ] 歸屬覆核：`rg -n 'replayNotchDetachmentHint|replayFirstRunOnboardingDemo|appLanguagePicker' PingIsland/UI/Views/SettingsWindowView.swift` → 確認 replay helpers 不被 generalContent 引用、`appLanguagePicker` 僅 general 使用
- [ ] 建新檔、剪貼；單體檔刪除、switch case 改指新 view
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「通用」→「登录时打开」toggle 切換寫入生效、語言 Picker 切換後文案即時變化（`AppLocalizedRootView` 生效）、顯示器 Picker 照舊
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract general settings category view"`

### Task 11: `Categories/DisplaySettingsView.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/DisplaySettingsView.swift`（來源：`displayContent` 2912–3082、`resetSettingsPanelSize` 3084–3087（callsite 3077）、`replayNotchDetachmentHint` 3089–3097（callsite 2951）、display 專用子 view 群 6095–6660：`ClosedNotchTrailingContentPicker` 6110、`FloatingPetSizeModePicker` 6128、`IslandSurfaceModeSelector` 6144、`IslandSurfaceModeCard` 6180、`IslandSurfaceModePreviewScene` 6198、`DisplayPreviewMascotPicker` 6389、`FloatingPetPlacementInfoCard` 6415、`NotchDisplayPreviewMock` 6432、`NotchDisplayModeSelector` 6496、`NotchDisplayModeCard` 6526）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述；`case .display: displayContent` → `case .display: DisplaySettingsView(viewModel: viewModel, onClose: onClose)`）

**Interfaces**

- Produces:

  ```swift
  struct DisplaySettingsView: View {
      @ObservedObject var viewModel: SettingsPanelViewModel
      var onClose: (() -> Void)?
      @ObservedObject private var settings = AppSettings.shared
      @ObservedObject private var screenSelector = ScreenSelector.shared

      var body: some View { /* 逐字貼入 displayContent body */ }

      private var currentWindow: NSWindow? {
          NSApp.keyWindow ?? NSApp.mainWindow
      }

      private func resetSettingsPanelSize() {
          SettingsWindowLayout.resetContentSize(of: currentWindow)
      }

      private func replayNotchDetachmentHint() { /* 逐字搬入 3089–3097，含 onClose?() 呼叫 */ }
  }
  ```

  （`currentWindow` 是 root 上的一行 helper，display 是搬出後唯一還需要它的分類，直接複製這一行，root 保留自己的那份供 onAppear/visibility 使用）

**Steps**

- [ ] 存取層級覆核（`IslandSurfaceModeSelector`/`IslandSurfaceModeCard` 有檔外 caller — first-run onboarding）：`rg -n 'IslandSurfaceModeSelector|IslandSurfaceModeCard' PingIsland --glob '!PingIsland/UI/Views/SettingsWindowView.swift'` → 記下外部 callsite；兩型別搬檔時保持 internal（現狀即 internal）不加 `private`
- [ ] 建新檔（Interfaces 骨架 + 子 view 群逐字剪貼、各自去 `private`；`IslandSurfaceModeSelector`/`Card` 原樣不加修飾），import `SwiftUI` + `AppKit`
- [ ] 單體檔刪除來源區段；switch case 改 `DisplaySettingsView(viewModel: viewModel, onClose: onClose)`
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「显示」→ surface mode 卡可切換且預覽動、notch 顯示模式卡切換、「重置」恢復預設視窗尺寸、重播分離提示按鈕會關閉 Settings 視窗並觸發 notch 提示（驗 onClose 鏈）
- [ ] first-run onboarding 外部 caller 冒煙：`rg` 記下的外部 callsite 檔案能 build（`BUILD` 已涵蓋）即可
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract display settings category view"`

### Task 12: `Categories/SoundSettingsView.swift`

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/SoundSettingsView.swift`（來源：`SoundSettingsContent` 664–866、`SoundPackSourceInfoLine` 5636–5672、`SoundPackImportActionLine` 5709–5747、sound 列群 6705–6922：`SoundEventSection`、`SoundStartupLine`、`SoundEventTextBlock`、`SoundPreviewButton`、`SoundControlCluster`、`SoundEventSettingsLine`、`SoundPackEventLine`、`BundledSoundEventLine`）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪上述與 `soundContent` 包裝 var 3163–3165；`case .sound: soundContent` → `case .sound: SoundSettingsContent()`）

**Interfaces**

- Produces: `struct SoundSettingsContent: View`（去 `private`，符號名逐字保留不改名 — spec 搬遷原則「剪貼不重寫」優先於架構圖上的示意名）及其子 view 群（各去 `private`）。無 init 參數（自帶 `AppSettings.shared` / `SoundPackCatalog.shared`）

**Steps**

- [ ] 歸屬覆核：`rg -n 'SoundPackSourceInfoLine|SoundPackImportActionLine|SoundEventSection|SoundStartupLine|SoundPreviewButton|SoundControlCluster|SoundEventSettingsLine|SoundPackEventLine|BundledSoundEventLine|SoundEventTextBlock' PingIsland/UI/Views/SettingsWindowView.swift` → callsite 全在 sound 區段
- [ ] 建新檔、逐段剪貼去 `private`；單體檔刪除、刪 `soundContent` 包裝 var、switch case 改 `SoundSettingsContent()`
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「声音」→ loading 遮罩短暫出現、聲音包列表渲染、預覽播放按鈕出聲、啟動音 toggle 切換
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract sound settings category view"`

### Task 13: `Categories/AnalyticsSettingsView.swift` + `AgentUsageCharts.swift` + `AgentUsageRows.swift`

1300 行 cluster（868–2150）依 spec 切三檔：viewmodel+content / chart / row。

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/AnalyticsSettingsView.swift`（`AgentUsageAnalyticsViewModel` 868–905、`AgentUsageAnalyticsContent` 906–1037、`AgentUsageLoadingOverlay` 1038–1073、`AgentUsageRangeControl` 1074–1106、`AgentUsageFormat` 2065–2150 — Format 被 chart 與 row 共用，錨在主檔）
- Create: `PingIsland/UI/Views/Settings/Categories/AgentUsageCharts.swift`（`AgentUsageSpendBarChart` 1406–1454、`AgentUsageSparklineBackdrop` 1455–1512、`AgentUsageSparklineStroke` 1513–1520、`AgentUsageSparklineFill` 1521–1554、`AgentUsageHeatmapView` 1748–2041）
- Create: `PingIsland/UI/Views/Settings/Categories/AgentUsageRows.swift`（`AgentUsageSummaryCards` 1107–1198、`AgentUsageSummaryCard` 1199–1283、`AgentUsageSpendPanel` 1284–1310、`AgentUsageSpendFooter` 1311–1372、`AgentUsageSpendMetricTile` 1373–1405、`AgentUsageOverviewLine` 1555–1602、`AgentUsageMetricLine` 1603–1635、`AgentUsageTokenSplitLine` 1636–1655、`AgentUsageTokenPill` 1656–1677、`AgentUsageRankingList` 1678–1699、`AgentUsageRankingRow` 1700–1747、`AgentUsageInsetDivider` 2042–2048、`AgentUsageEmptyLine` 2049–2064）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（刪 868–2150 與 `analyticsContent` 包裝 var 3167–3169；`case .analytics: analyticsContent` → `case .analytics: AgentUsageAnalyticsContent()`）

**Interfaces**

- Produces: 全部型別原樣去 `private`；`AgentUsageAnalyticsContent` 自帶自己的 `@StateObject`（`AgentUsageAnalyticsViewModel`），無 init 參數；三檔互相以 internal 可見

**Steps**

- [ ] 邊界覆核：`rg -n '^(private )?(struct|final class|enum) AgentUsage' PingIsland/UI/Views/SettingsWindowView.swift` → 對照上列 22 個型別無遺漏（若有本表未列的 `AgentUsage*` 符號，依「chart=sparkline/bar/heatmap、row=line/pill/ranking/card、其餘錨主檔」規則就近歸檔）
- [ ] 依 Files 分配逐段剪貼建三檔（各去 `private`；`@MainActor` 標註原樣保留），import `SwiftUI`（Charts 檔若引用 `AppKit` 型別以 build 錯誤補）
- [ ] 單體檔刪除來源區段與 `analyticsContent` 包裝 var；switch case 改 `AgentUsageAnalyticsContent()`
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「统计」→ 摘要卡/sparkline/長條圖/heatmap 渲染、時間範圍切換控件切換後數字與圖表更新
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract analytics settings views into three focused files"`

### Task 14: `Categories/IntegrationSettingsView.swift`（含 hook sheet 狀態下沉）

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/IntegrationSettingsView.swift`（來源：`integrationContent` 3171–3455、`replayFirstRunOnboardingDemo` 3099–3117（callsite 3397）、hook 型別群：`HookManagementLine` 4034–4166、`CustomHookInstallationLine` 4167–4241、`CustomHookInstallSheet` 4242–4473、`HookInstallOptionsMode` 4474–4478、`HookInstallOptionsRequest` 4479–4484、`HookInstallOptionsSheet` 4485–4726（`CategoryToggleState` 若為其巢狀型別隨檔走）、`CategoryToggleRow` 4727–4782、`EventToggleRow` 4783–4819、`HookManagementIcon` 4820–4832、`IDEExtensionManagementLine` 5337–5404、`IDEExtensionManagementIcon` 5405–5417、`SettingsClientIcon` 5418–5465（callsite 僅 integration 型別內）、`SettingsStatusLine` 6661–6704（callsite 僅 3420））
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`：
  - 刪 root 的 4 個 `@State`：`pendingHookReinstallProfile`、`pendingHookOptionsRequest`、`showingUninstallAllHooksConfirmation`、`showingCustomHookInstallSheet`（2261–2264）
  - 從 root body 剪下並隨遷：「重新安装 Hooks？」alert（2368–2387）、「一键卸载所有 Hooks 配置文件？」alert（2388–2398）、`CustomHookInstallSheet` sheet（2399–2403）、`HookInstallOptionsSheet` sheet（2404–2422）
  - `case .integration: integrationContent` → `case .integration: IntegrationSettingsView(viewModel: viewModel)`

**Interfaces**

- Produces:

  ```swift
  struct IntegrationSettingsView: View {
      @ObservedObject var viewModel: SettingsPanelViewModel
      @ObservedObject private var settings = AppSettings.shared
      @State private var pendingHookReinstallProfile: ManagedHookClientProfile?
      @State private var pendingHookOptionsRequest: HookInstallOptionsRequest?
      @State private var showingUninstallAllHooksConfirmation = false
      @State private var showingCustomHookInstallSheet = false

      var body: some View {
          content            // 逐字貼入 integrationContent body
              // 逐字貼入四個 .alert / .sheet modifier（2368–2422），
              // 掛在 content 之後 — 只在 integration 顯示時掛載即可：
              // 這 4 個狀態全部只由本分類內的使用者操作觸發，無外部通知發送方，
              // 下沉不會漏接（root 的三個 onReceive 全數留在 root，見下）
      }

      private var content: some View { /* integrationContent body */ }
      private func replayFirstRunOnboardingDemo() { /* 逐字搬入 3099–3117 */ }
  }
  ```

- onReceive 時序審計結論（spec Risks 要求逐一列出）：root 現有三個 onReceive — `.settingsWindowVisibilityDidChange`（controller 發，跨分類）、`.settingsWindowCategorySelectionRequested`（controller 發，跨視窗跳轉）、`NSApplication.didBecomeActiveNotification`（系統發）— 全部留在 root，一個都不下沉；integration/remote 下沉的只有純使用者操作觸發的 alert/sheet 狀態

**Steps**

- [ ] `CategoryToggleState` 定位：`rg -n 'CategoryToggleState' PingIsland/UI/Views/SettingsWindowView.swift` → 若為 `HookInstallOptionsSheet` 巢狀型別則隨 4485–4726 自然搬走；若為 top-level 則併入本檔
- [ ] 建新檔（Interfaces 骨架 + 全部型別逐字剪貼去 `private`；`HookInstallOptionsMode`/`Request` 原本就 internal 保持不動），import `SwiftUI` + `AppKit`
- [ ] root body 剪下四個 alert/sheet modifier 貼到新 view 的 body；root 刪 4 個 `@State`
- [ ] 單體檔刪 `integrationContent`、`replayFirstRunOnboardingDemo`；switch case 改指新 view
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「集成」→ loading 遮罩短暫出現、hook 用戶端列表渲染、對一個 profile 按安裝/重新安裝 → options sheet / reinstall alert 正常開合並走 `viewModel.installHooks`/`reinstallHooks`、一鍵卸載確認 alert 開合、自訂 hook 安裝 sheet 開合、sidebar 的 integration notice dot 照舊（dot 讀 root 共享的同一個 viewModel 實例）
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract integration settings view with hook sheet state"`

### Task 15: `Categories/RemoteSettingsView.swift`（含 remote sheet 狀態下沉）

**Files**

- Create: `PingIsland/UI/Views/Settings/Categories/RemoteSettingsView.swift`（來源：`remoteContent` 3574–3661、`RemoteHostManagementLine` 4833–5045、`AddRemoteHostSheet` 5046–5191、`RemotePasswordPromptAction` 5192–5214、`RemotePasswordPromptRequest` 5215–5223、`RemotePasswordPromptSheet` 5224–5336）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`：
  - 刪 root 的 2 個 `@State`：`showingRemoteHostSheet`、`remotePasswordPromptRequest`（2265–2266）
  - 從 root body 剪下並隨遷：`AddRemoteHostSheet` sheet（2423–2427）、`RemotePasswordPromptSheet` sheet（2428–2440）
  - `case .remote: remoteContent` → `case .remote: RemoteSettingsView()`

**Interfaces**

- Produces:

  ```swift
  struct RemoteSettingsView: View {
      @ObservedObject private var remoteManager = RemoteConnectorManager.shared
      @ObservedObject private var settings = AppSettings.shared
      @State private var showingRemoteHostSheet = false
      @State private var remotePasswordPromptRequest: RemotePasswordPromptRequest?

      var body: some View {
          content
              // 逐字貼入兩個 .sheet modifier（2423–2440）：
              // AddRemoteHostSheet(remoteManager:onDismiss:) 與
              // RemotePasswordPromptSheet(request:onSubmit:onDismiss:)（connect / uninstallBridge 分支照舊）
      }

      private var content: some View { /* 逐字貼入 remoteContent body（3574–3661） */ }
  }
  ```

  兩個下沉狀態同樣只由本分類內操作觸發（列表按鈕開 sheet、連線要密碼時由本分類內 action 設 request），無外部通知發送方

**Steps**

- [ ] 依賴覆核：`sed` 前次全檔掃描把 3663–3830 的 helper 區誤併入 remote 範圍；先確認 `remoteContent` 實際 body 止於 3661：`rg -n 'private var remoteContent|private var screenPicker' PingIsland/UI/Views/SettingsWindowView.swift`，再 `rg -n 'settings\.|remoteManager\.'` 於該範圍確認實際依賴（預期 `remoteManager` + `settings`；若有多的 singleton 依 build 錯誤補 `@ObservedObject`）
- [ ] 建新檔（骨架 + 逐字剪貼去 `private`）；root 剪下兩個 sheet、刪 2 個 `@State`；單體檔刪 `remoteContent`；switch case 改 `RemoteSettingsView()`
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP`：開「远程」→ 主機列表渲染、「新增主機」sheet 開合、對既有主機觸發連線出現密碼 prompt sheet（有 SSH 測試主機才驗連線本身；sheet 開合為必驗項）
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: extract remote settings view with host sheet state"`

---

## Stage 5：收尾

### Task 16: 殼拆檔 — SettingsRootView / SettingsSidebarView / SettingsDetailRouter，SettingsWindowView 縮成薄包裝

**Files**

- Create: `PingIsland/UI/Views/Settings/SettingsRootView.swift`（`SettingsPanelContentView` 更名 `SettingsRootView` 整體搬入 + `SettingsPanelMetrics` 精簡版）
- Create: `PingIsland/UI/Views/Settings/SettingsSidebarView.swift`（`sidebar` List + `SidebarItemView` 3858–3935）
- Create: `PingIsland/UI/Views/Settings/SettingsDetailRouter.swift`（`detail` switch + `SettingsCategoryLoadingView` 2151–2193）
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift`（縮成薄包裝，目標 < 100 行）

**Interfaces**

- Produces:

  ```swift
  // SettingsSidebarView.swift
  struct SettingsSidebarView: View {
      @Binding var selectedCategory: SettingsCategory?
      let labsUnlocked: Bool
      let hasIntegrationNotice: Bool
      let onTap: (SettingsCategory) -> Void
      // body = Task 3 的 List(selection:)，
      // showsNoticeDot 改讀 hasIntegrationNotice、
      // visibleCategories(labsUnlocked: labsUnlocked)、
      // simultaneousGesture 呼叫 onTap(category)
  }

  // SettingsDetailRouter.swift
  struct SettingsDetailRouter: View {
      let currentCategory: SettingsCategory
      let loadingCategory: SettingsCategory?
      @ObservedObject var viewModel: SettingsPanelViewModel
      var onClose: (() -> Void)?
      // body = 現 detail 的 ScrollView + loading 分支 + switch（各 case 指 Stage 4 的分類 view）
      // + .id(currentCategory) + .accessibilityIdentifier("settings.detail.\(currentCategory.rawValue)")
      // mascot case 直接 MascotSettingsView()（刪 mascotContent 包裝 var）
  }

  // SettingsRootView.swift — 持有全部跨分類狀態與 modifier 鏈：
  struct SettingsRootView: View {
      var onClose: (() -> Void)? = nil
      @StateObject private var viewModel = SettingsPanelViewModel()
      // selectedCategory / loadingCategory / categoryRefreshTask /
      // consecutiveGeneralTapCount / showingAnalyticsConsentPrompt /
      // isAccessibilityPollingActive / arePreviewAnimationsActive 原樣保留
      // body = NavigationSplitView { SettingsSidebarView(selectedCategory: $selectedCategory,
      //   labsUnlocked: settings.labsSettingsUnlocked,
      //   hasIntegrationNotice: viewModel.hasIntegrationNotice,
      //   onTap: selectSidebarCategory) ... } detail: {
      //   SettingsDetailRouter(currentCategory: currentCategory, loadingCategory: loadingCategory,
      //   viewModel: viewModel, onClose: onClose) }
      // + 既有 onAppear/onDisappear/task/三個 onReceive/onChange/analytics consent alert
  }

  // SettingsWindowView.swift（薄包裝，保留檔名與型別名 — 兩個進入點的既有 API）
  struct SettingsWindowView: View {
      var onClose: (() -> Void)? = nil

      var body: some View {
          AppLocalizedRootView {
              SettingsRootView(onClose: onClose)
                  .accessibilityIdentifier("settings.root")
          }
      }
  }
  ```

**Steps**

- [ ] 搬 `SettingsCategoryLoadingView`（去 `private`）+ `detail` 內容成 `SettingsDetailRouter`（依 Interfaces；switch 各 case 已是一行分類 view 呼叫）；刪 `mascotContent` 包裝 var，case `.mascot` 直接 `MascotSettingsView()`
- [ ] 搬 `SidebarItemView`（去 `private`）+ `sidebar` 成 `SettingsSidebarView`（依 Interfaces）
- [ ] `SettingsPanelContentView` 更名 `SettingsRootView` 搬入 `Settings/SettingsRootView.swift`，body 的 sidebar/detail 引用改為兩個新 view；`SettingsPanelMetrics`（只剩 `windowSize`/`windowMinSize`/`windowMaxSize`/`windowSidebarWidth`）隨行搬入同檔
- [ ] `SettingsWindowView.swift` 縮成薄包裝（Interfaces 的完整程式碼）；`wc -l PingIsland/UI/Views/SettingsWindowView.swift` → 預期 < 100
- [ ] `rg -n 'SettingsPanelContentView' PingIsland` → 0 match
- [ ] `BUILD` → `** BUILD SUCCEEDED **`
- [ ] `RUN-APP` 冒煙：任點 3 個分類切換正常、labs 6 連點彩蛋仍作用（onTap 鏈經 SettingsSidebarView 轉發後的回歸點）、跨視窗 `present(category:)` 跳轉正常
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "refactor: split settings shell into root/sidebar/router files"`

### Task 17: 殘留清理、UI 測試連動、AGENTS.md、全量驗證

**Files**

- Modify: `PingIslandUITests/PingIslandUITests.swift`（lines 14, 24 — 僅在 query 型別不符時）
- Modify: `AGENTS.md`（Start Here 與 Change Routing 的 settings entry）

**Interfaces**

- Consumes: `app.buttons["settings.sidebar.general"]` / `app.buttons["settings.sidebar.about"]`（XCUIElement query；List row 可能不再是 `.button` 型別）
- Produces（僅在 UI-TEST 失敗於元素找不到時採用，屬測試連動不屬行為變更）：
  - line 14 → `XCTAssertTrue(app.descendants(matching: .any)["settings.sidebar.general"].waitForExistence(timeout: 5))`
  - line 24–27 → `let aboutButton = app.descendants(matching: .any)["settings.sidebar.about"]` （其後 `waitForExistence` / `tap()` 不變）

**Steps**

- [ ] 死碼殘留 grep（全部預期 0 match）：
  - `rg -in 'popover' PingIsland/UI PingIsland/Core --glob '!*Notch*'`（Settings 相關殘留；NotchView 系檔案若有無關的 popover 字樣不計）
  - `rg -n 'isSettingsPopoverPresented|SettingsPanelPresentation|NotchSettingsPopoverView|WindowControlButton|SettingsWindowDragHandle|SettingsSidebarSection|onMinimize' PingIsland PingIslandTests PingIslandUITests`
- [ ] 跑 `UNIT-TEST` → `** TEST SUCCEEDED **`
- [ ] 跑 `UI-TEST`；若兩條 sidebar 測試因 `app.buttons` query 型別失敗 → 套用 Interfaces 的 `descendants(matching: .any)` 改寫後重跑 → `** TEST SUCCEEDED **`
- [ ] `AGENTS.md` 更新（settings 相關 entry 指向新結構）：
  - Start Here 的 `First-run surface-mode onboarding and mode-switch UI:` 行，`PingIsland/UI/Views/SettingsWindowView.swift` → `PingIsland/UI/Views/Settings/`（`SettingsWindowView.swift` 仍是入口薄包裝，保留並列）
  - Change Routing 新增一條（放在 surface mode 那條之後）：`- If you change the Settings window, the shell lives in \`PingIsland/UI/Views/Settings/\` (SettingsRootView = NavigationSplitView shell, SettingsSidebarView, SettingsDetailRouter, SettingsPanelViewModel, Components/, Categories/ one file per category); \`SettingsWindowView.swift\` is only the thin entry wrapper shared by the Settings scene and SettingsWindowController. The window uses native titled chrome with \`safeAreaRegions = []\`; do not reintroduce custom window controls or drag handles.`
  - 全文搜尋其他 `SettingsWindowView.swift` 引用（`rg -n 'SettingsWindowView' AGENTS.md`）逐條校對是否仍準確
- [ ] Testing 節 runtime checklist 全跑（`RUN-APP`）：
  - 原生紅綠燈三顆作用、無空白 title 條、原生陰影；cmd-W 關窗（隱藏不退出）
  - 背景拖曳、邊緣縮放尊重 min/max、display「重置」恢復尺寸
  - 10 分類逐一開啟渲染一致 + 代表性控件（general toggle、display surface mode 卡、sound 預覽、analytics 範圍切換、integration install/reinstall sheet、remote 新增主機 sheet、shortcuts 錄製、about 檢查更新）
  - display/sound/integration 切入 loading 遮罩；integration notice dot
  - labs 彩蛋（未解鎖隱藏 → 6 連點解鎖跳轉）
  - notch 觸發 `present(category:)` 跳轉
  - app 選單 Settings scene 路徑開啟正常（SwiftUI 自管 chrome，維持預設外觀即符合預期）
  - 語言切換後文案生效
- [ ] `git add -A ':!PingIsland/UI/Views/NotificationFeedView.swift' && git commit -m "docs: update AGENTS.md for settings module split + UI test query fix"`
- [ ] 完成後走 superpowers:finishing-a-development-branch 決定 merge/PR

---

## Self-Review

執行完 Task 17 後逐項自查：

- [ ] Spec 覆蓋：Goal 四項（原生外觀 / 完整拆分 / popover 死碼 / 行為零變更）各自對應到 Task 3 / Tasks 4–16 / Tasks 1–2 / 每 task 的 runtime 驗證，無遺漏
- [ ] Spec「Removed dead code」表逐列核銷（Task 17 的 grep 步驟即核銷證據）
- [ ] Spec「Testing」節三條單元測試面向齊備：NotchViewModelTests 簽章連動（Task 1）、visibleCategories gating 新測試（Task 4）、UI 測試 identifier 存在性（Task 17）
- [ ] Placeholder 掃描：plan 內無 TBD / 「加上錯誤處理」/「同 Task N」式步驟；所有「逐字貼入」都指向明確符號名 + 行號範圍
- [ ] 型別一致性：`SettingsPanelViewModel` 全程只在 root `@StateObject` 一份、分類 view 一律 `@ObservedObject var viewModel` 或 singleton；`selectedCategory` 全程 `SettingsCategory?`；`onClose` 型別 `(() -> Void)?` 一路到 DisplaySettingsView
- [ ] 與 spec 的既知偏差已在對應 task 內註明：replay helper 歸屬（Task 10/11/14）、`SettingsClientIcon`/`SettingsStatusLine` 歸 integration（Task 6/14）、`SettingsScreenPicker` 新共用元件（Task 6）、uninstall-all 是 `.alert` 非 `.confirmationDialog`（Task 14）、三個 onReceive 全留 root（Task 14）、每 task 一 commit（Global Constraints）
- [ ] Plan/Spec 同步：若執行中發現與 spec 不符的新事實，先改 spec/plan 再繼續寫碼（CLAUDE.md V.6）

## Success criteria

1. `BUILD` 通過；`UNIT-TEST`（含新 SettingsCategoryTests）與 `UI-TEST` 綠。
2. `SettingsWindowView.swift` < 100 行；`Settings/` 下各檔單一責任、無跨檔重複定義（`rg` 每個搬出符號恰一個定義處）。
3. Task 17 runtime checklist 全數通過（含 labs 彩蛋與跨視窗分類跳轉）。
4. 死碼 grep 零殘留（Task 17 清單）。
5. 視窗為原生 titled 外觀：真紅綠燈、原生陰影、原生縮放/zoom，sidebar 為原生 `List(.sidebar)` vibrancy。
6. `AGENTS.md` settings entry 與新檔案結構 1:1 對應。
