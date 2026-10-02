import SwiftUI
import SnowOpsCore

struct StormReviewView: View {
    @Environment(OperationsStore.self) private var store
    let stormID: UUID
    @State private var finalSnow: Decimal = 0
    @State private var adjustment: BillingRecord?
    @State private var finalize = false
    @State private var feedback = 0
    var body: some View {
        if let storm = store.storm(stormID) {
            let records = store.state.billing.filter { $0.stormID == stormID }
            List {
                Section("Verified snowfall") {
                    LabeledContent("Forecast", value: "\(storm.forecastLow)–\(storm.forecastHigh)″")
                    LabeledContent("Original operational estimate", value: storm.operationalSnowfall.inches)
                    if storm.status != .finalized {
                        TextField("Final verified inches", value: $finalSnow, format: .number).keyboardType(.decimalPad)
                        Button("Verify snowfall & recalculate") { _ = store.recalculate(stormID: stormID, snowfall: finalSnow) }
                        Text("Recalculation preserves every manual override and flags changed calculations for another review.").font(.footnote).foregroundStyle(.secondary)
                    } else { LabeledContent("Final snowfall", value: storm.finalSnowfall?.inches ?? "Not verified") }
                }
                Section("Property billing") {
                    if records.isEmpty { Text("Verify snowfall to calculate completed services.").foregroundStyle(.secondary) }
                    ForEach(records) { record in
                        Button { adjustment = record } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.property(record.propertyID)?.name ?? "Property").font(.headline).foregroundStyle(.primary)
                                Text("\(store.visits(stormID: stormID, propertyID: record.propertyID).filter { $0.departure != nil && !$0.canceled }.count) visits").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    VStack(alignment: .leading) { Text("Calculated").font(.caption); Text(record.calculated.currency).font(.headline) }
                                    Spacer()
                                    VStack(alignment: .trailing) { Text("Final billable").font(.caption); Text(record.final.currency).font(.headline) }
                                }.foregroundStyle(.primary)
                                Label(record.needsReview ? "Needs review" : "Reviewed", systemImage: record.needsReview ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(record.needsReview ? .orange : .green)
                                if record.override != nil { Text("Manual adjustment preserved").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                }
                if storm.status != .finalized {
                    let problems = Validation.finalizationProblems(store.state, storm: storm)
                    Section("Before finalization") {
                        if problems.isEmpty { Label("Everything is ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                        ForEach(problems, id: \.self) { Label($0, systemImage: "circle").foregroundStyle(.secondary) }
                    }
                    if store.actor.allows(.finalizeStorm) { Section { PrimaryAction(title: "Finalize storm", symbol: "checkmark.seal", disabled: !problems.isEmpty) { finalize = true } } }
                } else { Section { Label("Finalized · records locked", systemImage: "lock.fill"); NavigationLink("View final summary", destination: StormSummaryView(stormID: stormID)) } }
            }.navigationTitle("Storm review")
                .onAppear { finalSnow = storm.finalSnowfall ?? storm.operationalSnowfall }
                .sheet(item: $adjustment) { BillingAdjustmentView(record: $0) }
                .confirmationDialog("Finalize this storm?", isPresented: $finalize, titleVisibility: .visible) { Button("Finalize & lock records") { if store.setStatus(stormID: stormID, status: .finalized) { feedback += 1 } } } message: { Text("Service and billing records will become read-only.") }
                .sensoryFeedback(.success, trigger: feedback)
        }
    }
}
struct BillingAdjustmentView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: BillingRecord
    @State private var useOverride: Bool
    @State private var amount: Decimal
    @State private var reason: String
    @State private var discard = false
    init(record: BillingRecord) {
        self.record = record; _useOverride = State(initialValue: record.override != nil); _amount = State(initialValue: record.final); _reason = State(initialValue: record.reason)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(store.property(record.propertyID)?.name ?? "Property").font(.headline); LabeledContent("Calculated", value: record.calculated.currency) }
                Section("Calculation breakdown") {
                    let snowfall = store.storm(record.stormID)?.finalSnowfall ?? 0
                    if let lines = try? PricingEngine.lines(visits: store.visits(stormID: record.stormID, propertyID: record.propertyID), snowfall: snowfall) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            VStack(alignment: .leading, spacing: 5) { LabeledContent(line.service, value: line.amount.currency); Text("\(line.quantity) × \(line.rate.currency) · \(line.explanation)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if store.storm(record.stormID)?.status != .finalized {
                    Section("Administrative review") {
                        Toggle("Override calculated amount", isOn: $useOverride)
                        if useOverride { TextField("Final billable amount", value: $amount, format: .number).keyboardType(.decimalPad); TextField("Adjustment reason", text: $reason, axis: .vertical) }
                        PrimaryAction(title: "Save & mark reviewed", symbol: "checkmark") { if store.reviewBilling(record, override: useOverride ? amount : nil, reason: useOverride ? reason : "Calculation accepted") { dismiss() } }
                    }
                } else { Section { LabeledContent("Final amount", value: record.final.currency); if !record.reason.isEmpty { Text(record.reason) }; Label("Finalized record", systemImage: "lock") } }
            }.navigationTitle("Billing detail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if useOverride != (record.override != nil) || amount != record.final || reason != record.reason { discard = true } else { dismiss() } } } }
                .interactiveDismissDisabled()
                .confirmationDialog("Discard adjustment changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }.presentationDetents([.large])
    }
}
struct StormSummaryView: View {
    @Environment(OperationsStore.self) private var store
    let stormID: UUID
    var body: some View {
        if let storm = store.storm(stormID) {
            let visits = store.visits(stormID: stormID).filter { $0.departure != nil && !$0.canceled }
            let records = store.state.billing.filter { $0.stormID == stormID }
            let calculated = records.reduce(Decimal(0)) { $0 + $1.calculated }
            let final = records.reduce(Decimal(0)) { $0 + $1.final }
            List {
                Section { Text(storm.name).font(.headline); Text(storm.start, style: .date); LabeledContent("Status", value: storm.status.title); LabeledContent("Final snowfall", value: storm.finalSnowfall?.inches ?? "Not verified") }
                Section("Work performed") {
                    LabeledContent("Properties serviced", value: "\(Set(visits.map(\.propertyID)).count)")
                    LabeledContent("Total visits", value: "\(visits.count)")
                    LabeledContent("Plow visits", value: "\(visits.filter { $0.services.contains { $0.performed && $0.configuration.name.localizedCaseInsensitiveContains("plow") } }.count)")
                    LabeledContent("Salt applications", value: "\(visits.flatMap(\.services).filter { $0.performed && $0.configuration.name.localizedCaseInsensitiveContains("salt") }.count)")
                    LabeledContent("Sidewalk services", value: "\(visits.flatMap(\.services).filter { $0.performed && $0.configuration.name.localizedCaseInsensitiveContains("sidewalk") }.count)")
                    LabeledContent("Crew hours", value: "\(PricingEngine.money(visits.reduce(Decimal(0)) { $0 + $1.hours }))")
                }
                Section("Materials") {
                    let materials = Dictionary(grouping: visits.flatMap(\.materials), by: { "\($0.name) (\($0.unit))" })
                    ForEach(materials.keys.sorted(), id: \.self) { key in LabeledContent(key, value: "\(materials[key]!.reduce(Decimal(0)) { $0 + $1.quantity })") }
                }
                Section("Billing") {
                    LabeledContent("Calculated revenue", value: calculated.currency)
                    LabeledContent("Adjustments", value: (final - calculated).currency)
                    LabeledContent("Final billable revenue", value: final.currency).font(.headline)
                    LabeledContent("Outstanding issues", value: "\(store.state.issues.filter { $0.stormID == stormID && !$0.resolved }.count)")
                    NavigationLink("Prepare billing export", destination: InvoicePrepView(stormID: stormID))
                }
            }.navigationTitle("Storm summary")
        }
    }
}
