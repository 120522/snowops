import Foundation

public enum DomainError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { message } else { nil } }
}
public struct PricingLine: Sendable {
    public var visitID: UUID
    public var service: String
    public var quantity: Decimal
    public var rate: Decimal
    public var amount: Decimal
    public var explanation: String
}
public enum PricingEngine {
    public static func money(_ value: Decimal) -> Decimal {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
    public static func validate(_ service: PropertyService) throws {
        guard service.rate >= 0, service.trigger >= 0 else { throw DomainError.invalid("Rates and triggers cannot be negative.") }
        guard service.method == .snowfallTier else { return }
        let tiers = service.tiers.sorted { $0.lower < $1.lower }
        guard !tiers.isEmpty else { throw DomainError.invalid("Add at least one snowfall tier.") }
        for (index, tier) in tiers.enumerated() {
            guard tier.lower >= 0, tier.amount >= 0, (tier.additionalInchRate ?? 0) >= 0,
                  tier.upper == nil || tier.upper! > tier.lower else { throw DomainError.invalid("Invalid snowfall tier.") }
            if index > 0 {
                guard let previousUpper = tiers[index - 1].upper, previousUpper <= tier.lower else {
                    throw DomainError.invalid("Snowfall tiers overlap.")
                }
            }
        }
    }
    public static func lines(visits: [Visit], snowfall: Decimal) throws -> [PricingLine] {
        guard snowfall >= 0 else { throw DomainError.invalid("Snowfall cannot be negative.") }
        var result: [PricingLine] = []
        for visit in visits where !visit.canceled && visit.billable && visit.departure != nil {
            for performed in visit.services where performed.performed {
                let service = performed.configuration
                try validate(service)
                guard performed.quantity >= 0 else { throw DomainError.invalid("Quantities cannot be negative.") }
                var quantity = performed.quantity, rate = service.rate, explanation = service.method.title
                switch service.method {
                case .perPush, .perVisit, .perApplication: break
                case .hourly: quantity = visit.hours
                case .perInch: quantity = snowfall * performed.quantity
                case .seasonal: rate = 0; explanation = "Included in seasonal contract"
                case .manual: throw DomainError.invalid("\(service.name) requires a manual rate before billing can be reviewed.")
                case .snowfallTier:
                    guard let tier = service.tiers.first(where: { snowfall >= $0.lower && ($0.upper == nil || snowfall < $0.upper!) }) else {
                        throw DomainError.invalid("No \(service.name) pricing tier covers \(snowfall) inches.")
                    }
                    rate = tier.amount + max(0, snowfall - tier.lower) * (tier.additionalInchRate ?? 0)
                    explanation = "\(tier.label) · per performed visit"
                }
                result.append(PricingLine(visitID: visit.id, service: service.name, quantity: quantity, rate: rate,
                                          amount: money(quantity * rate), explanation: explanation))
            }
        }
        return result
    }
    public static func total(visits: [Visit], snowfall: Decimal) throws -> Decimal {
        try lines(visits: visits, snowfall: snowfall).reduce(Decimal(0)) { $0 + $1.amount }
    }
}
public enum Validation {
    public static func completionProblems(_ visit: Visit) -> [String] {
        var problems = visit.checklist.filter { $0.item.required && !$0.satisfied }.map { $0.item.title }
        if visit.services.contains(where: { $0.performed && $0.configuration.photoRequired }) && visit.photos.isEmpty {
            problems.append("A service photo is required")
        }
        if !visit.services.contains(where: \.performed) { problems.append("Select at least one performed service") }
        if visit.services.contains(where: { $0.quantity < 0 }) || visit.materials.contains(where: { $0.quantity < 0 }) {
            problems.append("Quantities cannot be negative")
        }
        return problems
    }
    public static func finalizationProblems(_ state: Workspace, storm: Storm) -> [String] {
        var problems: [String] = []
        if storm.status != .underReview { problems.append("Move the storm into review") }
        if storm.finalSnowfall == nil { problems.append("Verify final snowfall") }
        let assignments = state.assignments.filter { $0.stormID == storm.id }
        if assignments.isEmpty { problems.append("No dispatched properties") }
        if assignments.contains(where: { $0.status != .completed && !($0.status == .skipped && !$0.exceptionReason.isEmpty) }) {
            problems.append("Account for every dispatched property")
        }
        let visits = state.visits.filter { $0.stormID == storm.id && !$0.canceled }
        if visits.contains(where: { $0.departure == nil }) { problems.append("Review incomplete visits") }
        if visits.contains(where: { !completionProblems($0).isEmpty && $0.overrideReason.isEmpty }) { problems.append("Review incomplete checklists") }
        if state.issues.contains(where: { $0.stormID == storm.id && !$0.resolved }) { problems.append("Resolve outstanding issues") }
        for assignment in assignments where assignment.status == .completed {
            if !visits.contains(where: { $0.assignmentID == assignment.id && $0.departure != nil }) { problems.append("Completed stop has no completed visit") }
            if !state.billing.contains(where: { $0.stormID == storm.id && $0.propertyID == assignment.propertyID && !$0.needsReview }) {
                problems.append("Review billing for every serviced property")
            }
        }
        if state.billing.contains(where: { $0.stormID == storm.id && $0.override != nil && $0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            problems.append("Document billing adjustment reasons")
        }
        if let snowfall = storm.finalSnowfall {
            for record in state.billing where record.stormID == storm.id {
                do {
                    let calculated = try PricingEngine.total(visits: visits.filter { $0.propertyID == record.propertyID }, snowfall: snowfall)
                    if calculated != record.calculated { problems.append("Recalculate changed service records") }
                } catch { problems.append("Resolve invalid pricing: \(error.localizedDescription)") }
            }
        }
        return Array(Set(problems)).sorted()
    }
}
