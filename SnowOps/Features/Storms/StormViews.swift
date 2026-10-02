import SwiftUI
import SnowOpsCore

struct StormListView: View {
    @Environment(OperationsStore.self) private var store
    @State private var query = ""
    @State private var create = false
    var body: some View {
        List {
            ForEach(store.state.storms.reversed().filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { storm in
                NavigationLink { StormDetailView(stormID: storm.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(storm.name, systemImage: "cloud.snow").font(.headline)
                        Text(storm.start, format: .dateTime.month().day().year()).font(.subheadline).foregroundStyle(.secondary)
                        Text(storm.status.title).font(.subheadline).foregroundStyle(storm.status == .active ? .blue : .secondary)
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("Storms").searchable(text: $query, prompt: "Search storms")
            .toolbar { if store.actor.allows(.dispatch) { Button("New storm", systemImage: "plus") { create = true } } }
            .sheet(isPresented: $create) { StormWizardView() }
    }
}
struct StormDetailView: View {
    @Environment(OperationsStore.self) private var store
    let stormID: UUID
    @State private var confirmStatus: StormStatus?
    var body: some View {
        if let storm = store.storm(stormID) {
            let assignments = store.route(stormID: stormID)
            let visits = store.visits(stormID: stormID).filter { !$0.canceled }
            List {
                Section {
                    LabeledContent("Status", value: storm.status.title)
                    LabeledContent("Forecast", value: "\(storm.forecastLow)–\(storm.forecastHigh)″")
                    LabeledContent("Operational estimate", value: storm.operationalSnowfall.inches)
                    if let snow = storm.finalSnowfall { LabeledContent("Verified snowfall", value: snow.inches) }
                    ProgressView(value: Double(assignments.filter { $0.status == .completed || $0.status == .skipped }.count), total: Double(max(1, assignments.count)))
                    HStack {
                        Metric(value: "\(assignments.filter { $0.status == .completed }.count)/\(assignments.count)", label: "Stops complete", symbol: "building.2")
                        Metric(value: "\(visits.filter { $0.departure != nil }.count)", label: "Visits", symbol: "checkmark.circle")
                    }
                }
                Section("Operations") {
                    NavigationLink("Dispatched properties", destination: DispatchView(stormID: stormID))
                    NavigationLink("Visit records", destination: HistoryView(stormID: stormID))
                    NavigationLink("Map", destination: OperationsMapView(stormID: stormID))
                }
                let issues = store.state.issues.filter { $0.stormID == stormID }
                if !issues.isEmpty { Section("Issues") { ForEach(issues) { IssueRow(issue: $0) } } }
                if store.actor.allows(.reviewBilling) {
                    Section("Post-storm") {
                        if storm.status == .underReview || storm.status == .finalized { NavigationLink("Storm review & billing", destination: StormReviewView(stormID: stormID)) }
                        NavigationLink("Storm summary", destination: StormSummaryView(stormID: stormID))
                        NavigationLink("Invoice preparation", destination: InvoicePrepView(stormID: stormID))
                    }
                }
                if store.actor.allows(.dispatch), storm.status != .finalized {
                    Section {
                        if storm.status == .preparing { Button("Activate storm") { confirmStatus = .active } }
                        if storm.status == .active { Button("Wrap up operations") { confirmStatus = .wrappingUp } }
                        if storm.status == .wrappingUp { Button("Move to storm review") { confirmStatus = .underReview } }
                    }
                }
            }.navigationTitle(storm.name)
                .confirmationDialog("Change storm status?", isPresented: Binding(get: { confirmStatus != nil }, set: { if !$0 { confirmStatus = nil } }), titleVisibility: .visible) {
                    if let status = confirmStatus { Button(status.title) { _ = store.setStatus(stormID: stormID, status: status); confirmStatus = nil } }
                } message: { Text("This change is recorded in the audit history.") }
        }
    }
}

struct StormWizardView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Storm(name: "")
    @State private var step = 0
    @State private var selected: Set<UUID> = []
    @State private var crews: [UUID: UUID] = [:]
    @State private var activate = true
    @State private var discard = false
    private let steps = ["Storm information", "Expected snowfall", "Select properties", "Service triggers", "Assign crews", "Review dispatch", "Activate storm"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Step \(step + 1) of 7").font(.caption).foregroundStyle(.secondary)
                    Text(steps[step]).font(.title2.bold())
                    ProgressView(value: Double(step + 1), total: 7)
                }
                switch step {
                case 0:
                    Section { TextField("Storm name", text: $draft.name); DatePicker("Start", selection: $draft.start); TextField("Weather notes", text: $draft.notes, axis: .vertical) }
                case 1:
                    Section("Inches") {
                        TextField("Forecast low", value: $draft.forecastLow, format: .number).keyboardType(.decimalPad)
                        TextField("Forecast high", value: $draft.forecastHigh, format: .number).keyboardType(.decimalPad)
                        TextField("Operational estimate", value: $draft.operationalSnowfall, format: .number).keyboardType(.decimalPad)
                    }
                case 2, 3:
                    if step == 3 { Section { Text("Suggested stops use each service’s trigger. You can include or exclude any property.").foregroundStyle(.secondary) } }
                    Section {
                        ForEach(store.state.properties.filter(\.active)) { property in
                            Toggle(isOn: Binding(get: { selected.contains(property.id) }, set: { if $0 { selected.insert(property.id) } else { selected.remove(property.id) } })) {
                                VStack(alignment: .leading) {
                                    Text(property.name)
                                    if step == 3 {
                                        let triggered = property.services.filter { $0.active && $0.trigger <= draft.operationalSnowfall }
                                        Text(triggered.isEmpty ? "Below trigger · manual inclusion" : triggered.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case 4:
                    Section { ForEach(store.state.properties.filter { selected.contains($0.id) }) { property in
                        Picker(property.name, selection: Binding(get: { crews[property.id] ?? property.defaultCrewID ?? store.state.crews.first?.id ?? UUID() }, set: { crews[property.id] = $0 })) {
                            ForEach(store.state.crews) { Text($0.name).tag($0.id) }
                        }
                    } }
                case 5:
                    Section {
                        LabeledContent("Storm", value: draft.name)
                        LabeledContent("Snowfall", value: draft.operationalSnowfall.inches)
                        LabeledContent("Selected stops", value: "\(selected.count)")
                    }
                    Section { ForEach(store.state.properties.filter { selected.contains($0.id) }) { property in
                        LabeledContent(property.name, value: store.crew(crews[property.id] ?? property.defaultCrewID ?? UUID())?.name ?? "Unassigned")
                    } }
                default:
                    Section {
                        Toggle("Activate immediately", isOn: $activate)
                        Text("Assignments are saved locally. Cross-device delivery is unavailable in this development build.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section { PrimaryAction(title: activate ? "Activate storm" : "Save preparing storm", symbol: "cloud.snow") {
                        if store.createStorm(draft, selected: selected, crewAssignments: crews, activate: activate) { dismiss() }
                    } }
                }
            }.navigationTitle("New storm").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            if step > 0 { Button("Back") { step -= 1 } }
                            Spacer()
                            if step < 6 { Button("Continue") {
                                if step == 1 && selected.isEmpty {
                                    selected = Set(store.state.properties.filter { $0.active && $0.services.contains { $0.active && $0.trigger <= draft.operationalSnowfall } }.map(\.id))
                                }
                                if step == 4 { for property in store.state.properties where selected.contains(property.id) { crews[property.id] = crews[property.id] ?? property.defaultCrewID ?? store.state.crews.first?.id } }
                                step += 1
                            }.disabled(step == 0 && draft.name.isEmpty || step == 1 && (draft.forecastLow < 0 || draft.forecastHigh < draft.forecastLow || draft.operationalSnowfall < 0) || (step == 2 || step == 3) && selected.isEmpty) }
                        }
                    }
                }.interactiveDismissDisabled()
                .confirmationDialog("Discard new storm?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }
    }
}
