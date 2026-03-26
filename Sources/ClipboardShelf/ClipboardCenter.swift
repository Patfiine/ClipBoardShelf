import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import SwiftUI

@MainActor
final class ClipboardCenter: NSObject, ObservableObject {
    private enum PastePayload {
        case text(String)
        case pasteboard
    }

    static let shared = ClipboardCenter()

    @Published private(set) var textItems: [ClipboardItem] = []
    @Published private(set) var imageItems: [ClipboardImageItem] = []
    @Published var selectedTab: ClipboardTab = .text
    @Published var selectedTextID: UUID?
    @Published var selectedImageID: UUID?
    @Published private(set) var lastPasteTargetName = "Не выбрано"
    @Published private(set) var lastPasteStatus = "Ожидание"

    let maxTextItems = 50
    let maxImageItems = 20

    private let pasteboard = NSPasteboard.general
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let screenshotNameMarkers = [
        "screen shot",
        "screenshot",
        "снимок экрана",
        "снимок",
    ]

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let popover = NSPopover()
    private var hotKeyManager: HotKeyManager?
    private var monitorTimer: Timer?
    private var lastChangeCount: Int
    private var isInternalCopy = false
    private var previousActiveApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var workspaceActivationObserver: Any?
    private var lastDesktopScreenshotScanDate: Date
    private var importedScreenshotSignatures = Set<String>()

    private override init() {
        self.lastChangeCount = pasteboard.changeCount
        self.lastDesktopScreenshotScanDate = .now.addingTimeInterval(-2)
        super.init()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        load()
        importedScreenshotSignatures = Set(imageItems.compactMap(\.sourceSignature))
    }

    func configureApplication() {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureHotKey()
        startTrackingActiveApplication()
        startMonitoringPasteboard()
    }

