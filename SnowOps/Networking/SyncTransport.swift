import Foundation
import SnowOpsCore

/// Production boundary: the server must validate organization, permissions, versions and idempotency.
/// Not connected in the development app; local changes are always explicitly pending.
protocol SyncTransport: Sendable {
    func upload(_ event: AuditEvent, token: String) async throws
}
struct HTTPSyncTransport: SyncTransport {
    let endpoint: URL
    private struct Receipt: Decodable { let mutationID: UUID; let committed: Bool }
    func upload(_ event: AuditEvent, token: String) async throws {
        guard endpoint.scheme == "https" else { throw DomainError.invalid("Sync requires HTTPS.") }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/mutations"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(event.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DomainError.invalid("Server did not acknowledge the change. It remains saved on this device.")
        }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.committed && receipt.mutationID == event.id else { throw DomainError.invalid("The server receipt does not match this change.") }
    }
}
