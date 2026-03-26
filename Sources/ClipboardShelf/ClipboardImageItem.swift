import Foundation

struct ClipboardImageItem: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let pixelWidth: Double
    let pixelHeight: Double
    let sourceSignature: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        createdAt: Date = .now,
        pixelWidth: Double,
        pixelHeight: Double,
        sourceSignature: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceSignature = sourceSignature
    }
}
