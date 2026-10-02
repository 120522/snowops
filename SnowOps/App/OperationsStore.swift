import SwiftUI
import SnowOpsCore

@MainActor @Observable final class OperationsStore {
    private(set) var state: Workspace
    private(set) var outbox: [PendingMutation]
    var actorID: UUID
    var error: String?
    var notice: String?
    private let repository: LocalRepository
    var actor: Operator { state.employees.first { $0.id == actorID } ?? Operator(name: "Unknown", role: .field) }
    var activeStorm: Storm? { state.storms.first { $0.status == .active || $0.status == .wrappingUp } }
    var isAdminInterface: Bool { actor.role != .field }
    init(repository: LocalRepository) throws {
        self.repository = repository
        if let saved = try repository.load() { state = saved.workspace; outbox = saved.outbox }
        else {
            state = Seed.workspace(); outbox = []
            try repository.save(LocalEnvelope(workspace: state))
        }
        guard let first = state.employees.first else { throw DomainError.invalid("The saved workspace has no employee identity. Its data has been preserved.") }
        actorID = first.id
    }
    func property(_ id: UUID) -> Property? { state.properties.first { $0.id == id } }
    func storm(_ id: UUID) -> Storm? { state.storms.first { $0.id == id } }
    func crew(_ id: UUID) -> Crew? { state.crews.first { $0.id == id } }
    func customer(_ id: UUID) -> Customer? { state.customers.first { $0.id == id } }
    func visit(_ id: UUID) -> Visit? { state.visits.first { $0.id == id } }
    func route(stormID: UUID, crewID: UUID? = nil) -> [Assignment] {
        if actor.role == .field && actor.crewID == nil { return [] }
        let permittedCrew = actor.role == .field ? actor.crewID : crewID
        return state.assignments.filter { $0.stormID == stormID && (permittedCrew == nil || $0.crewID == permittedCrew) }.sorted { $0.order < $1.order }
    }
    func visits(stormID: UUID, propertyID: UUID? = nil) -> [Visit] {
        state.visits.filter { $0.stormID == stormID && (propertyID == nil || $0.propertyID == propertyID) }
    }
    func require(_ permission: Permission) throws {
        guard actor.allows(permission) else { throw DomainError.invalid("Your role does not permit this action.") }
    }
    func requireMutable(_ stormID: UUID) throws {
        guard let storm = storm(stormID), storm.status != .finalized else { throw DomainError.invalid("Finalized storm records are locked.") }
    }
    @discardableResult
    func transaction(entityID: UUID, action: String, reason: String = "", _ mutation: (inout Workspace) throws -> Void) -> Bool {
        do {
            var beforeState = state; beforeState.audit = []
            let before = try JSONEncoder().encode(beforeState)
            var next = state
            try mutation(&next)
            var afterState = next; afterState.audit = []
            let after = try JSONEncoder().encode(afterState)
            let audit = AuditEvent(entityID: entityID, actorID: actorID, action: action, reason: reason, before: before, after: after)
            next.audit.append(audit)
            var pending = outbox; pending.append(PendingMutation(auditID: audit.id))
            try repository.save(LocalEnvelope(workspace: next, outbox: pending))
            state = next; outbox = pending
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func addCustomer(_ customer: Customer) -> Bool {
        transaction(entityID: customer.id, action: "Customer created") { state in
            try require(.manageCustomers)
            guard !customer.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.invalid("Enter a customer name.") }
            state.customers.append(customer)
        }
    }
    func saveProperty(_ property: Property) -> Bool {
        transaction(entityID: property.id, action: "Property configuration saved") { state in
            try require(.manageProperties)
            guard !property.name.isEmpty, !property.address.isEmpty, state.customers.contains(where: { $0.id == property.customerID }),
                  (-90...90).contains(property.latitude), (-180...180).contains(property.longitude) else {
                throw DomainError.invalid("A property needs a customer, name, address and valid coordinates.")
            }
            for service in property.services { try PricingEngine.validate(service) }
            if let index = state.properties.firstIndex(where: { $0.id == property.id }) { state.properties[index] = property }
            else { state.properties.append(property) }
        }
    }
    func addCrew(name: String, equipment: String) -> Bool {
        let crew = Crew(name: name, equipment: equipment)
        return transaction(entityID: crew.id, action: "Crew created") { state in
            try require(.manageCrews)
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.invalid("Enter a crew name.") }
            state.crews.append(crew)
        }
    }
    func createStorm(_ storm: Storm, selected: Set<UUID>, crewAssignments: [UUID: UUID], activate: Bool) -> Bool {
        transaction(entityID: storm.id, action: activate ? "Storm activated" : "Storm prepared") { state in
            try require(.dispatch)
            guard !storm.name.isEmpty, !selected.isEmpty, storm.forecastLow >= 0, storm.forecastHigh >= storm.forecastLow else {
                throw DomainError.invalid("Enter valid storm information and select properties.")
            }
            guard !activate || activeStorm == nil else { throw DomainError.invalid("Wrap up the current active storm first.") }
            var created = storm; created.status = activate ? .active : .preparing
            state.storms.append(created)
            for (order, property) in state.properties.filter({ selected.contains($0.id) }).enumerated() {
                guard let crewID = crewAssignments[property.id] ?? property.defaultCrewID, state.crews.contains(where: { $0.id == crewID }) else {
                    throw DomainError.invalid("Assign a crew to \(property.name).")
                }
                state.assignments.append(Assignment(stormID: storm.id, propertyID: property.id, crewID: crewID, order: order))
            }
        }
    }
    func setStatus(stormID: UUID, status: StormStatus) -> Bool {
        transaction(entityID: stormID, action: "Storm status: \(status.title)") { state in
            try require(status == .finalized ? .finalizeStorm : .dispatch); try requireMutable(stormID)
            guard let index = state.storms.firstIndex(where: { $0.id == stormID }) else { return }
            let current = state.storms[index].status
            let permitted: [StormStatus: Set<StormStatus>] = [.preparing: [.active], .active: [.wrappingUp], .wrappingUp: [.underReview], .underReview: [.finalized]]
            guard permitted[current]?.contains(status) == true else { throw DomainError.invalid("Invalid storm status transition.") }
            if status == .active, activeStorm != nil { throw DomainError.invalid("Another storm is already active.") }
            if status == .finalized {
                let problems = Validation.finalizationProblems(state, storm: state.storms[index])
                guard problems.isEmpty else { throw DomainError.invalid(problems.joined(separator: "\n")) }
            }
            state.storms[index].status = status
            if status == .underReview { state.storms[index].end = Date() }
        }
    }
    func reassign(_ assignment: Assignment, crewID: UUID) -> Bool {
        transaction(entityID: assignment.id, action: "Property reassigned") { state in
            try require(.dispatch); try requireMutable(assignment.stormID)
            guard assignment.status != .inProgress else { throw DomainError.invalid("Complete the active visit before changing crews.") }
            guard let index = state.assignments.firstIndex(where: { $0.id == assignment.id }) else { return }
            state.assignments[index].crewID = crewID
        }
    }
    func reorder(_ assignments: [Assignment], from: IndexSet, to: Int) {
        var reordered = assignments; reordered.move(fromOffsets: from, toOffset: to)
        _ = transaction(entityID: assignments.first?.stormID ?? UUID(), action: "Route reordered") { state in
            try require(.dispatch)
            if let first = assignments.first { try requireMutable(first.stormID) }
            for (position, item) in reordered.enumerated() {
                if let index = state.assignments.firstIndex(where: { $0.id == item.id }) { state.assignments[index].order = position }
            }
        }
    }
    func start(_ assignment: Assignment) -> UUID? {
        if let existing = state.visits.first(where: { $0.assignmentID == assignment.id && $0.departure == nil && !$0.canceled }), actor.allows(.dispatch) || actor.crewID == assignment.crewID { return existing.id }
        guard let property = property(assignment.propertyID) else { return nil }
        let visit = Visit(assignment: assignment, property: property, employees: crew(assignment.crewID)?.employeeIDs ?? [], actor: actorID)
        let saved = transaction(entityID: visit.id, action: "Visit started") { state in
            try requireMutable(assignment.stormID)
            guard storm(assignment.stormID)?.status == .active || storm(assignment.stormID)?.status == .wrappingUp else { throw DomainError.invalid("Field visits require an active storm.") }
            guard actor.allows(.dispatch) || actor.crewID == assignment.crewID else { throw DomainError.invalid("This property is assigned to another crew.") }
            guard !state.visits.contains(where: { $0.crewID == assignment.crewID && $0.departure == nil && !$0.canceled }) else { throw DomainError.invalid("Complete your current visit first.") }
            guard let index = state.assignments.firstIndex(where: { $0.id == assignment.id }), state.assignments[index].status != .skipped else { throw DomainError.invalid("This stop has been skipped.") }
            state.visits.append(visit); state.assignments[index].status = .inProgress
            for index in state.billing.indices where state.billing[index].stormID == assignment.stormID && state.billing[index].propertyID == assignment.propertyID { state.billing[index].needsReview = true }
        }
        return saved ? visit.id : nil
    }
    func saveVisit(_ draft: Visit, complete: Bool = false) -> Bool {
        transaction(entityID: draft.id, action: complete ? "Visit completed" : "Visit updated", reason: draft.overrideReason) { state in
            try requireMutable(draft.stormID)
            guard let index = state.visits.firstIndex(where: { $0.id == draft.id }) else { throw DomainError.invalid("Visit no longer exists.") }
            guard state.visits[index].departure == nil else { throw DomainError.invalid("Completed visits require an audited correction workflow.") }
            guard actor.allows(.reviewVisits) || actor.crewID == draft.crewID else { throw DomainError.invalid("You cannot edit another crew’s visit.") }
            let original = state.visits[index]
            guard draft.assignmentID == original.assignmentID, draft.stormID == original.stormID,
                  draft.propertyID == original.propertyID, draft.customerID == original.customerID,
                  draft.crewID == original.crewID, draft.employeeIDs == original.employeeIDs,
                  draft.arrival == original.arrival, draft.createdAt == original.createdAt else {
                throw DomainError.invalid("Visit identity and original timestamps cannot be changed by field edits.")
            }
            var updated = draft; updated.editedAt = Date(); updated.editedBy = actorID
            if complete {
                let problems = Validation.completionProblems(updated)
                if !problems.isEmpty {
                    guard actor.allows(.reviewVisits), !updated.overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw DomainError.invalid("Complete the required items:\n" + problems.joined(separator: "\n"))
                    }
                }
                updated.departure = Date()
                if let assignmentIndex = state.assignments.firstIndex(where: { $0.id == updated.assignmentID }) { state.assignments[assignmentIndex].status = .completed }
            }
            state.visits[index] = updated
        }
    }
    func correctVisit(_ draft: Visit, reason: String) -> Bool {
        transaction(entityID: draft.id, action: draft.canceled ? "Visit canceled" : "Completed visit corrected", reason: reason) { state in
            try require(.reviewVisits); try requireMutable(draft.stormID)
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let index = state.visits.firstIndex(where: { $0.id == draft.id }),
                  state.visits[index].departure != nil else { throw DomainError.invalid("A completed visit correction requires a reason.") }
            let original = state.visits[index]
            guard draft.assignmentID == original.assignmentID, draft.stormID == original.stormID,
                  draft.propertyID == original.propertyID, draft.customerID == original.customerID,
                  draft.crewID == original.crewID, draft.employeeIDs == original.employeeIDs,
                  draft.createdAt == original.createdAt,
                  let departure = draft.departure, departure >= draft.arrival else { throw DomainError.invalid("Correction contains invalid identity or timestamps.") }
            if !actor.allows(.reviewBilling) {
                guard draft.billable == original.billable,
                      try JSONEncoder().encode(draft.services.map(\.configuration)) == JSONEncoder().encode(original.services.map(\.configuration)) else {
                    throw DomainError.invalid("Billing permission is required to change rates or billable status.")
                }
            }
            for service in draft.services { try PricingEngine.validate(service.configuration) }
            if !draft.canceled, !Validation.completionProblems(draft).isEmpty, draft.overrideReason.isEmpty { throw DomainError.invalid("Document an override for incomplete required work.") }
            var updated = draft; updated.editedAt = Date(); updated.editedBy = actorID
            state.visits[index] = updated
            if updated.canceled, let assignmentIndex = state.assignments.firstIndex(where: { $0.id == updated.assignmentID }) {
                let otherCompleted = state.visits.contains { $0.assignmentID == updated.assignmentID && $0.id != updated.id && !$0.canceled && $0.departure != nil }
                if !otherCompleted { state.assignments[assignmentIndex].status = .attention }
            }
            for billingIndex in state.billing.indices where state.billing[billingIndex].stormID == updated.stormID && state.billing[billingIndex].propertyID == updated.propertyID { state.billing[billingIndex].needsReview = true }
        }
    }
    func attachPhoto(_ data: Data, visitID: UUID) -> PhotoRecord? {
        do {
            guard let visit = visit(visitID), visit.departure == nil else { throw DomainError.invalid("Photos can only be added to an active visit.") }
            guard actor.allows(.reviewVisits) || actor.crewID == visit.crewID else { throw DomainError.invalid("You cannot edit another crew’s visit.") }
            return try repository.storePhoto(data)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func photoURL(_ photo: PhotoRecord) -> URL { repository.directory.appendingPathComponent(photo.relativePath) }
    func reportIssue(_ issue: Issue) -> Bool {
        transaction(entityID: issue.id, action: "Issue reported") { state in
            try requireMutable(issue.stormID)
            guard actor.allows(.reviewVisits) || state.assignments.contains(where: { $0.stormID == issue.stormID && $0.propertyID == issue.propertyID && $0.crewID == actor.crewID }) else {
                throw DomainError.invalid("This property is not assigned to your crew.")
            }
            state.issues.append(issue)
        }
    }
    func resolveIssue(_ issue: Issue) {
        _ = transaction(entityID: issue.id, action: "Issue resolved") { state in
            try require(.reviewVisits); try requireMutable(issue.stormID)
            if let index = state.issues.firstIndex(where: { $0.id == issue.id }) { state.issues[index].resolved = true }
        }
    }
    func recalculate(stormID: UUID, snowfall: Decimal) -> Bool {
        transaction(entityID: stormID, action: "Final snowfall verified", reason: "Final snowfall \(snowfall) in") { state in
            try require(.reviewBilling); try requireMutable(stormID)
            guard snowfall >= 0, let index = state.storms.firstIndex(where: { $0.id == stormID }), state.storms[index].status == .underReview else {
                throw DomainError.invalid("Enter nonnegative snowfall while the storm is under review.")
            }
            state.storms[index].finalSnowfall = snowfall
            let propertyIDs = Set(state.assignments.filter { $0.stormID == stormID && $0.status != .skipped }.map(\.propertyID))
                .union(state.billing.filter { $0.stormID == stormID }.map(\.propertyID))
            for propertyID in propertyIDs {
                let amount = try PricingEngine.total(visits: state.visits.filter { $0.stormID == stormID && $0.propertyID == propertyID }, snowfall: snowfall)
                if let billingIndex = state.billing.firstIndex(where: { $0.stormID == stormID && $0.propertyID == propertyID }) {
                    if state.billing[billingIndex].calculated != amount { state.billing[billingIndex].needsReview = true }
                    state.billing[billingIndex].calculated = amount
                } else { state.billing.append(BillingRecord(stormID: stormID, propertyID: propertyID, calculated: amount)) }
            }
        }
    }
    func reviewBilling(_ record: BillingRecord, override: Decimal?, reason: String) -> Bool {
        transaction(entityID: record.id, action: "Billing reviewed", reason: reason) { state in
            try require(.reviewBilling); try requireMutable(record.stormID)
            guard override == nil || (override! >= 0 && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { throw DomainError.invalid("An adjustment requires a nonnegative amount and a reason.") }
            guard let index = state.billing.firstIndex(where: { $0.id == record.id }) else { return }
            guard let snowfall = storm(record.stormID)?.finalSnowfall else { throw DomainError.invalid("Verify snowfall before reviewing billing.") }
            let currentCalculation = try PricingEngine.total(visits: state.visits.filter { $0.stormID == record.stormID && $0.propertyID == record.propertyID }, snowfall: snowfall)
            guard currentCalculation == state.billing[index].calculated else { throw DomainError.invalid("Service records changed. Recalculate snowfall pricing before reviewing this amount.") }
            state.billing[index].override = override; state.billing[index].reason = reason; state.billing[index].needsReview = false
        }
    }
    func markEntered(_ record: BillingRecord) {
        _ = transaction(entityID: record.id, action: "Invoice preparation marked entered") { state in
            try require(.reviewBilling)
            guard storm(record.stormID)?.status == .finalized, !record.needsReview else { throw DomainError.invalid("Finalize the storm before marking billing entered.") }
            if let index = state.billing.firstIndex(where: { $0.id == record.id }) { state.billing[index].entered = true }
        }
    }
    func addAdditionalVisit(_ assignment: Assignment) -> Bool {
        transaction(entityID: assignment.id, action: "Additional visit dispatched") { state in
            try require(.dispatch); try requireMutable(assignment.stormID)
            guard storm(assignment.stormID)?.status == .active || storm(assignment.stormID)?.status == .wrappingUp else { throw DomainError.invalid("Additional visits require an active storm.") }
            state.assignments.append(Assignment(stormID: assignment.stormID, propertyID: assignment.propertyID, crewID: assignment.crewID, order: (state.assignments.map(\.order).max() ?? 0) + 1))
        }
    }
    func skip(_ assignment: Assignment, reason: String) -> Bool {
        transaction(entityID: assignment.id, action: "Stop accounted for without service", reason: reason) { state in
            try require(.dispatch); try requireMutable(assignment.stormID)
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, assignment.status != .inProgress, assignment.status != .completed else { throw DomainError.invalid("Provide a reason for an unstarted stop.") }
            if let index = state.assignments.firstIndex(where: { $0.id == assignment.id }) { state.assignments[index].status = .skipped; state.assignments[index].exceptionReason = reason }
        }
    }
}
