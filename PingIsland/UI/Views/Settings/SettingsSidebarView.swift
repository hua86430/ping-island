import AppKit
import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selectedCategory: SettingsCategory?
    let labsUnlocked: Bool
    let hasIntegrationNotice: Bool
    let onTap: (SettingsCategory) -> Void

    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(SettingsCategory.visibleCategories(labsUnlocked: labsUnlocked)) { category in
                SidebarItemView(
                    category: category,
                    showsNoticeDot: category == .integration && hasIntegrationNotice
                )
                .tag(category)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        onTap(category)
                    }
                )
                .accessibilityIdentifier("settings.sidebar.\(category.rawValue)")
            }
        }
        .listStyle(.sidebar)
    }
}

// Flat macOS-style row: colored icon chip + single-line label. No per-row card;
// the native List(selection:) draws the selection highlight.
struct SidebarItemView: View {
    let category: SettingsCategory
    var showsNoticeDot: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(category.tint)
                    )

                if showsNoticeDot {
                    Circle()
                        .fill(TerminalColors.amber)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.42), lineWidth: 1)
                        )
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("有需要注意的集成提示")
                }
            }

            Text(appLocalized: category.title)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
