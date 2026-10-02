import XCTest
import SnowOpsCore
@testable import SnowOps

@MainActor final class OperationsStoreTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private func store() throws -> OperationsStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try OperationsStore(repository: LocalRepository(directory: directory))
    }
    func testOfflineVisitIsDurableAcrossRestart() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try store()
        store.actorID = store.state.employees[2].id
        let assignment = store.state.assignments.first { $0.crewID == store.actor.crewID && $0.status == .pending }!
        let id = try XCTUnwrap(store.start(assignment))
        var visit = try XCTUnwrap(store.visit(id))
        for index in visit.checklist.indices { visit.checklist[index].checked = true }
        visit.notes = "North entrance inspected"
        XCTAssertTrue(store.saveVisit(visit, complete: true))
        let reopened = try self.store()
        XCTAssertNotNil(reopened.visit(id)?.departure)
        XCTAssertEqual(reopened.visit(id)?.notes, "North entrance inspected")
        XCTAssertEqual(reopened.outbox.count, 2)
    }
    func testDuplicateStartReturnsSameVisit() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try store()
        let assignment = store.state.assignments.first { $0.status == .pending }!
        let first = store.start(assignment)
        XCTAssertEqual(store.start(assignment), first)
        XCTAssertEqual(store.state.visits.filter { $0.assignmentID == assignment.id }.count, 1)
    }
    func testFieldCannotChangeDispatch() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try store(); store.actorID = store.state.employees[2].id
        XCTAssertFalse(store.reassign(store.state.assignments[3], crewID: store.state.crews[1].id))
        XCTAssertEqual(store.state.assignments[3].crewID, store.state.crews[0].id)
    }
    func testSnowfallRecalculationPreservesManualOverride() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try store(); let id = store.state.storms[0].id
        XCTAssertTrue(store.setStatus(stormID: id, status: .wrappingUp))
        XCTAssertTrue(store.setStatus(stormID: id, status: .underReview))
        XCTAssertTrue(store.recalculate(stormID: id, snowfall: 5))
        let first = store.state.billing.first { $0.propertyID == store.state.properties[0].id }!
        XCTAssertTrue(store.reviewBilling(first, override: 1350, reason: "Extra cleanup agreed with customer"))
        XCTAssertTrue(store.recalculate(stormID: id, snowfall: 7))
        let updated = store.state.billing.first { $0.id == first.id }!
        XCTAssertEqual(updated.override, 1350)
        XCTAssertNotEqual(updated.calculated, first.calculated)
        XCTAssertTrue(updated.needsReview)
    }
    func testFailedSaveDoesNotPublishChanges() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try store()
        let previous = store.state.customers.count
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(store.addCustomer(Customer(name: "Cannot persist")))
        XCTAssertEqual(store.state.customers.count, previous)
        XCTAssertTrue(store.outbox.isEmpty)
    }
}
