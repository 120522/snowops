import UIKit
import SnowOpsCore

@MainActor enum ExportService {
    static func csv(state: Workspace, stormID: UUID?) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SnowOps-\(UUID().uuidString).csv")
        try BillingExport.csv(state, stormID: stormID).write(to: file, atomically: true, encoding: .utf8)
        return file
    }
    static func pdf(state: Workspace, stormID: UUID?) throws -> URL {
        let records = state.billing.filter { stormID == nil || $0.stormID == stormID }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SnowOps-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: file) { context in
            var y: CGFloat = 800
            func page() {
                context.beginPage(); y = 42
                ("Snow Ops · Billing preparation" as NSString).draw(at: CGPoint(x: 42, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                y += 32
                ("Service records for your existing invoicing system" as NSString).draw(at: CGPoint(x: 42, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                y += 34
            }
            for record in records {
                guard let property = state.properties.first(where: { $0.id == record.propertyID }), let storm = state.storms.first(where: { $0.id == record.stormID }) else { continue }
                let customer = state.customers.first { $0.id == property.customerID }?.name ?? "Customer"
                let text = "\(customer)\n\(property.name)\n\(storm.name) · \(storm.start.formatted(date: .abbreviated, time: .omitted))\nCalculated: \(record.calculated.currency)    Final: \(record.final.currency)\n\(record.reason)\n\(record.entered ? "Entered" : record.needsReview || storm.status != .finalized ? "Needs review" : "Ready")"
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
                let height = (text as NSString).boundingRect(with: CGSize(width: 528, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).height + 24
                if y + height > 750 { page() }
                (text as NSString).draw(in: CGRect(x: 42, y: y, width: 528, height: height), withAttributes: attributes)
                y += height
            }
            if records.isEmpty { page(); ("No reviewed billing records." as NSString).draw(at: CGPoint(x: 42, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]) }
        }
        return file
    }
}
