import XCTest
@testable import SnowOpsCore

final class PricingTests: XCTestCase {
    private func visit(_ service: PropertyService) -> Visit {
        let state = Seed.workspace()
        var property = state.properties[0]; property.services = [service]
        var visit = Visit(assignment: state.assignments[0], property: property, employees: [], actor: state.employees[0].id, now: Date(timeIntervalSince1970: 0))
        visit.departure = Date(timeIntervalSince1970: 5400)
        return visit
    }
    func testTierBoundaryUsesNextTierWithoutGap() throws {
        let service = PropertyService(name: "Plow", method: .snowfallTier, rate: 0, tiers: [SnowTier(lower: 0, upper: 6, amount: 400), SnowTier(lower: 6, upper: nil, amount: 650)])
        XCTAssertEqual(try PricingEngine.total(visits: [visit(service)], snowfall: Decimal(string: "5.999")!), 400)
        XCTAssertEqual(try PricingEngine.total(visits: [visit(service)], snowfall: 6), 650)
    }
    func testMultipleVisitsChargeIndependently() throws {
        let service = PropertyService(name: "Plow", method: .perPush, rate: 325)
        XCTAssertEqual(try PricingEngine.total(visits: [visit(service), visit(service)], snowfall: 5), 650)
    }
    func testAdditionalInchesAndMoneyRounding() throws {
        let service = PropertyService(name: "Plow", method: .snowfallTier, rate: 0, tiers: [SnowTier(lower: 12, upper: nil, amount: 825, additionalInchRate: 80)])
        XCTAssertEqual(try PricingEngine.total(visits: [visit(service)], snowfall: Decimal(string: "13.25")!), 925)
        XCTAssertEqual(PricingEngine.money(Decimal(string: "1.005")!), Decimal(string: "1.01")!)
    }
    func testHourlyUsesRecordedDuration() throws {
        let service = PropertyService(name: "Loader", method: .hourly, rate: 200)
        XCTAssertEqual(try PricingEngine.total(visits: [visit(service)], snowfall: 0), 300)
    }
    func testIncompleteCanceledAndNonbillableVisitsAreExcluded() throws {
        let service = PropertyService(name: "Salt", method: .perApplication, rate: 100)
        var incomplete = visit(service); incomplete.departure = nil
        var canceled = visit(service); canceled.canceled = true
        var nonbillable = visit(service); nonbillable.billable = false
        XCTAssertEqual(try PricingEngine.total(visits: [incomplete, canceled, nonbillable], snowfall: 0), 0)
    }
    func testMissingTierNeverSilentlyChargesZero() {
        let service = PropertyService(name: "Plow", method: .snowfallTier, rate: 0, tiers: [SnowTier(lower: 3, upper: 6, amount: 400)])
        XCTAssertThrowsError(try PricingEngine.total(visits: [visit(service)], snowfall: 7))
    }
    func testOverlappingTiersRejected() {
        let service = PropertyService(name: "Plow", method: .snowfallTier, rate: 0, tiers: [SnowTier(lower: 0, upper: 6, amount: 400), SnowTier(lower: 5, upper: nil, amount: 650)])
        XCTAssertThrowsError(try PricingEngine.validate(service))
    }
    func testManualPricingRequiresReview() {
        XCTAssertThrowsError(try PricingEngine.total(visits: [visit(PropertyService(name: "Custom", method: .manual, rate: 0))], snowfall: 0))
    }
    func testServiceSnapshotsSurvivePropertyEdits() {
        let service = PropertyService(name: "Plow", method: .perPush, rate: 325)
        let record = visit(service)
        var edited = service; edited.rate = 900
        XCTAssertEqual(record.services[0].configuration.rate, 325)
        XCTAssertEqual(edited.rate, 900)
    }
    func testChecklistFalseZeroAndNoAreValidAnswers() {
        var yesNo = ChecklistResponse(item: ChecklistItem("Blocked?", kind: .yesNo)); yesNo.value = "No"
        var number = ChecklistResponse(item: ChecklistItem("Bags used", kind: .number)); number.value = "0"
        XCTAssertTrue(yesNo.satisfied); XCTAssertTrue(number.satisfied)
        number.value = "not a number"; XCTAssertFalse(number.satisfied)
    }
    func testRequiredPhotoBlocksCompletion() {
        var service = PropertyService(name: "Salt", method: .perApplication, rate: 100); service.photoRequired = true
        XCTAssertTrue(Validation.completionProblems(visit(service)).contains("A service photo is required"))
    }
    func testFinalizationRejectsUnaccountedStopsAndSnowfall() {
        let state = Seed.workspace()
        let problems = Validation.finalizationProblems(state, storm: state.storms[0])
        XCTAssertTrue(problems.contains("Verify final snowfall"))
        XCTAssertTrue(problems.contains("Account for every dispatched property"))
    }
    func testCSVQuotesAndNeutralizesFormulaInjection() {
        XCTAssertEqual(BillingExport.escape("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"")
        XCTAssertEqual(BillingExport.escape("Office, North\nEntry"), "\"Office, North\nEntry\"")
        XCTAssertEqual(BillingExport.escape("  @SUM(A1)"), "\"'  @SUM(A1)\"")
    }
    func testWorkspaceRoundTripPreservesIDsAndDecimalRates() throws {
        let original = Seed.workspace()
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.properties[0].id, original.properties[0].id)
        XCTAssertEqual(decoded.properties[0].services[0].tiers[1].amount, 475)
        XCTAssertEqual(decoded.visits[0].createdAt, original.visits[0].createdAt)
    }
}
