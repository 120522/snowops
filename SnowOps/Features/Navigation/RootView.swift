import SwiftUI
import SnowOpsCore

struct RootView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("Home", systemImage: "house") { NavigationStack { DashboardView() } }
            if store.isAdminInterface {
                Tab("Storms", systemImage: "cloud.snow") { NavigationStack { StormListView() } }
                Tab("Dispatch", systemImage: "person.2.badge.gearshape") { NavigationStack { DispatchView() } }
                Tab("Properties", systemImage: "building.2") { NavigationStack { PropertyListView() } }
            } else {
                Tab("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { NavigationStack { RouteView() } }
                Tab("Map", systemImage: "map") { NavigationStack { OperationsMapView() } }
                Tab("History", systemImage: "clock") { NavigationStack { HistoryView() } }
            }
            Tab("More", systemImage: "ellipsis") { NavigationStack { MoreView() } }
        }.tint(.blue)
            .safeAreaInset(edge: .top, spacing: 0) { SyncBanner() }
            .alert("Couldn’t save this change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

struct MoreView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        List {
            Section {
                Label(store.actor.name, systemImage: "person.crop.circle").font(.headline)
                LabeledContent("Role", value: store.actor.role.title)
                if let id = store.actor.crewID { LabeledContent("Crew", value: store.crew(id)?.name ?? "Unassigned") }
            }
            if store.isAdminInterface {
                Section("Operations") {
                    NavigationLink("Customers", destination: CustomerListView())
                    NavigationLink("Crews", destination: CrewsView())
                    NavigationLink("Employees", destination: EmployeesView())
                    NavigationLink("Checklist templates", destination: TemplatesView())
                    if store.actor.allows(.reviewBilling) { NavigationLink("Invoice preparation", destination: InvoicePrepView()) }
                    NavigationLink("Search everything", destination: UniversalSearchView())
                    NavigationLink("Audit history", destination: AuditHistoryView())
                }
            }
            Section { NavigationLink("Settings & development access", destination: SettingsView()) }
        }.navigationTitle("More")
    }
}
struct SettingsView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Development access") {
                Text("This build uses sample identities. Selecting a role previews its interface; it is not authenticated access.").foregroundStyle(.secondary)
                Picker("Preview identity", selection: $store.actorID) {
                    ForEach(store.state.employees) { employee in Text("\(employee.name) · \(employee.role.title)").tag(employee.id) }
                }
            }
            Section("Local storage") {
                LabeledContent("Pending changes", value: "\(store.outbox.count)")
                Label("Records saved on this device", systemImage: "checkmark.shield")
                Text("Cloud sync, sign-in, push notifications, background transfers and cross-device dispatch are unavailable until a production backend is connected. Pending changes are retained; this build never claims they are synced.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                Text("Snow Ops follows system text size, contrast, Reduce Motion, Reduce Transparency and Dark Mode. Primary service controls use large touch targets.")
            }
        }.navigationTitle("Settings")
    }
}

struct AuditHistoryView: View {
    @Environment(OperationsStore.self) private var store
    var body: some View {
        List(store.state.audit.reversed()) { event in
            VStack(alignment: .leading, spacing: 5) {
                Text(event.action).font(.headline)
                Text(store.state.employees.first { $0.id == event.actorID }?.name ?? event.actorID.uuidString).font(.subheadline)
                Text(event.timestamp, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                if !event.reason.isEmpty { Text(event.reason).font(.subheadline) }
            }
        }.navigationTitle("Audit history")
            .overlay { if store.state.audit.isEmpty { ContentUnavailableView("No changes yet", systemImage: "clock", description: Text("Saved changes will show the person, time and reason here.")) } }
    }
}