    func configureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "ClipboardShelf"
        )
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.action = #selector(togglePopoverFromStatusItem)
        item.button?.target = self
        statusItem = item
        configureStatusMenu()
    }

    func copyText(_ item: ClipboardItem) {
        isInternalCopy = true
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        addText(item.text)
    }

    func pasteTextImmediately(_ item: ClipboardItem) {
        copyText(item)
        pasteIntoPreviousAppIfPossible(payload: .text(item.text))
    }

    func copyImage(_ item: ClipboardImageItem) {
        guard let image = image(for: item) else {
            return
        }

        isInternalCopy = true
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        promoteImage(item)
    }

    func pasteImageImmediately(_ item: ClipboardImageItem) {
        copyImage(item)
        pasteIntoPreviousAppIfPossible(payload: .pasteboard)
    }

    func removeText(_ item: ClipboardItem) {
        textItems.removeAll { $0.id == item.id }
        ensureSelection()
        saveTexts()
    }

    func removeImage(_ item: ClipboardImageItem) {
        imageItems.removeAll { $0.id == item.id }
        if let sourceSignature = item.sourceSignature {
            importedScreenshotSignatures.remove(sourceSignature)
        }
        deleteImageFileIfNeeded(named: item.fileName)
        ensureSelection()
        saveImages()
    }

    func clearCurrentTab() {
        switch selectedTab {
        case .text:
            textItems.removeAll()
            selectedTextID = nil
            saveTexts()
        case .screenshots:
            imageItems.compactMap(\.sourceSignature).forEach { importedScreenshotSignatures.remove($0) }
            imageItems.forEach { deleteImageFileIfNeeded(named: $0.fileName) }
            imageItems.removeAll()
            selectedImageID = nil
            saveImages()
        }
    }

    func selectText(_ item: ClipboardItem) {
        selectedTextID = item.id
        selectedTab = .text
    }

    func selectImage(_ item: ClipboardImageItem) {
        selectedImageID = item.id
        selectedTab = .screenshots
    }

    func moveSelection(by delta: Int) {
        switch selectedTab {
        case .text:
            guard !textItems.isEmpty else {
                selectedTextID = nil
                return
            }

            let currentIndex = textItems.firstIndex { $0.id == selectedTextID } ?? 0
            let nextIndex = max(0, min(textItems.count - 1, currentIndex + delta))
            selectedTextID = textItems[nextIndex].id
        case .screenshots:
            guard !imageItems.isEmpty else {
                selectedImageID = nil
                return
            }

            let currentIndex = imageItems.firstIndex { $0.id == selectedImageID } ?? 0
            let nextIndex = max(0, min(imageItems.count - 1, currentIndex + delta))
            selectedImageID = imageItems[nextIndex].id
        }
    }

    func switchTab(by delta: Int) {
        let tabs = ClipboardTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab) else {
            return
        }

        let nextIndex = max(0, min(tabs.count - 1, currentIndex + delta))
        selectedTab = tabs[nextIndex]
        ensureSelection()
    }

    func pasteSelectedImmediately() {
        switch selectedTab {
        case .text:
            guard let item = selectedTextItem else { return }
            pasteTextImmediately(item)
        case .screenshots:
            guard let item = selectedImageItem else { return }
            pasteImageImmediately(item)
        }
    }

    func copySelected() {
        switch selectedTab {
        case .text:
            guard let item = selectedTextItem else { return }
            copyText(item)
        case .screenshots:
            guard let item = selectedImageItem else { return }
            copyImage(item)
        }
    }

    func image(for item: ClipboardImageItem) -> NSImage? {
        guard let url = imageFileURL(for: item.fileName) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    func isSelected(textItem: ClipboardItem) -> Bool {
        selectedTab == .text && selectedTextID == textItem.id
    }

    func isSelected(imageItem: ClipboardImageItem) -> Bool {
        selectedTab == .screenshots && selectedImageID == imageItem.id
    }

    var selectedTextItem: ClipboardItem? {
        textItems.first { $0.id == selectedTextID }
    }

    var selectedImageItem: ClipboardImageItem? {
        imageItems.first { $0.id == selectedImageID }
    }

    var currentShortcutSummary: String {
        "Открыть: Command+Shift+Space, навигация: Command+стрелки, мгновенная вставка: Command+Return"
    }

    @objc
    func togglePopoverFromStatusItem() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        togglePopover()
    }

    func togglePopover() {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 430, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardMenuView(center: self)
        )
    }

    private func configureStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(
            withTitle: "Открыть",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        statusMenu.addItem(
            withTitle: "Настройки",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Выход",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        statusMenu.items.forEach { item in
            item.target = self
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        previousActiveApplication = currentTargetApplication()
        ensureSelection()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showStatusMenu() {
        closePopover()
        guard let button = statusItem?.button else {
            return
        }

        statusItem?.menu = statusMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc
    private func openFromMenu() {
        togglePopover()
    }

    @objc
    private func openSettingsFromMenu() {
        openSettings()
    }

    @objc
    private func quitFromMenu() {
        quitApplication()
    }

    private func configureHotKey() {
        hotKeyManager = HotKeyManager(
            identifier: 1,
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover()
            }
        }
    }

    private func startTrackingActiveApplication() {
        guard workspaceActivationObserver == nil else {
            return
        }

        updateLastExternalApplication(from: NSWorkspace.shared.frontmostApplication)

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.updateLastExternalApplication(from: application)
            }
        }
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard popover.isShown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)

        guard hasCommand else {
            return false
        }

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            moveSelection(by: -1)
            return true
        case kVK_DownArrow:
            moveSelection(by: 1)
            return true
        case kVK_LeftArrow:
            switchTab(by: -1)
            return true
        case kVK_RightArrow:
            switchTab(by: 1)
            return true
        case kVK_Return where !hasShift:
            pasteSelectedImmediately()
            return true
        case kVK_ANSI_V where hasShift:
            pasteSelectedImmediately()
            return true
        case kVK_ANSI_C:
            copySelected()
            return true
        default:
            return false
        }
    }

    private func startMonitoringPasteboard() {
        guard monitorTimer == nil else {
            return
        }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollSources()
            }
        }
    }

    private func pollSources() {
        pollPasteboard()
        pollDesktopScreenshots()
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        if isInternalCopy {
            isInternalCopy = false
            return
        }

        if let copiedText = pasteboard.string(forType: .string) {
            addText(copiedText)
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            addImage(image)
        }
    }

    private func pollDesktopScreenshots() {
        guard let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return
        }

        let previousScanDate = lastDesktopScreenshotScanDate
        lastDesktopScreenshotScanDate = .now

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let candidates = fileURLs
            .filter { isScreenshotFileCandidate($0) }
            .sorted { lhs, rhs in
                screenshotDate(for: lhs) < screenshotDate(for: rhs)
            }

        for fileURL in candidates {
            guard screenshotDate(for: fileURL) >= previousScanDate else {
                continue
            }

            let signature = screenshotSignature(for: fileURL)
            guard !importedScreenshotSignatures.contains(signature),
                  let image = NSImage(contentsOf: fileURL) else {
                continue
            }

            addImage(image, sourceSignature: signature)
        }
    }

    private func addText(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            return
        }

        textItems.removeAll { $0.text == normalizedText }
        textItems.insert(ClipboardItem(text: normalizedText), at: 0)

        if textItems.count > maxTextItems {
            textItems = Array(textItems.prefix(maxTextItems))
        }

        if selectedTab == .text || selectedTextID == nil {
            selectedTextID = textItems.first?.id
        }

        saveTexts()
    }

    private func addImage(_ image: NSImage, sourceSignature: String? = nil) {
        guard let pngData = image.pngData(),
              let directoryURL = imagesDirectoryURL() else {
            return
        }

        if let sourceSignature, importedScreenshotSignatures.contains(sourceSignature) {
            return
        }

        let item = ClipboardImageItem(
            fileName: "\(UUID().uuidString).png",
            pixelWidth: image.size.width,
            pixelHeight: image.size.height,
            sourceSignature: sourceSignature
        )

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try pngData.write(to: directoryURL.appendingPathComponent(item.fileName), options: .atomic)
        } catch {
            assertionFailure("Failed to save image clipboard item: \(error)")
            return
        }

        imageItems.insert(item, at: 0)

        if imageItems.count > maxImageItems, let removed = imageItems.popLast() {
            deleteImageFileIfNeeded(named: removed.fileName)
        }

        if selectedTab == .screenshots || selectedImageID == nil {
            selectedImageID = imageItems.first?.id
        }

        if let sourceSignature {
            importedScreenshotSignatures.insert(sourceSignature)
        }

        saveImages()
    }

    private func promoteImage(_ item: ClipboardImageItem) {
        imageItems.removeAll { $0.id == item.id }
        imageItems.insert(item, at: 0)
        selectedImageID = item.id
        saveImages()
    }

    private func pasteIntoPreviousAppIfPossible(payload: PastePayload) {
        guard AXIsProcessTrusted() else {
            lastPasteStatus = "Нет доступа Accessibility"
            closePopover()
            return
        }

        guard let targetApplication = currentTargetApplication() else {
            lastPasteStatus = "Не найдено приложение для вставки"
            closePopover()
            return
        }

        lastPasteTargetName = targetApplication.localizedName ?? targetApplication.bundleIdentifier ?? "Неизвестно"

        if case let .text(text) = payload,
           insertTextViaAccessibility(text, pid: targetApplication.processIdentifier) {
            lastPasteStatus = "Текст вставлен через Accessibility"
            closePopover()
            return
        }

        lastPasteStatus = "Возвращаю фокус в \(lastPasteTargetName)"
        closePopover()
        targetApplication.activate(options: [.activateIgnoringOtherApps])
        NSApp.hide(nil)

        attemptPaste(
            into: targetApplication,
            payload: payload,
            remainingAttempts: 5,
            delay: 0.18
        )
    }

    private func load() {
        loadTexts()
        loadImages()
        ensureSelection()
    }

    private func loadTexts() {
        guard let fileURL = textStorageFileURL(),
              fileManager.fileExists(atPath: fileURL.path) else {
            migrateLegacyTextHistoryIfNeeded()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            textItems = try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            textItems = []
        }
    }

    private func loadImages() {
        guard let fileURL = imageStorageFileURL(),
              fileManager.fileExists(atPath: fileURL.path) else {
            imageItems = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            imageItems = try decoder.decode([ClipboardImageItem].self, from: data)
        } catch {
            imageItems = []
        }
    }

    private func migrateLegacyTextHistoryIfNeeded() {
        guard let fileURL = legacyTextStorageFileURL(),
              fileManager.fileExists(atPath: fileURL.path) else {
            textItems = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            textItems = try decoder.decode([ClipboardItem].self, from: data)
            saveTexts()
        } catch {
            textItems = []
        }
    }

    private func saveTexts() {
        guard let fileURL = textStorageFileURL() else {
            return
        }

        do {
            try ensureStorageDirectoryExists()
            let data = try encoder.encode(textItems)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save text history: \(error)")
        }
    }

    private func saveImages() {
        guard let fileURL = imageStorageFileURL() else {
            return
        }

        do {
            try ensureStorageDirectoryExists()
            let data = try encoder.encode(imageItems)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save image history: \(error)")
        }
    }

    private func ensureSelection() {
        if selectedTextID == nil || !textItems.contains(where: { $0.id == selectedTextID }) {
            selectedTextID = textItems.first?.id
        }

        if selectedImageID == nil || !imageItems.contains(where: { $0.id == selectedImageID }) {
            selectedImageID = imageItems.first?.id
        }

        switch selectedTab {
        case .text where textItems.isEmpty && !imageItems.isEmpty:
            selectedTab = .screenshots
        case .screenshots where imageItems.isEmpty && !textItems.isEmpty:
            selectedTab = .text
        default:
            break
        }
    }

    private func ensureStorageDirectoryExists() throws {
        guard let directoryURL = storageDirectoryURL() else {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func storageDirectoryURL() -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClipboardShelf", isDirectory: true)
    }

    private func imagesDirectoryURL() -> URL? {
        storageDirectoryURL()?.appendingPathComponent("Images", isDirectory: true)
    }

    private func textStorageFileURL() -> URL? {
        storageDirectoryURL()?.appendingPathComponent("text-history.json")
    }

    private func imageStorageFileURL() -> URL? {
        storageDirectoryURL()?.appendingPathComponent("image-history.json")
    }

    private func legacyTextStorageFileURL() -> URL? {
        storageDirectoryURL()?.appendingPathComponent("history.json")
    }

    private func imageFileURL(for fileName: String) -> URL? {
        imagesDirectoryURL()?.appendingPathComponent(fileName)
    }

    private func deleteImageFileIfNeeded(named fileName: String) {
        guard let fileURL = imageFileURL(for: fileName),
              fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
    }

    private func isScreenshotFileCandidate(_ fileURL: URL) -> Bool {
        let fileName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        let fileExtension = fileURL.pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg"].contains(fileExtension)
        let isScreenshotName = screenshotNameMarkers.contains { fileName.contains($0) }
        return isImage && isScreenshotName
    }

    private func screenshotDate(for fileURL: URL) -> Date {
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private func screenshotSignature(for fileURL: URL) -> String {
        let date = screenshotDate(for: fileURL).ISO8601Format()
        return "\(fileURL.lastPathComponent.lowercased())::\(date)"
    }

    private func updateLastExternalApplication(from application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        lastExternalApplication = application
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        if let previousActiveApplication,
           previousActiveApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
               frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return frontmostApplication
            }
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            return frontmostApplication
        }

        if let lastExternalApplication, isUsableTargetApplication(lastExternalApplication) {
            return lastExternalApplication
        }

        if let previousActiveApplication, isUsableTargetApplication(previousActiveApplication) {
            return previousActiveApplication
        }

        return lastExternalApplication
    }

    private func attemptPaste(
        into application: NSRunningApplication,
        payload: PastePayload,
        remainingAttempts: Int,
        delay: TimeInterval
    ) {
        guard remainingAttempts > 0 else {
            lastPasteStatus = "Не удалось вернуть фокус"
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }

            let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let targetHasFocusedElement = self.hasFocusedElement(for: application.processIdentifier)

            if frontmostProcessIdentifier != application.processIdentifier && !targetHasFocusedElement {
                application.activate(options: [.activateIgnoringOtherApps])
                self.attemptPaste(
                    into: application,
                    payload: payload,
                    remainingAttempts: remainingAttempts - 1,
                    delay: delay
                )
                return
            }

            self.performPaste(payload: payload, targetApplication: application)
        }
    }

    private func performPaste(payload: PastePayload, targetApplication: NSRunningApplication) {
        switch payload {
        case .text(let text):
            if insertTextViaAccessibility(text, pid: targetApplication.processIdentifier) {
                lastPasteStatus = "Текст вставлен через Accessibility"
                return
            }

            if triggerPasteMenuAction(pid: targetApplication.processIdentifier) {
                lastPasteStatus = "Вставка выполнена через меню приложения"
                return
            }

            lastPasteStatus = "AX-вставка не сработала, отправляю Cmd+V"
            sendPasteShortcut()
        case .pasteboard:
            if triggerPasteMenuAction(pid: targetApplication.processIdentifier) {
                lastPasteStatus = "Вставка выполнена через меню приложения"
                return
            }

            lastPasteStatus = "Отправляю Cmd+V"
            sendPasteShortcut()
        }
    }

    private func sendPasteShortcut() {
        lastPasteStatus = "Отправляю Cmd+V"
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandKeyCode: CGKeyCode = 0x37
        let vKeyCode: CGKeyCode = 0x09

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
        lastPasteStatus = "Команда Cmd+V отправлена"
    }

    private func insertTextViaAccessibility(_ text: String, pid: pid_t) -> Bool {
        let applicationElement = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?

        let focusedResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedResult == .success,
              let focusedElement else {
            return false
        }

        let uiElement = focusedElement as! AXUIElement
        let originalValue = accessibilityStringValue(for: uiElement)
        let cfText = text as CFString

        let selectedTextResult = AXUIElementSetAttributeValue(
            uiElement,
            kAXSelectedTextAttribute as CFString,
            cfText
        )

        if selectedTextResult == .success {
            let newValue = accessibilityStringValue(for: uiElement)
            let newSelectedText = accessibilitySelectedText(for: uiElement)

            if newValue != originalValue || newSelectedText == text {
                return true
            }
        }

        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            uiElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard valueResult == .success,
              let currentString = currentValue as? String else {
            return false
        }

        let newValue = currentString + text
        let setValueResult = AXUIElementSetAttributeValue(
            uiElement,
            kAXValueAttribute as CFString,
            newValue as CFString
        )

        guard setValueResult == .success else {
            return false
        }

        return accessibilityStringValue(for: uiElement) == newValue
    }

    private func hasFocusedElement(for pid: pid_t) -> Bool {
        let applicationElement = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        return result == .success && focusedElement != nil
    }

    private func isUsableTargetApplication(_ application: NSRunningApplication) -> Bool {
        !application.isTerminated &&
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
        application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    private func accessibilityStringValue(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func accessibilitySelectedText(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func triggerPasteMenuAction(pid: pid_t) -> Bool {
        let applicationElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?

        let menuBarResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        )

        guard menuBarResult == .success,
              let menuBarRef else {
            return false
        }

        let menuBar = menuBarRef as! AXUIElement
        guard let menuBarItems = accessibilityChildren(of: menuBar) else {
            return false
        }

        let editTitles = ["Edit", "Правка"]
        let pasteTitles = ["Paste", "Вставить"]

        guard let editMenuItem = menuBarItems.first(where: { element in
            guard let title = accessibilityTitle(of: element) else {
                return false
            }

            return editTitles.contains(title)
        }) else {
            return false
        }

        let openMenuResult = AXUIElementPerformAction(editMenuItem, kAXPressAction as CFString)
        guard openMenuResult == .success else {
            return false
        }

        usleep(120_000)

        guard let editMenu = accessibilityMenu(of: editMenuItem),
              let menuItems = accessibilityChildren(of: editMenu),
              let pasteItem = menuItems.first(where: { element in
                  guard let title = accessibilityTitle(of: element) else {
                      return false
                  }

                  return pasteTitles.contains(title)
              }) else {
            return false
        }

        let pasteResult = AXUIElementPerformAction(pasteItem, kAXPressAction as CFString)
        return pasteResult == .success
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func accessibilityTitle(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func accessibilityMenu(of element: AXUIElement) -> AXUIElement? {
        guard let children = accessibilityChildren(of: element) else {
            return nil
        }

        return children.first
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
