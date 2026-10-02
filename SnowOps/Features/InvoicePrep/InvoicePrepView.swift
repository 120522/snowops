import SwiftUI
import SnowOpsCore

private enum PrepFilter: String, CaseIterable { case ready = "Ready", review = "Needs review", entered = "Entered", all = "All" }
struct InvoicePrepView: View {
    @Environment(OperationsStore.self) private var store
    var stormID: UUID?
    @State private var filter: PrepFilter = .all
    @State private var exportURL: URL?
    @State private var copied = false
    var body: some View {
        let records = store.state.billing.filter { record in
            guard stormID == nil || record.stormID == stormID else { return false }
            let ready = !record.needsReview && store.storm(record.stormID)?.status == .finalized
            switch filter { case .all: return true; case .ready: return ready && !record.entered; case .review: return !ready; case .entered: return record.entered }
        }
        List {
            Section { Picker("Show", selection: $filter) { ForEach(PrepFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Text("Transfer reviewed totals into your existing invoicing system. Each export row summarizes a property’s storm services with quantity 1; visit-level rate breakdowns are in storm review.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                if let property = store.property(record.propertyID) {
                    Section {
                        Text(store.customer(property.customerID)?.name ?? "Customer").font(.headline)
                        Text(property.name)
                        Text(store.storm(record.stormID)?.name ?? "Storm").foregroundStyle(.secondary)
                        LabeledContent("Quantity", value: "1 property storm summary")
                        LabeledContent("Rate / amount", value: record.final.currency)
                        if !record.reason.isEmpty { Text(record.reason).font(.subheadline).foregroundStyle(.secondary) }
                        if record.entered { Label("Entered in external system", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if !record.needsReview && store.storm(record.stormID)?.status == .finalized { Button("Mark as entered") { store.markEntered(record) }.frame(minHeight: 44) }
                        else { Label("Needs review / finalization", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    }
                }
            }
            if records.isEmpty { ContentUnavailableView("No matching billing records", systemImage: "doc.text", description: Text("Review a storm and verify snowfall to prepare service totals.")) }
            if let exportURL { Section("Export ready") { ShareLink(item: exportURL) { Label("Share export", systemImage: "square.and.arrow.up") } } }
        }.navigationTitle("Invoice prep")
            .toolbar { Menu("Export", systemImage: "square.and.arrow.up") {
                Button(copied ? "Copied" : "Copy CSV") { UIPasteboard.general.string = BillingExport.csv(exportState(records), stormID: stormID); copied = true }
                Button("Export CSV") { export(pdf: false, records: records) }
                Button("Export PDF") { export(pdf: true, records: records) }
            } }
    }
    private func exportState(_ records: [BillingRecord]) -> Workspace { var state = store.state; state.billing = records; return state }
    private func export(pdf: Bool, records: [BillingRecord]) {
        do { exportURL = try pdf ? ExportService.pdf(state: exportState(records), stormID: stormID) : ExportService.csv(state: exportState(records), stormID: stormID) }
        catch { store.error = error.localizedDescription }
    }
}
