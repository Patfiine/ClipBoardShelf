import Foundation

enum ClipboardTab: String, CaseIterable, Identifiable {
    case text
    case screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            "Текст"
        case .screenshots:
            "Снимки"
        }
    }
}
