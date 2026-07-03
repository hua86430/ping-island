import SwiftUI

struct LabsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "实验室") {
                LabsEmptyStateView()
            }
        }
    }
}

struct LabsEmptyStateView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(SettingsCategory.labs.tint)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SettingsCategory.labs.tint.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(SettingsCategory.labs.tint.opacity(0.28), lineWidth: 1)
                )

            VStack(alignment: .center, spacing: 6) {
                Text("暂无可用实验")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text("实验室主要承载一些试验性特性，稳定性不做保障。当前没有开放中的实验项目。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
    }
}
