import SwiftUI
import SnowOpsCore

struct CustomerListView: View {
    @Environment(OperationsStore.self) private var store
    @State private var query = ""
    @State private var create = false
    var body: some View {
        List(store.state.customers.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { customer in
            NavigationLink { CustomerDetailView(customerID: customer.id) } label: {
                VStack(alignment: .leading, spacing: 6) { Text(customer.name).font(.headline); Text("\(store.state.properties.filter { $0.customerID == customer.id }.count) properties").font(.subheadline).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Customers").searchable(text: $query)
            .toolbar { if store.actor.allows(.manageCustomers) { Button("New customer", systemImage: "plus") { create = true } } }
            .sheet(isPresented: $create) { CustomerEditorView() }
    }
}
struct CustomerDetailView: View {
    @Environment(OperationsStore.self) private var store
    let customerID: UUID
    @State private var edit = false
    var body: some View {
        if let customer = store.customer(customerID) {
            List {
                Section("Contact") { LabeledContent("Name", value: customer.contact); LabeledContent("Phone", value: customer.phone); LabeledContent("Email", value: customer.email); LabeledContent("Status", value: customer.active ? "Active" : "Archived") }
                if !customer.billingNotes.isEmpty { Section("Billing notes") { Text(customer.billingNotes) } }
                if !customer.notes.isEmpty { Section("Notes") { Text(customer.notes) } }
                Section("Properties") { ForEach(store.state.properties.filter { $0.customerID == customerID }) { property in NavigationLink { PropertyConfigurationView(propertyID: property.id) } label: { PropertyRow(property: property) } } }
            }.navigationTitle(customer.name)
                .toolbar { if store.actor.allows(.manageCustomers) { Button("Edit") { edit = true } } }
                .sheet(isPresented: $edit) { CustomerEditorView(customer: customer) }
        }
    }
}
struct CustomerEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Customer
    @State private var discard = false
    @State private var archive = false
    private let existing: Bool
    init(customer: Customer? = nil) { _draft = State(initialValue: customer ?? Customer(name: "")); existing = customer != nil }
    var body: some View {
        NavigationStack { Form {
            Section("Customer") {
                TextField("Company or customer name", text: $draft.name)
                TextField("Primary contact", text: $draft.contact)
                TextField("Phone", text: $draft.phone).keyboardType(.phonePad)
                TextField("Email", text: $draft.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section("Notes") { TextField("Billing notes", text: $draft.billingNotes, axis: .vertical); TextField("Customer notes", text: $draft.notes, axis: .vertical) }
            if existing { Section { Button(draft.active ? "Archive customer" : "Restore customer", role: draft.active ? .destructive : nil) { archive = true } } }
        }.navigationTitle(existing ? "Edit customer" : "New customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(draft.name.isEmpty) }
            }.interactiveDismissDisabled()
            .confirmationDialog("Discard changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
            .confirmationDialog(draft.active ? "Archive this customer?" : "Restore this customer?", isPresented: $archive, titleVisibility: .visible) { Button("Confirm") { draft.active.toggle(); save() } }
        }
    }
    private func save() {
        if !existing { if store.addCustomer(draft) { dismiss() }; return }
        let updated = draft
        let saved = store.transaction(entityID: updated.id, action: "Customer updated", { state in
            try store.require(.manageCustomers)
            guard !updated.name.isEmpty else { throw DomainError.invalid("Enter a customer name.") }
            if let index = state.customers.firstIndex(where: { $0.id == updated.id }) { state.customers[index] = updated }
        })
        if saved { dismiss() }
    }
}
