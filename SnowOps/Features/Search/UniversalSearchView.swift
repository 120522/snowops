import SwiftUI
import SnowOpsCore

struct UniversalSearchView: View {
    @Environment(OperationsStore.self) private var store
    @State private var query = ""
    var body: some View {
        List {
            if !query.isEmpty {
                Section("Properties") { ForEach(store.state.properties.filter { matches($0.name) || matches($0.address) }) { property in NavigationLink { PropertyConfigurationView(propertyID: property.id) } label: { PropertyRow(property: property) } } }
                Section("Customers") { ForEach(store.state.customers.filter { matches($0.name) }) { customer in NavigationLink(customer.name, destination: CustomerDetailView(customerID: customer.id)) } }
                Section("Storms") { ForEach(store.state.storms.filter { matches($0.name) }) { storm in NavigationLink(storm.name, destination: StormDetailView(stormID: storm.id)) } }
                Section("Crews") { ForEach(store.state.crews.filter { matches($0.name) }) { crew in NavigationLink(crew.name, destination: CrewsView()) } }
                Section("Employees") { ForEach(store.state.employees.filter { matches($0.name) }) { employee in NavigationLink(employee.name, destination: EmployeesView()) } }
                Section("Visits") { ForEach(store.state.visits.filter { matches(store.property($0.propertyID)?.name ?? "") || matches($0.notes) || matches($0.id.uuidString) }) { visit in NavigationLink { VisitRecordView(visitID: visit.id) } label: { VStack(alignment: .leading) { Text(store.property(visit.propertyID)?.name ?? "Visit"); Text(visit.arrival, style: .date).font(.caption) } } } }
            } else { ContentUnavailableView("Search your operation", systemImage: "magnifyingglass", description: Text("Find properties by name or address, customers, storms, crews, employees and visits.")) }
        }.navigationTitle("Search").searchable(text: $query, prompt: "Names, addresses or visit notes")
    }
    private func matches(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(query) }
}
