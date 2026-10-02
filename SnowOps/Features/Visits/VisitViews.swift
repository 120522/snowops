import SwiftUI
import MapKit
import PhotosUI
import SnowOpsCore

struct AssignmentDetailView: View {
    @Environment(OperationsStore.self) private var store
    let assignmentID: UUID
    @State private var visitID: UUID?
    @State private var issue = false
    @State private var feedback = 0
    var body: some View {
        if let assignment = store.state.assignments.first(where: { $0.id == assignmentID }), let property = store.property(assignment.propertyID) {
            List {
                Section {
                    PropertyRow(property: property, status: assignment.status)
                    Button("Navigate with Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill") { navigate(property) }.frame(minHeight: 44)
                }
                Section("Required services") { ForEach(property.services.filter(\.active)) { service in
                    VStack(alignment: .leading, spacing: 4) { Text(service.name).font(.headline); if !service.instructions.isEmpty { Text(service.instructions).foregroundStyle(.secondary) } }
                } }
                Section("Site instructions") {
                    Text(property.instructions)
                    if !property.access.isEmpty { Label(property.access, systemImage: "key") }
                    if !property.hazards.isEmpty { Label(property.hazards, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                if !property.checklist.isEmpty { Section("Checklist") { ForEach(property.checklist) { item in Label(item.title + (item.required ? " · required" : ""), systemImage: "square").font(.subheadline) } } }
                let previous = store.state.visits.filter { $0.propertyID == property.id && !$0.notes.isEmpty }
                if !previous.isEmpty { Section("Previous notes") { ForEach(previous.suffix(3)) { visit in VStack(alignment: .leading) { Text(visit.notes); Text(visit.arrival, style: .date).font(.caption).foregroundStyle(.secondary) } } } }
                Section {
                    Button("Report issue", systemImage: "exclamationmark.bubble") { issue = true }.frame(minHeight: 44)
                    if store.actor.allows(.dispatch), assignment.status != .inProgress {
                        Menu("Crew assignment") { ForEach(store.state.crews) { crew in Button(crew.name) { _ = store.reassign(assignment, crewID: crew.id) } } }
                    }
                    if store.actor.allows(.dispatch), assignment.status == .completed {
                        Button("Dispatch an additional visit", systemImage: "plus") { _ = store.addAdditionalVisit(assignment) }
                    }
                }
                if assignment.status == .completed {
                    Section("Completed visit records") {
                        ForEach(store.state.visits.filter { $0.assignmentID == assignment.id && !$0.canceled }) { visit in
                            NavigationLink { VisitRecordView(visitID: visit.id) } label: { Label(visit.arrival.formatted(date: .abbreviated, time: .shortened), systemImage: "checkmark.circle") }
                        }
                    }
                }
            }.navigationTitle(property.name).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if assignment.status == .pending || assignment.status == .inProgress || assignment.status == .attention {
                        PrimaryAction(title: assignment.status == .inProgress ? "Continue visit" : "Start visit", symbol: "play.fill",
                                      disabled: store.storm(assignment.stormID)?.status != .active && store.storm(assignment.stormID)?.status != .wrappingUp) {
                            if let id = store.start(assignment) { visitID = id; feedback += 1 }
                        }.padding().background(.bar)
                    }
                }.sensoryFeedback(.success, trigger: feedback)
                .navigationDestination(isPresented: Binding(get: { visitID != nil }, set: { if !$0 { visitID = nil } })) {
                    if let visitID, let visit = store.visit(visitID) { VisitEditorView(visit: visit) }
                }.sheet(isPresented: $issue) { ReportIssueView(stormID: assignment.stormID, propertyID: property.id) }
        }
    }
    private func navigate(_ property: Property) {
        let place = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude)))
        place.name = property.name
        place.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

struct VisitEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Visit
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var feedback = 0
    @State private var confirmComplete = false
    @State private var materialSheet = false
    @State private var issueSheet = false
    @State private var completed = false
    @State private var additionalService: PropertyService?
    init(visit: Visit) { _draft = State(initialValue: visit) }
    var body: some View {
        Form {
            Section {
                Text(store.property(draft.propertyID)?.name ?? "Property").font(.title2.bold())
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("On site", value: Duration.seconds(max(0, context.date.timeIntervalSince(draft.arrival))).formatted(.time(pattern: .hourMinuteSecond)))
                }
                Label("Changes saved on this device", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
            }
            Section("Checklist") {
                ForEach(draft.checklist.indices, id: \.self) { index in
                    let item = draft.checklist[index].item
                    switch item.kind {
                    case .checkbox, .confirmation:
                        Toggle(item.title + (item.required ? " *" : ""), isOn: $draft.checklist[index].checked).frame(minHeight: 44)
                    case .yesNo:
                        Picker(item.title + (item.required ? " *" : ""), selection: $draft.checklist[index].value) {
                            Text("Choose").tag(""); Text("Yes").tag("Yes"); Text("No").tag("No")
                        }
                    case .number, .text:
                        TextField(item.title + (item.required ? " *" : ""), text: $draft.checklist[index].value).keyboardType(item.kind == .number ? .decimalPad : .default)
                    case .photo:
                        Picker(item.title + (item.required ? " *" : ""), selection: $draft.checklist[index].photoID) {
                            Text("Choose attached photo").tag(Optional<UUID>.none)
                            ForEach(Array(draft.photos.enumerated()), id: \.element.id) { photoIndex, photo in Text("Photo \(photoIndex + 1)").tag(Optional(photo.id)) }
                        }
                    }
                }
            }
            Section("Services performed") {
                ForEach(draft.services.indices, id: \.self) { index in
                    Toggle(draft.services[index].configuration.name, isOn: $draft.services[index].performed).frame(minHeight: 44)
                    if draft.services[index].performed {
                        TextField("Quantity", value: $draft.services[index].quantity, format: .number).keyboardType(.decimalPad)
                    }
                }
                Button("Add additional service", systemImage: "plus") { additionalService = PropertyService(name: "Additional re-plow", method: .perVisit, rate: 0) }
            }
            Section("Materials") {
                ForEach(draft.materials) { material in LabeledContent(material.name, value: "\(material.quantity) \(material.unit)") }
                    .onDelete { draft.materials.remove(atOffsets: $0) }
                Button("Record material", systemImage: "plus") { materialSheet = true }.frame(minHeight: 44)
            }
            Section("Documentation") {
                TextField("Service notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(photoLoading ? "Saving photo…" : "Attach service photo", systemImage: "camera") }.disabled(photoLoading).frame(minHeight: 44)
                ScrollView(.horizontal) { HStack {
                    ForEach(draft.photos) { photo in
                        if let image = UIImage(contentsOfFile: store.photoURL(photo).path) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 110, height: 90).clipped().clipShape(.rect(cornerRadius: 10)).accessibilityLabel("Attached service photo")
                        }
                    }
                } }
                Button("Report issue", systemImage: "exclamationmark.bubble") { issueSheet = true }.frame(minHeight: 44)
            }
            if store.actor.allows(.reviewVisits) {
                Section("Authorized checklist override") { TextField("Reason (only if required items cannot be met)", text: $draft.overrideReason, axis: .vertical) }
            }
            let problems = Validation.completionProblems(draft)
            if !problems.isEmpty { Section("Still needed") { ForEach(problems, id: \.self) { Label($0, systemImage: "circle").foregroundStyle(.secondary) } } }
        }.navigationTitle("Active visit").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryAction(title: "Complete service", symbol: "checkmark", disabled: photoLoading || completed) { confirmComplete = true }.padding().background(.bar)
            }
            .onChange(of: try? JSONEncoder().encode(draft)) { _, _ in
                if !completed { _ = store.saveVisit(draft) }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                photoLoading = true
                Task { @MainActor in
                    defer { photoLoading = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw DomainError.invalid("This image could not be read.") }
                        if let photo = store.attachPhoto(jpeg, visitID: draft.id) { draft.photos.append(photo) }
                    } catch { store.error = error.localizedDescription }
                }
            }
            .confirmationDialog("Complete this visit?", isPresented: $confirmComplete, titleVisibility: .visible) {
                Button("Complete service") {
                    if store.saveVisit(draft, complete: true) { completed = true; feedback += 1; dismiss() }
                }
            } message: { Text("Your service record and departure time will be saved locally.") }
            .sensoryFeedback(.success, trigger: feedback)
            .sheet(isPresented: $materialSheet) { MaterialEntryView { draft.materials.append($0) } }
            .sheet(isPresented: $issueSheet) { ReportIssueView(stormID: draft.stormID, propertyID: draft.propertyID) }
            .sheet(item: $additionalService) { service in
                ServiceEditorView(service: service) { updated in
                    // Field records quantities and service names; only administrators set billable rates.
                    var configuration = updated
                    if !store.actor.allows(.reviewBilling) { configuration.method = .manual; configuration.rate = 0; configuration.tiers = [] }
                    draft.services.append(VisitService(configuration: configuration))
                }
            }
    }
}
struct MaterialEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Rock salt"
    @State private var quantity: Decimal = 0
    @State private var unit = "lb"
    let save: (MaterialUsage) -> Void
    var body: some View {
        NavigationStack { Form {
            Picker("Material", selection: $name) { Text("Rock salt").tag("Rock salt"); Text("Calcium chloride").tag("Calcium chloride"); Text("Brine").tag("Brine") }
            TextField("Quantity", value: $quantity, format: .number).keyboardType(.decimalPad)
            Picker("Unit", selection: $unit) { ForEach(["lb", "ton", "gal", "bag"], id: \.self) { Text($0).tag($0) } }
            Button("Save material") { save(MaterialUsage(name: name, quantity: quantity, unit: unit)); dismiss() }.disabled(quantity <= 0)
        }.navigationTitle("Record material").toolbar { Button("Cancel") { dismiss() } } }.presentationDetents([.medium, .large])
    }
}
struct ReportIssueView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let stormID: UUID
    let propertyID: UUID
    @State private var category = "Vehicle blocking lot"
    @State private var severity: Severity = .normal
    @State private var note = ""
    @State private var discard = false
    private let categories = ["Vehicle blocking lot", "Property inaccessible", "Heavy drifting", "Ice condition", "Equipment problem", "Customer request", "Damage concern", "Service cannot be completed"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                    Picker("Severity", selection: $severity) { ForEach(Severity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    TextField("What happened?", text: $note, axis: .vertical).lineLimit(3...8)
                    Text("Attach supporting photos from the active visit. Issue-specific photo capture is not yet available.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { PrimaryAction(title: "Report issue", symbol: "exclamationmark.bubble") {
                    if store.reportIssue(Issue(stormID: stormID, propertyID: propertyID, category: category, note: note, severity: severity, createdBy: store.actorID)) { dismiss() }
                } }
            }.navigationTitle("Report issue").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if note.isEmpty { dismiss() } else { discard = true } } } }
                .interactiveDismissDisabled(!note.isEmpty)
                .confirmationDialog("Discard issue report?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

struct HistoryView: View {
    @Environment(OperationsStore.self) private var store
    var stormID: UUID?
    var body: some View {
        let visits = store.state.visits.filter { (stormID == nil || $0.stormID == stormID) && (store.isAdminInterface || $0.crewID == store.actor.crewID) }.sorted { $0.arrival > $1.arrival }
        List(visits) { visit in
            NavigationLink { VisitRecordView(visitID: visit.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.property(visit.propertyID)?.name ?? "Property").font(.headline)
                    Text(visit.arrival, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                    Text(visit.canceled ? "Canceled" : visit.departure == nil ? "In progress" : "Completed").font(.caption).foregroundStyle(visit.departure == nil ? .blue : .secondary)
                }
            }
        }.navigationTitle("Visit history")
            .overlay { if visits.isEmpty { ContentUnavailableView("No visit records", systemImage: "clock", description: Text("Start your first property visit to create a service record.")) } }
    }
}
struct VisitRecordView: View {
    @Environment(OperationsStore.self) private var store
    let visitID: UUID
    @State private var correction = false
    var body: some View {
        if let visit = store.visit(visitID) {
            List {
                Section("Service record") {
                    Text(store.property(visit.propertyID)?.name ?? "Property").font(.headline)
                    LabeledContent("Crew", value: store.crew(visit.crewID)?.name ?? "Crew")
                    LabeledContent("Arrival", value: visit.arrival.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Departure", value: visit.departure?.formatted(date: .abbreviated, time: .shortened) ?? "Still on site")
                    LabeledContent("Created", value: visit.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if !visit.overrideReason.isEmpty { LabeledContent("Override reason", value: visit.overrideReason) }
                }
                Section("Performed services") { ForEach(visit.services.filter(\.performed)) { LabeledContent($0.configuration.name, value: "\($0.quantity)") } }
                Section("Checklist") { ForEach(visit.checklist, id: \.item.id) { response in Label(response.item.title + (response.value.isEmpty ? "" : ": \(response.value)"), systemImage: response.satisfied ? "checkmark.circle.fill" : "circle").foregroundStyle(response.satisfied ? .green : .secondary) } }
                Section("Materials") { ForEach(visit.materials) { LabeledContent($0.name, value: "\($0.quantity) \($0.unit)") } }
                if !visit.notes.isEmpty { Section("Field notes") { Text(visit.notes) } }
                if !visit.photos.isEmpty { Section("Photos") { ForEach(visit.photos) { photo in if let image = UIImage(contentsOfFile: store.photoURL(photo).path) { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Service documentation photo") } } } }
                if visit.departure != nil {
                    Section {
                        if store.actor.allows(.reviewVisits), store.storm(visit.stormID)?.status != .finalized {
                            Button("Correct service record") { correction = true }
                        }
                        Text("Completed records retain their original values in audit history. Corrections require an authorized user and a reason.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                else { NavigationLink("Continue active visit") { VisitEditorView(visit: visit) } }
            }.navigationTitle("Visit record").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $correction) { VisitCorrectionView(visit: visit) }
        }
    }
}

struct VisitCorrectionView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Visit
    @State private var reason = ""
    @State private var confirm = false
    @State private var discard = false
    init(visit: Visit) { _draft = State(initialValue: visit) }
    var body: some View {
        NavigationStack { Form {
            Section("Recorded times") {
                DatePicker("Arrival", selection: $draft.arrival)
                DatePicker("Departure", selection: Binding(get: { draft.departure ?? Date() }, set: { draft.departure = $0 }))
            }
            Section("Service corrections") {
                ForEach(draft.services.indices, id: \.self) { index in
                    Toggle(draft.services[index].configuration.name, isOn: $draft.services[index].performed)
                    TextField("Quantity", value: $draft.services[index].quantity, format: .number).keyboardType(.decimalPad)
                    if store.actor.allows(.reviewBilling) {
                        Picker("Pricing method", selection: $draft.services[index].configuration.method) { ForEach(PricingMethod.allCases, id: \.self) { Text($0.title).tag($0) } }
                        TextField("Rate", value: $draft.services[index].configuration.rate, format: .number).keyboardType(.decimalPad)
                    }
                }
                if store.actor.allows(.reviewBilling) { Toggle("Billable visit", isOn: $draft.billable) }
                Toggle("Cancel erroneous visit", isOn: $draft.canceled)
            }
            Section("Documentation") {
                TextField("Manager notes", text: $draft.managerNotes, axis: .vertical)
                TextField("Checklist override reason", text: $draft.overrideReason, axis: .vertical)
                TextField("Reason for this correction (required)", text: $reason, axis: .vertical)
                Text("The original record remains in audit history. Billing must be recalculated and reviewed after this correction.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Correct visit").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { confirm = true }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.interactiveDismissDisabled()
            .confirmationDialog("Apply this audited correction?", isPresented: $confirm, titleVisibility: .visible) { Button("Save correction", role: draft.canceled ? .destructive : nil) { if store.correctVisit(draft, reason: reason) { dismiss() } } }
            .confirmationDialog("Discard correction?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }
    }
}
