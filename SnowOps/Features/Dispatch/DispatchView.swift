import SwiftUI
import SnowOpsCore

struct DispatchView: View {
    @Environment(OperationsStore.self) private var store
    var stormID: UUID?
    @State private var query = ""
    @State private var skipAssignment: Assignment?
    @State private var skipReason = ""
    var body: some View {
        Group {
            if let storm = stormID.flatMap(store.storm) ?? store.activeStorm {
                List {
                    Section { Text(storm.name).font(.headline) }
                    ForEach(store.state.crews) { crew in
                        let stops = store.route(stormID: storm.id, crewID: crew.id).filter { query.isEmpty || store.property($0.propertyID)?.name.localizedCaseInsensitiveContains(query) == true || store.property($0.propertyID)?.address.localizedCaseInsensitiveContains(query) == true }
                        if !stops.isEmpty {
                            Section {
                                ForEach(stops) { assignment in
                                    if let property = store.property(assignment.propertyID) {
                                        NavigationLink { AssignmentDetailView(assignmentID: assignment.id) } label: { PropertyRow(property: property, status: assignment.status) }
                                            .contextMenu {
                                                if store.actor.allows(.dispatch), storm.status != .finalized {
                                                    Menu("Reassign crew") { ForEach(store.state.crews) { target in Button(target.name) { _ = store.reassign(assignment, crewID: target.id) } } }
                                                    Button("Add another visit", systemImage: "plus") { _ = store.addAdditionalVisit(assignment) }
                                                    if assignment.status == .pending || assignment.status == .attention { Button("Account for without service") { skipAssignment = assignment } }
                                                }
                                            }
                                    }
                                }.onMove { from, to in if query.isEmpty { store.reorder(stops, from: from, to: to) } }
                            } header: {
                                Text("\(crew.name) · \(stops.filter { $0.status == .completed }.count)/\(stops.count)")
                            } footer: { Text(crew.equipment) }
                        }
                    }
                }.toolbar { if store.actor.allows(.dispatch), query.isEmpty, storm.status != .finalized { EditButton() } }
            } else { ContentUnavailableView("No active dispatch", systemImage: "person.2", description: Text("Create and activate a storm to dispatch your crews.")) }
        }.navigationTitle("Dispatch").searchable(text: $query, prompt: "Properties or addresses")
            .sheet(item: $skipAssignment) { assignment in
                NavigationStack { Form {
                    Text("Account for this stop without recording performed service.")
                    TextField("Reason", text: $skipReason, axis: .vertical)
                    Button("Save exception") { if store.skip(assignment, reason: skipReason) { skipAssignment = nil; skipReason = "" } }.disabled(skipReason.isEmpty)
                }.navigationTitle("Stop exception").toolbar { Button("Cancel") { skipAssignment = nil } } }.presentationDetents([.medium, .large])
            }
    }
}
struct RouteView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        List {
            if let storm = store.activeStorm, let crewID = store.actor.crewID {
                let stops = store.route(stormID: storm.id, crewID: crewID)
                Section { Text(storm.name).font(.headline); Text("\(stops.filter { $0.status == .completed }.count) complete · \(stops.count) stops").foregroundStyle(.secondary) }
                ForEach(stops) { assignment in
                    if let property = store.property(assignment.propertyID) {
                        NavigationLink { AssignmentDetailView(assignmentID: assignment.id) } label: { PropertyRow(property: property, status: assignment.status) }
                    }
                }
            } else { ContentUnavailableView("No assigned route", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("An administrator must assign your crew to an active storm.")) }
        }.navigationTitle("Your route")
    }
}
