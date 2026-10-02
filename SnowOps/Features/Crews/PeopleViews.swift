import SwiftUI
import SnowOpsCore

struct CrewsView: View {
    @Environment(OperationsStore.self) private var store
    @State private var create = false
    var body: some View {
        List(store.state.crews) { crew in
            Section(crew.name) {
                Text(crew.equipment).foregroundStyle(.secondary)
                ForEach(store.state.employees.filter { $0.crewID == crew.id }) { employee in Label(employee.name, systemImage: "person") }
                if store.state.employees.filter({ $0.crewID == crew.id }).isEmpty { Text("No employees assigned").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Crews")
            .toolbar { if store.actor.allows(.manageCrews) { Button("New crew", systemImage: "plus") { create = true } } }
            .sheet(isPresented: $create) { CrewEditorView() }
    }
}
struct CrewEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var equipment = ""
    var body: some View {
        NavigationStack { Form {
            TextField("Crew name", text: $name)
            TextField("Vehicle / equipment", text: $equipment)
            Button("Create crew") { if store.addCrew(name: name, equipment: equipment) { dismiss() } }.disabled(name.isEmpty)
        }.navigationTitle("New crew").toolbar { Button("Cancel") { dismiss() } } }.presentationDetents([.medium, .large]).interactiveDismissDisabled(!name.isEmpty)
    }
}
struct EmployeesView: View {
    @Environment(OperationsStore.self) private var store
    @State private var draft: Operator?
    var body: some View {
        List(store.state.employees) { employee in
            Button { if store.actor.allows(.manageCrews) { draft = employee } } label: {
                VStack(alignment: .leading, spacing: 5) { Text(employee.name).font(.headline).foregroundStyle(.primary); Text("\(employee.role.title) · \(employee.crewID.flatMap(store.crew)?.name ?? "No crew")").font(.subheadline).foregroundStyle(.secondary) }
            }.disabled(!store.actor.allows(.manageCrews))
        }.navigationTitle("Employees")
            .toolbar { if store.actor.role == .admin { Button("Add employee", systemImage: "plus") { draft = Operator(name: "", role: .field) } } }
            .sheet(item: $draft) { EmployeeEditorView(employee: $0) }
    }
}
struct EmployeeEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Operator
    @State private var discard = false
    init(employee: Operator) { _draft = State(initialValue: employee) }
    var body: some View {
        NavigationStack { Form {
            TextField("Employee name", text: $draft.name).disabled(store.actor.role != .admin)
            if store.actor.role == .admin { Picker("Role", selection: $draft.role) { ForEach(Role.allCases, id: \.self) { Text($0.title).tag($0) } } }
            Picker("Crew", selection: $draft.crewID) { Text("Unassigned").tag(Optional<UUID>.none); ForEach(store.state.crews) { Text($0.name).tag(Optional($0.id)) } }
            if draft.role == .manager, store.actor.role == .admin {
                Section("Manager permissions") { ForEach(Permission.allCases, id: \.self) { permission in
                    Toggle(permission.rawValue, isOn: Binding(get: { draft.grants.contains(permission) }, set: { if $0 { draft.grants.insert(permission) } else { draft.grants.remove(permission) } }))
                } }
            }
            Text("These are development identities. Production employee invitations and secure sign-in are not connected.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Employee").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(draft.name.isEmpty) }
        }.interactiveDismissDisabled()
            .confirmationDialog("Discard employee changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }
    }
    private func save() {
        let updated = draft
        let success = store.transaction(entityID: updated.id, action: "Employee assignment updated", { state in
            try store.require(.manageCrews)
            if let index = state.employees.firstIndex(where: { $0.id == updated.id }) {
                if store.actor.role != .admin, (state.employees[index].role != updated.role || state.employees[index].grants != updated.grants || state.employees[index].name != updated.name) { throw DomainError.invalid("Only an administrator can edit identity permissions.") }
                if state.visits.contains(where: { $0.departure == nil && !$0.canceled && $0.employeeIDs.contains(updated.id) }) { throw DomainError.invalid("Finish the employee’s active visit before changing crews.") }
                state.employees[index] = updated
            } else {
                guard store.actor.role == .admin else { throw DomainError.invalid("Only an administrator can add employees.") }
                state.employees.append(updated)
            }
            for index in state.crews.indices {
                state.crews[index].employeeIDs.removeAll { $0 == updated.id }
                if state.crews[index].id == updated.crewID { state.crews[index].employeeIDs.append(updated.id) }
            }
        })
        if success { dismiss() }
    }
}
struct TemplatesView: View {
    @Environment(OperationsStore.self) private var store
    @State private var draft: ChecklistTemplate?
    var body: some View {
        List(store.state.templates) { template in
            Button { draft = template } label: { VStack(alignment: .leading, spacing: 5) { Text(template.name).font(.headline); Text("\(template.items.count) items").font(.subheadline).foregroundStyle(.secondary) } }.disabled(!store.actor.allows(.manageProperties))
        }.navigationTitle("Checklists")
            .toolbar { if store.actor.allows(.manageProperties) { Button("New template", systemImage: "plus") { draft = ChecklistTemplate(name: "", items: []) } } }
            .sheet(item: $draft) { TemplateEditorView(template: $0) }
    }
}
struct TemplateEditorView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChecklistTemplate
    @State private var title = ""
    @State private var kind: ChecklistKind = .checkbox
    @State private var required = true
    @State private var discard = false
    init(template: ChecklistTemplate) { _draft = State(initialValue: template) }
    var body: some View {
        NavigationStack { Form {
            TextField("Template name", text: $draft.name)
            Section("Items") { ForEach(draft.items) { Text($0.title + ($0.required ? " *" : "")) }.onDelete { draft.items.remove(atOffsets: $0) } }
            Section("Add item") {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) { ForEach(ChecklistKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Required", isOn: $required)
                Button("Add item") { draft.items.append(ChecklistItem(title, required: required, kind: kind)); title = "" }.disabled(title.isEmpty)
            }
        }.navigationTitle("Checklist template").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(draft.name.isEmpty || draft.items.isEmpty) }
        }.interactiveDismissDisabled()
            .confirmationDialog("Discard checklist changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() } }
        }
    }
    private func save() {
        let updated = draft
        let saved = store.transaction(entityID: updated.id, action: "Checklist template saved", { state in
            try store.require(.manageProperties)
            if let index = state.templates.firstIndex(where: { $0.id == updated.id }) { state.templates[index] = updated } else { state.templates.append(updated) }
        })
        if saved { dismiss() }
    }
}
