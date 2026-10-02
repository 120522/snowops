import Foundation
import SnowOpsCore

struct PendingMutation: Identifiable, Codable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var auditID: UUID
}
struct LocalEnvelope: Codable {
    var workspace: Workspace
    var outbox: [PendingMutation] = []
}

/// One atomic file commits domain changes, audit history and the outbox together.
/// A failed write never updates the observable workspace. No network operation owns local data.
struct LocalRepository {
    let directory: URL
    var file: URL { directory.appendingPathComponent("workspace-v1.json") }
    init() throws {
        directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SnowOps", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    init(directory: URL) { self.directory = directory }
    func load() throws -> LocalEnvelope? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let envelope = try JSONDecoder().decode(LocalEnvelope.self, from: Data(contentsOf: file))
        guard envelope.workspace.schemaVersion == 1 else { throw DomainError.invalid("This data requires a newer version of Snow Ops. The original file has been preserved.") }
        return envelope
    }
    func save(_ envelope: LocalEnvelope) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func storePhoto(_ data: Data) throws -> PhotoRecord {
        let relative = "photos/\(UUID().uuidString).jpg"
        let folder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(relative), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return PhotoRecord(relativePath: relative)
    }
}
