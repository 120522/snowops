import Foundation

public enum BillingExport {
    public static func csv(_ state: Workspace, stormID: UUID? = nil) -> String {
        let headers = ["Customer", "Property", "Storm", "Service Date", "Service Description", "Quantity", "Rate", "Calculated", "Final Amount", "Notes", "Status"]
        var rows = [headers]
        for record in state.billing where stormID == nil || record.stormID == stormID {
            guard let property = state.properties.first(where: { $0.id == record.propertyID }),
                  let customer = state.customers.first(where: { $0.id == property.customerID }),
                  let storm = state.storms.first(where: { $0.id == record.stormID }) else { continue }
            let visits = state.visits.filter { $0.stormID == record.stormID && $0.propertyID == record.propertyID && !$0.canceled && $0.departure != nil }
            let description = Set(visits.flatMap(\.services).filter(\.performed).map { $0.configuration.name }).sorted().joined(separator: "; ")
            rows.append([customer.name, property.name, storm.name, ISO8601DateFormatter().string(from: storm.start), description,
                         "1", "\(record.final)", "\(record.calculated)", "\(record.final)", record.reason,
                         record.entered ? "Entered" : record.needsReview || storm.status != .finalized ? "Needs Review" : "Ready"])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    public static func escape(_ value: String) -> String {
        // Prevent spreadsheet formula evaluation of customer-supplied names/notes.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) || trimmed.hasPrefix($0) }) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
