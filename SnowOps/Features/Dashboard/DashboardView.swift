import SwiftUI
import SnowOpsCore

struct DashboardView: View {
    @Environment(OperationsStore.self) private var store
    @State private var newStorm = false
    var body: some View {
        Group {
            if !store.isAdminInterface { FieldHomeView() }
            else {
                List {
                    if let storm = store.activeStorm {
                        Section {
                            NavigationLink { StormDetailView(stormID: storm.id) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Live operations", systemImage: "cloud.snow.fill").font(.subheadline).foregroundStyle(.blue)
                                    Text(storm.name).font(.title2.bold())
                                    Text("\(storm.operationalSnowfall.inches) operational snowfall").foregroundStyle(.secondary)
                                    let stops = store.route(stormID: storm.id)
                                    let completed = stops.filter { $0.status == .completed }.count
                                    ProgressView(value: Double(completed), total: Double(max(1, stops.count)))
                                    Text("\(completed) of \(stops.count) stops complete").font(.subheadline)
                                }.padding(.vertical, 10)
                            }
                        }
                        Section {
                            HStack {
                                Metric(value: "\(Set(store.route(stormID: storm.id).map(\.crewID)).count)", label: "Crews", symbol: "person.2")
                                Metric(value: "\(store.visits(stormID: storm.id).filter { $0.departure != nil && !$0.canceled }.count)", label: "Visits", symbol: "checkmark.circle")
                            }
                            NavigationLink("Open dispatch", destination: DispatchView())
                            NavigationLink("View operations map", destination: OperationsMapView())
                        }
                        let issues = store.state.issues.filter { $0.stormID == storm.id && !$0.resolved }
                        if !issues.isEmpty {
                            Section("Needs attention") { ForEach(issues) { issue in IssueRow(issue: issue) } }
                        }
                    } else {
                        Section {
                            ContentUnavailableView("No active storm", systemImage: "cloud.snow", description: Text("Prepare a storm when snow is in the forecast."))
                            if store.actor.allows(.dispatch) { Button("Create storm", systemImage: "plus") { newStorm = true } }
                        }
                    }
                    Section("Recent & preparing storms") {
                        ForEach(store.state.storms.reversed()) { storm in
                            NavigationLink { StormDetailView(stormID: storm.id) } label: {
                                VStack(alignment: .leading) { Text(storm.name); Text(storm.status.title).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section("Your operation") {
                        NavigationLink("\(store.state.properties.count) properties", destination: PropertyListView())
                        NavigationLink("\(store.state.crews.count) crews", destination: CrewsView())
                    }
                }.navigationTitle("Snow Ops")
                    .toolbar { if store.actor.allows(.dispatch) { Button("New storm", systemImage: "plus") { newStorm = true } } }
            }
        }.sheet(isPresented: $newStorm) { StormWizardView() }
    }
}
struct FieldHomeView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        List {
            if let storm = store.activeStorm {
                let route = store.route(stormID: storm.id, crewID: store.actor.crewID)
                let remaining = route.filter { $0.status != .completed && $0.status != .skipped }
                Section {
                    Label(storm.name, systemImage: "cloud.snow.fill").font(.headline)
                    Text(store.actor.crewID.flatMap(store.crew)?.name ?? "No crew assigned").foregroundStyle(.secondary)
                    ProgressView(value: Double(route.count - remaining.count), total: Double(max(1, route.count)))
                    Text("\(route.count - remaining.count) complete · \(remaining.count) remaining").font(.subheadline)
                }
                if let current = remaining.first, let property = store.property(current.propertyID) {
                    Section("Your next stop") {
                        PropertyRow(property: property, status: current.status)
                        NavigationLink { AssignmentDetailView(assignmentID: current.id) } label: {
                            Label(current.status == .inProgress ? "Continue visit" : "Start next property", systemImage: "arrow.right.circle.fill")
                                .font(.headline).frame(minHeight: 52).foregroundStyle(.blue)
                        }
                    }
                    if remaining.count > 1, let next = store.property(remaining[1].propertyID) {
                        Section("Then") { PropertyRow(property: next, status: remaining[1].status) }
                    }
                } else { ContentUnavailableView("Route complete", systemImage: "checkmark.circle", description: Text("Every assigned stop is accounted for. New assignments will appear in your route.")) }
            } else { ContentUnavailableView("No active assignment", systemImage: "cloud.snow", description: Text("Your route will appear when a storm is activated.")) }
        }.navigationTitle("Ready for the next stop")
    }
}
struct IssueRow: View {
    @Environment(OperationsStore.self) private var store
    let issue: Issue
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(issue.category, systemImage: "exclamationmark.triangle.fill").foregroundStyle(issue.severity == .critical ? .red : .orange).font(.headline)
            Text(store.property(issue.propertyID)?.name ?? "Property")
            if !issue.note.isEmpty { Text(issue.note).font(.subheadline).foregroundStyle(.secondary) }
            Text(issue.resolved ? "Resolved" : issue.severity.rawValue.capitalized).font(.caption)
            if store.actor.allows(.reviewVisits), !issue.resolved, store.storm(issue.stormID)?.status != .finalized {
                Button("Mark resolved") { store.resolveIssue(issue) }.frame(minHeight: 44)
            }
        }.padding(.vertical, 6)
    }
}
