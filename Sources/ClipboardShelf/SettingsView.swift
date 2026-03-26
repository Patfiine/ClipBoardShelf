import SwiftUI

struct SettingsView: View {
    @ObservedObject var center: ClipboardCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("О приложении")
                .font(.title3.bold())

            Text("ClipboardShelf хранит тексты и снимки экрана из буфера обмена, а также поддерживает быстрое повторное копирование и моментальную вставку.")
                .foregroundStyle(.secondary)

            Text("Текстов: \(center.textItems.count) из \(center.maxTextItems)")
                .font(.subheadline)

            Text("Снимков: \(center.imageItems.count) из \(center.maxImageItems)")
                .font(.subheadline)

            Text(center.currentShortcutSummary)
                .font(.callout)

            Text("Для моментальной вставки включи доступ приложения в System Settings -> Privacy & Security -> Accessibility.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Accessibility: \(AXIsProcessTrusted() ? "включен" : "выключен")")
                .font(.caption)

            Text("Цель вставки: \(center.lastPasteTargetName)")
                .font(.caption)

            Text("Статус вставки: \(center.lastPasteStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
    }
}
