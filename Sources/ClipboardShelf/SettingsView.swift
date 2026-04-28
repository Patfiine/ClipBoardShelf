import SwiftUI

struct SettingsView: View {
    @ObservedObject var center: ClipboardCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("О приложении")
                    .font(.title3.bold())

                settingsText("ClipboardShelf хранит тексты и снимки экрана из буфера обмена, а также поддерживает быстрое повторное копирование и моментальную вставку.")
                    .foregroundStyle(.secondary)

                Text("Текстов: \(center.textItems.count) из \(center.maxTextItems)")
                    .font(.subheadline)

                Text("Снимков: \(center.imageItems.count) из \(center.maxImageItems)")
                    .font(.subheadline)

                settingsText(center.currentShortcutSummary)
                    .font(.callout)

                settingsText("Для моментальной вставки включи доступ приложения в System Settings -> Privacy & Security -> Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                settingsText("Accessibility: \(AXIsProcessTrusted() ? "включен" : "выключен")")
                    .font(.caption)

                settingsText("Цель вставки: \(center.lastPasteTargetName)")
                    .font(.caption)

                settingsText("Статус вставки: \(center.lastPasteStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func settingsText(_ value: String) -> some View {
        Text(value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}
