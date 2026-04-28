import AppKit
import SwiftUI

struct ClipboardMenuView: View {
    @ObservedObject var center: ClipboardCenter
    private let calendar = Calendar.current

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
        Picker("Вкладка", selection: tabSelectionBinding) {
            ForEach(ClipboardTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tabSelectionBinding: Binding<ClipboardTab> {
        Binding(
            get: { center.selectedTab },
            set: { newValue in
                DispatchQueue.main.async {
                    center.setSelectedTab(newValue)
                }
            }
        )
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
                        LazyVStack(spacing: 14) {
                            ForEach(textRows) { row in
                                switch row {
                                case .header(let id, let title):
                                    sectionHeader(title: title)
                                        .id(id)
                                case .item(let item, let tint):
                                    TextClipboardRow(
                                        item: item,
                                        tint: tint,
                                        isSelected: center.isSelected(textItem: item),
                                        onSelect: { center.selectText(item) },
                                        onInstantPaste: { center.pasteTextImmediately(item) },
                                        onCopy: { center.copyText(item) },
                                        onDelete: { center.removeText(item) }
                                    )
                                    .id(item.id)
                                }
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
                    .onChange(of: center.selectedTab) { tab in
                        guard tab == .text else { return }
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
                        LazyVStack(spacing: 14) {
                            ForEach(imageRows) { row in
                                switch row {
                                case .header(let id, let title):
                                    sectionHeader(title: title)
                                        .id(id)
                                case .item(let item, let tint):
                                    ScreenshotClipboardRow(
                                        item: item,
                                        image: center.image(for: item),
                                        displayName: center.screenshotDisplayName(for: item),
                                        tint: tint,
                                        isSelected: center.isSelected(imageItem: item),
                                        onSelect: { center.selectImage(item) },
                                        onInstantPaste: { center.pasteImageImmediately(item) },
                                        onCopy: { center.copyImage(item) },
                                        onDelete: { center.removeImage(item) }
                                    )
                                    .id(item.id)
                                }
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
                    .onChange(of: center.selectedTab) { tab in
                        guard tab == .screenshots else { return }
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

    private var groupedTextItems: [HistorySection<ClipboardItem>] {
        makeSections(from: center.textItems)
    }

    private var groupedImageItems: [HistorySection<ClipboardImageItem>] {
        makeSections(from: center.imageItems)
    }

    private var textRows: [TextListRow] {
        groupedTextItems.flatMap { section in
            var rows: [TextListRow] = [
                .header(id: UUID(), title: title(for: section.day))
            ]
            rows.append(contentsOf: section.items.map { .item($0, tint: section.tint) })
            return rows
        }
    }

    private var imageRows: [ImageListRow] {
        groupedImageItems.flatMap { section in
            var rows: [ImageListRow] = [
                .header(id: UUID(), title: title(for: section.day))
            ]
            rows.append(contentsOf: section.items.map { .item($0, tint: section.tint) })
            return rows
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

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private func scrollToSelectedText(with proxy: ScrollViewProxy) {
        guard let id = center.selectedTextID else {
            return
        }

        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func scrollToSelectedImage(with proxy: ScrollViewProxy) {
        guard let id = center.selectedImageID else {
            return
        }

        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func makeSections<Item: Identifiable>(from items: [Item]) -> [HistorySection<Item>] where Item: DatedClipboardItem {
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        let sortedDays = grouped.keys.sorted(by: >)
        let tints: [Color] = [
            Color.accentColor.opacity(0.09),
            Color.cyan.opacity(0.12),
            Color.yellow.opacity(0.12),
            Color.indigo.opacity(0.09),
            Color.mint.opacity(0.09),
            Color.pink.opacity(0.09),
            Color.green.opacity(0.09),
            Color.purple.opacity(0.09),
            
            
            
        ]

        return sortedDays.enumerated().compactMap { index, day in
            guard let sectionItems = grouped[day] else {
                return nil
            }

            return HistorySection(
                day: day,
                tint: tints[index % tints.count],
                items: sectionItems.sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private func title(for day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Сегодня"
        }

        if calendar.isDateInYesterday(day) {
            return "Вчера"
        }

        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private protocol DatedClipboardItem {
    var createdAt: Date { get }
}

extension ClipboardItem: DatedClipboardItem {}
extension ClipboardImageItem: DatedClipboardItem {}

private struct HistorySection<Item: Identifiable>: Identifiable {
    let day: Date
    let tint: Color
    let items: [Item]

    var id: Date { day }
}

private struct TextClipboardRow: View {
    let item: ClipboardItem
    let tint: Color
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
        .background(isSelected ? Color.accentColor.opacity(0.16) : tint)
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
    let displayName: String
    let tint: Color
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
                Text(displayName)
                    .font(.headline)
                    .lineLimit(2)

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
        .background(isSelected ? Color.accentColor.opacity(0.16) : tint)
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

private enum TextListRow: Identifiable {
    case header(id: UUID, title: String)
    case item(ClipboardItem, tint: Color)

    var id: UUID {
        switch self {
        case .header(let id, _):
            return id
        case .item(let item, _):
            return item.id
        }
    }
}

private enum ImageListRow: Identifiable {
    case header(id: UUID, title: String)
    case item(ClipboardImageItem, tint: Color)

    var id: UUID {
        switch self {
        case .header(let id, _):
            return id
        case .item(let item, _):
            return item.id
        }
    }
}
