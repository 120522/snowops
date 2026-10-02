import SwiftUI
import SnowOpsCore

struct PropertyListView: View {
    @Environment(OperationsStore.self) private var store
    @State private var query = ""
    @State private var draft: Property?
    var body: some View {
        List {
            ForEach(store.state.properties.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.address.localizedCaseInsensitiveContains(query) }) { property in
                NavigationLink { PropertyConfigurationView(propertyID: property.id) } label: { PropertyRow(property: property) }
                    .swipeActions { if store.actor.allows(.manageProperties) { Button("Duplicate", systemImage: "doc.on.doc") { var copy = property; copy.id = UUID(); copy.name += " copy"; draft = copy }.tint(.blue) } }
            }
        }.navigationTitle("Properties").searchable(text: $query, prompt: "Name or address")
            .toolbar { if store.actor.allows(.manageProperties) {
                Button("New property", systemImage: "plus") {
                    guard let customer = store.state.customers.first else { store.error = "Create a customer first."; return }
                    draft = Property(customerID: customer.id, name: "", address: "", latitude: 40.62, longitude: -75.38)
                }
            } }
            .sheet(item: $draft) { PropertyEditorView(property: $0) }
            .overlay { if store.state.properties.isEmpty { ContentUnavailableView("No properties", systemImage: "building.2", description: Text("Add a customer, then configure their service locations.")) } }
    }
}
struct PropertyConfigurationView: View {
    @Environment(OperationsStore.self) private var store
    let propertyID: UUID
    @State private var edit = false
    var body: some View {
        if let property = store.property(propertyID) {
            List {
                Section { PropertyRow(property: property); LabeledContent("Customer", value: store.customer(property.customerID)?.name ?? "Customer"); LabeledContent("Type", value: property.type) }
                Section("Site information") { Text(property.instructions); Text(property.access); if !property.hazards.isEmpty { Label(property.hazards, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                Section("Service configuration") { ForEach(property.services) { service in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(service.name).font(.headline)
                        Text("\(service.method.title) · \(service.rate.currency) · trigger \(service.trigger.inches)").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(service.tiers) { tier in LabeledContent(tier.label, value: tier.amount.currency).font(.caption) }
                    }.padding(.vertical, 5)
                } }
                Section("Checklist") { ForEach(property.checklist) { Text($0.title + ($0.required ? " · required" : "")) } }
            }.navigationTitle(property.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { if store.actor.allows(.manageProperties) { Button("Edit") { edit = true } } }
                .sheet(isPresented: $edit) { PropertyEditorView(property: property) }
        }
    }
}
struct PropertyEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Property
    @State private var section = 0
    @State private var discard = false
    @State private var serviceDraft: PropertyService?
    @State private var checklistTitle = ""
    @State private var checklistKind: ChecklistKind = .checkbox
    @State private var checklistRequired = true
    private let sections = ["Customer", "Location", "Services & pricing", "Checklist", "Instructions", "Review"]
    init(property: Property) { _draft = State(initialValue: property) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("\(section + 1) of \(sections.count) · \(sections[section])").font(.headline); ProgressView(value: Double(section + 1), total: Double(sections.count)) }
                switch section {
                case 0:
                    Section { Picker("Customer", selection: $draft.customerID) { ForEach(store.state.customers.filter(\.active)) { Text($0.name).tag($0.id) } } }
                case 1:
                    Section {
                        TextField("Property name", text: $draft.name)
                        TextField("Service address", text: $draft.address)
                        Picker("Type", selection: $draft.type) { Text("Commercial").tag("Commercial"); Text("Residential").tag("Residential") }
                        TextField("Latitude", value: $draft.latitude, format: .number).keyboardType(.numbersAndPunctuation)
                        TextField("Longitude", value: $draft.longitude, format: .number).keyboardType(.numbersAndPunctuation)
                        Text("Verify coordinates before dispatch. Address geocoding is not connected in this build.").font(.footnote).foregroundStyle(.secondary)
                        Picker("Default crew", selection: $draft.defaultCrewID) { Text("Unassigned").tag(Optional<UUID>.none); ForEach(store.state.crews) { Text($0.name).tag(Optional($0.id)) } }
                        Stepper("Priority \(draft.priority)", value: $draft.priority, in: 1...5)
                    }
                case 2:
                    Section {
                        ForEach(draft.services) { service in Button { serviceDraft = service } label: { LabeledContent(service.name, value: service.method.title) } }
                            .onDelete { draft.services.remove(atOffsets: $0) }
                        Button("Add service", systemImage: "plus") { serviceDraft = PropertyService(name: "Snow plowing", method: .perPush, rate: 0) }
                    }
                case 3:
                    Section("Reuse a template") { ForEach(store.state.templates) { template in Button(template.name) { draft.checklist = template.items } } }
                    Section("Required work") { ForEach(draft.checklist) { item in Text(item.title + (item.required ? " *" : "")) }.onDelete { draft.checklist.remove(atOffsets: $0) } }
                    Section("Add checklist item") {
                        TextField("Item title", text: $checklistTitle)
                        Picker("Response", selection: $checklistKind) { ForEach(ChecklistKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        Toggle("Required", isOn: $checklistRequired)
                        Button("Add item") { draft.checklist.append(ChecklistItem(checklistTitle, required: checklistRequired, kind: checklistKind)); checklistTitle = "" }.disabled(checklistTitle.isEmpty)
                    }
                case 4:
                    Section {
                        TextField("Snow instructions", text: $draft.instructions, axis: .vertical)
                        TextField("Access instructions", text: $draft.access, axis: .vertical)
                        TextField("Hazards", text: $draft.hazards, axis: .vertical)
                        TextField("Internal notes", text: $draft.notes, axis: .vertical)
                    }
                default:
                    Section {
                        PropertyRow(property: draft)
                        LabeledContent("Customer", value: store.customer(draft.customerID)?.name ?? "Customer")
                        LabeledContent("Services", value: "\(draft.services.count)")
                        LabeledContent("Checklist items", value: "\(draft.checklist.count)")
                        PrimaryAction(title: "Save property", symbol: "checkmark") { if store.saveProperty(draft) { dismiss() } }
                    }
                }
            }.navigationTitle("Property setup").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                    ToolbarItem(placement: .bottomBar) { HStack {
                        if section > 0 { Button("Back") { section -= 1 } }
                        Spacer()
                        if section < sections.count - 1 { Button("Continue") { section += 1 }.disabled(section == 1 && (draft.name.isEmpty || draft.address.isEmpty)) }
                    } }
                }.interactiveDismissDisabled()
                .confirmationDialog("Discard property changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
                .sheet(item: $serviceDraft) { service in ServiceEditorView(service: service) { updated in
                    if let index = draft.services.firstIndex(where: { $0.id == updated.id }) { draft.services[index] = updated } else { draft.services.append(updated) }
                } }
        }
    }
}
struct ServiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PropertyService
    @State private var error: String?
    @State private var discard = false
    let save: (PropertyService) -> Void
    init(service: PropertyService, save: @escaping (PropertyService) -> Void) { _draft = State(initialValue: service); self.save = save }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Service name (custom names supported)", text: $draft.name)
                    Toggle("Active", isOn: $draft.active)
                    TextField("Trigger inches", value: $draft.trigger, format: .number).keyboardType(.decimalPad)
                    Picker("Pricing", selection: $draft.method) { ForEach(PricingMethod.allCases, id: \.self) { Text($0.title).tag($0) } }
                    TextField("Rate", value: $draft.rate, format: .number).keyboardType(.decimalPad)
                    Toggle("Service photo required", isOn: $draft.photoRequired)
                    TextField("Instructions", text: $draft.instructions, axis: .vertical)
                }
                if draft.method == .snowfallTier {
                    Section("Custom snowfall tiers") {
                        Text("Lower bounds are inclusive; upper bounds are exclusive. Tiers apply to each performed visit. Use an open-ended last tier for additional-inch pricing.").font(.footnote).foregroundStyle(.secondary)
                        ForEach(draft.tiers.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("From inches", value: $draft.tiers[index].lower, format: .number).keyboardType(.decimalPad)
                                Toggle("Open-ended", isOn: Binding(get: { draft.tiers[index].upper == nil }, set: { draft.tiers[index].upper = $0 ? nil : draft.tiers[index].lower + 3 }))
                                if draft.tiers[index].upper != nil { TextField("Up to inches", value: Binding(get: { draft.tiers[index].upper ?? 0 }, set: { draft.tiers[index].upper = $0 }), format: .number).keyboardType(.decimalPad) }
                                TextField("Tier amount", value: $draft.tiers[index].amount, format: .number).keyboardType(.decimalPad)
                                TextField("Additional inch rate (0 for none)", value: Binding(get: { draft.tiers[index].additionalInchRate ?? 0 }, set: { draft.tiers[index].additionalInchRate = $0 }), format: .number).keyboardType(.decimalPad)
                            }.padding(.vertical, 8)
                        }.onDelete { draft.tiers.remove(atOffsets: $0) }
                        Button("Add tier", systemImage: "plus") { let lower = draft.tiers.last?.upper ?? 0; draft.tiers.append(SnowTier(lower: lower, upper: lower + 3, amount: 0)) }
                    }
                }
                if draft.method == .manual { Section { Text("Manual pricing blocks storm calculation until an administrator sets a pricing method and rate in the completed visit correction workflow.").foregroundStyle(.orange) } }
            }.navigationTitle("Service & pricing").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try PricingEngine.validate(draft); guard !draft.name.isEmpty else { throw DomainError.invalid("Enter a service name.") }; save(draft); dismiss() } catch { self.error = error.localizedDescription } } }
                }.interactiveDismissDisabled()
                .confirmationDialog("Discard service changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
                .alert("Check pricing", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
