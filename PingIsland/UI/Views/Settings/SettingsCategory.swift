import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case display
    case analytics
    case mascot
    case sound
    case integration
    case remote
    case labs
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcuts: return "快捷键"
        case .display: return "显示"
        case .mascot: return "宠物"
        case .sound: return "声音"
        case .analytics: return "统计"
        case .integration: return "集成"
        case .remote: return "远程"
        case .labs: return "实验室"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "系统与基础行为"
        case .shortcuts: return "全局展开与自定义"
        case .display: return "显示器与位置"
        case .mascot: return "客户端宠物与动作"
        case .sound: return "通知与提示音"
        case .analytics: return "Agent、Token 与工具"
        case .integration: return "Hooks 与 IDE 扩展"
        case .remote: return "SSH 主机与远程转发"
        case .labs: return "试验性特性"
        case .about: return "版本与更新"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "command.square.fill"
        case .display: return "rectangle.on.rectangle"
        case .mascot: return "face.smiling.fill"
        case .sound: return "speaker.wave.2.fill"
        case .analytics: return "chart.bar.xaxis"
        case .integration: return "link.circle.fill"
        case .remote: return "network.badge.shield.half.filled"
        case .labs: return "flask.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.12, green: 0.42, blue: 0.95)
        case .shortcuts: return Color(red: 0.25, green: 0.82, blue: 0.46)
        case .display: return Color(red: 0.46, green: 0.40, blue: 0.96)
        case .mascot: return Color(red: 0.91, green: 0.27, blue: 0.81)  // Pink
        case .sound: return Color(red: 0.22, green: 0.83, blue: 0.42)
        case .analytics: return Color(red: 0.97, green: 0.70, blue: 0.22)
        case .integration: return Color(red: 0.16, green: 0.76, blue: 0.72)
        case .remote: return Color(red: 0.95, green: 0.54, blue: 0.20)
        case .labs: return Color(red: 0.82, green: 0.48, blue: 0.97)
        case .about: return Color(red: 0.17, green: 0.60, blue: 0.96)
        }
    }

    static func visibleCategories(labsUnlocked: Bool) -> [SettingsCategory] {
        allCases.filter { category in
            category != .labs || labsUnlocked
        }
    }
}
