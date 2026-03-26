import AppKit
import SwiftUI

struct ClipboardMenuView: View {
    @ObservedObject var center: ClipboardCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tabPicker

            switch center.selectedTab {
            case .text:
                textList
            case .screenshots:
                screenshotList
            }
        }
        .padding(14)
        .background(
            KeyboardEventHandler { event in
                center.handleKeyEvent(event)
            }
            .frame(width: 0, height: 0)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ClipboardShelf")
                    .font(.headline)
                Text(center.currentShortcutSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Очистить вкладку") {
                center.clearCurrentTab()
            }
            .disabled(isCurrentTabEmpty)

            Button("Выход") {
                center.quitApplication()
            }
        }
    }

    private var tabPicker: some View {
        Picker("Вкладка", selection: $center.selectedTab) {
            ForEach(ClipboardTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var textList: some View {
        Group {
            if center.textItems.isEmpty {
                emptyState(
                    title: "Текстовая история пуста",
                    systemImage: "text.quote",
                    description: "Скопируй любой текст, и он появится здесь."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(center.textItems) { item in
                                TextClipboardRow(
                                    item: item,
                                    isSelected: center.isSelected(textItem: item),
                                    onSelect: { center.selectText(item) },
                                    onInstantPaste: { center.pasteTextImmediately(item) },
                                    onCopy: { center.copyText(item) },
                                    onDelete: { center.removeText(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollToSelectedText(with: proxy)
                    }
                    .onChange(of: center.selectedTextID) { _ in
                        scrollToSelectedText(with: proxy)
                    }
                }
            }
        }
    }

    private var screenshotList: some View {
        Group {
            if center.imageItems.isEmpty {
                emptyState(
                    title: "Снимков пока нет",
                    systemImage: "photo.on.rectangle",
                    description: "Сделай снимок экрана в буфер обмена, и он появится здесь."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(center.imageItems) { item in
                                ScreenshotClipboardRow(
                                    item: item,
                                    image: center.image(for: item),
                                    isSelected: center.isSelected(imageItem: item),
                                    onSelect: { center.selectImage(item) },
                                    onInstantPaste: { center.pasteImageImmediately(item) },
                                    onCopy: { center.copyImage(item) },
                                    onDelete: { center.removeImage(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollToSelectedImage(with: proxy)
                    }
                    .onChange(of: center.selectedImageID) { _ in
                        scrollToSelectedImage(with: proxy)
                    }
                }
            }
        }
    }

    private var isCurrentTabEmpty: Bool {
        switch center.selectedTab {
        case .text:
            center.textItems.isEmpty
        case .screenshots:
            center.imageItems.isEmpty
        }
    }

    private func emptyState(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToSelectedText(with proxy: ScrollViewProxy) {
        guard let id = center.selectedTextID else {
            return
        }

        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func scrollToSelectedImage(with proxy: ScrollViewProxy) {
        guard let id = center.selectedImageID else {
            return
        }

        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct TextClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onInstantPaste: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var previewText: String {
        let singleLine = item.text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(150))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(previewText)
                .font(.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onInstantPaste()
                } label: {
                    Image(systemName: "arrowshape.turn.up.forward")
                }
                .help("Сразу вставить")
                .buttonStyle(.borderless)

                Button("Выбрать") {
                    onCopy()
                }
                .buttonStyle(.borderedProminent)

                Button("Удалить") {
                    onDelete()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onSelect()
        }
    }
}

private struct ScreenshotClipboardRow: View {
    let item: ClipboardImageItem
    let image: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onInstantPaste: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 110, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text("Снимок экрана")
                    .font(.headline)

                Text("\(Int(item.pixelWidth)) x \(Int(item.pixelHeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        onInstantPaste()
                    } label: {
                        Image(systemName: "arrowshape.turn.up.forward")
                    }
                    .help("Сразу вставить")
                    .buttonStyle(.borderless)

                    Button("Выбрать") {
                        onCopy()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Удалить") {
                        onDelete()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onSelect()
        }
    }
}
