import Foundation

public enum Role: String, Codable, CaseIterable, Sendable {
    case admin, manager, field
    public var title: String { rawValue.capitalized }
}
public enum Permission: String, Codable, CaseIterable, Sendable {
    case manageCustomers, manageProperties, manageCrews, dispatch, reviewVisits, reviewBilling, finalizeStorm
}
public struct Operator: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var role: Role
    public var crewID: UUID?
    public var grants: Set<Permission> = []
    public func allows(_ permission: Permission) -> Bool { role == .admin || (role == .manager && grants.contains(permission)) }
    public init(name: String, role: Role, crewID: UUID? = nil, grants: Set<Permission> = []) {
        self.name = name; self.role = role; self.crewID = crewID; self.grants = grants
    }
}
public struct Customer: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var contact = ""
    public var phone = ""
    public var email = ""
    public var billingNotes = ""
    public var notes = ""
    public var active = true
    public init(name: String) { self.name = name }
}
public struct Crew: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var employeeIDs: [UUID] = []
    public var equipment = ""
    public init(name: String, equipment: String = "") { self.name = name; self.equipment = equipment }
}
public enum PricingMethod: String, Codable, CaseIterable, Sendable {
    case perPush, perVisit, perInch, snowfallTier, hourly, perApplication, seasonal, manual
    public var title: String {
        switch self {
        case .perPush: "Per push"
        case .perVisit: "Per visit"
        case .perInch: "Per inch"
        case .snowfallTier: "Snowfall tier"
        case .hourly: "Hourly"
        case .perApplication: "Per application"
        case .seasonal: "Seasonal (included)"
        case .manual: "Manual review"
        }
    }
}
/// Half-open intervals [lower, upper). An absent upper bound is open-ended.
public struct SnowTier: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var lower: Decimal
    public var upper: Decimal?
    public var amount: Decimal
    public var additionalInchRate: Decimal?
    public init(lower: Decimal, upper: Decimal?, amount: Decimal, additionalInchRate: Decimal? = nil) {
        self.lower = lower; self.upper = upper; self.amount = amount; self.additionalInchRate = additionalInchRate
    }
    public var label: String { "\(lower)–\(upper.map { "\($0)" } ?? "∞") in" }
}
public struct PropertyService: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var active = true
    public var trigger: Decimal = 0
    public var method: PricingMethod
    public var rate: Decimal
    public var tiers: [SnowTier] = []
    public var instructions = ""
    public var photoRequired = false
    public init(name: String, method: PricingMethod, rate: Decimal, trigger: Decimal = 0, tiers: [SnowTier] = []) {
        self.name = name; self.method = method; self.rate = rate; self.trigger = trigger; self.tiers = tiers
    }
}
public enum ChecklistKind: String, Codable, CaseIterable, Sendable { case checkbox, yesNo, number, text, photo, confirmation }
public struct ChecklistItem: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var required: Bool
    public var kind: ChecklistKind
    public init(_ title: String, required: Bool = true, kind: ChecklistKind = .checkbox) {
        self.title = title; self.required = required; self.kind = kind
    }
}
public struct ChecklistTemplate: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var items: [ChecklistItem]
    public init(name: String, items: [ChecklistItem]) { self.name = name; self.items = items }
}
public struct Property: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var customerID: UUID
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public var type = "Commercial"
    public var instructions = ""
    public var access = ""
    public var hazards = ""
    public var notes = ""
    public var priority = 1
    public var active = true
    public var services: [PropertyService] = []
    public var checklist: [ChecklistItem] = []
    public var defaultCrewID: UUID?
    public init(customerID: UUID, name: String, address: String, latitude: Double, longitude: Double) {
        self.customerID = customerID; self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude
    }
}
public enum StormStatus: String, Codable, CaseIterable, Sendable { case preparing, active, wrappingUp, underReview, finalized
    public var title: String {
        switch self { case .preparing: "Preparing"; case .active: "Active"; case .wrappingUp: "Wrapping up"; case .underReview: "Under review"; case .finalized: "Finalized" }
    }
}
public struct Storm: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var start = Date()
    public var end: Date?
    public var status: StormStatus = .preparing
    public var forecastLow: Decimal = 0
    public var forecastHigh: Decimal = 0
    public var operationalSnowfall: Decimal = 0
    public var finalSnowfall: Decimal?
    public var notes = ""
    public init(name: String) { self.name = name }
}
public enum AssignmentStatus: String, Codable, CaseIterable, Sendable { case pending, inProgress, completed, attention, skipped
    public var title: String {
        switch self { case .pending: "Not started"; case .inProgress: "In progress"; case .completed: "Completed"; case .attention: "Needs attention"; case .skipped: "Skipped" }
    }
}
public struct Assignment: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var stormID: UUID
    public var propertyID: UUID
    public var crewID: UUID
    public var order: Int
    public var status: AssignmentStatus = .pending
    public var exceptionReason = ""
    public init(stormID: UUID, propertyID: UUID, crewID: UUID, order: Int) {
        self.stormID = stormID; self.propertyID = propertyID; self.crewID = crewID; self.order = order
    }
}
public struct ChecklistResponse: Codable, Sendable {
    public var item: ChecklistItem
    public var checked = false
    public var value = ""
    public var photoID: UUID?
    public var satisfied: Bool {
        switch item.kind {
        case .checkbox, .confirmation: checked
        case .yesNo: value == "Yes" || value == "No"
        case .number: Decimal(string: value) != nil
        case .text: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo: photoID != nil
        }
    }
    public init(item: ChecklistItem) { self.item = item }
}
public struct VisitService: Identifiable, Codable, Sendable {
    public var id = UUID()
    /// Snapshot of the contracted configuration at arrival; later property edits cannot rewrite history.
    public var configuration: PropertyService
    public var performed = true
    public var quantity: Decimal = 1
    public init(configuration: PropertyService) { self.configuration = configuration }
}
public struct MaterialUsage: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var quantity: Decimal
    public var unit: String
    public init(name: String, quantity: Decimal, unit: String) { self.name = name; self.quantity = quantity; self.unit = unit }
}
public struct PhotoRecord: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var relativePath: String
    public var createdAt = Date()
    public init(relativePath: String) { self.relativePath = relativePath }
}
public struct Visit: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var assignmentID: UUID
    public var stormID: UUID
    public var propertyID: UUID
    public var customerID: UUID
    public var crewID: UUID
    public var employeeIDs: [UUID]
    public var arrival: Date
    public var departure: Date?
    public var createdAt: Date
    public var editedAt: Date
    public var editedBy: UUID
    public var services: [VisitService]
    public var checklist: [ChecklistResponse]
    public var materials: [MaterialUsage] = []
    public var photos: [PhotoRecord] = []
    public var notes = ""
    public var managerNotes = ""
    public var overrideReason = ""
    public var canceled = false
    public var billable = true
    public var latitude: Double?
    public var longitude: Double?
    public init(assignment: Assignment, property: Property, employees: [UUID], actor: UUID, now: Date = Date()) {
        assignmentID = assignment.id; stormID = assignment.stormID; propertyID = property.id; customerID = property.customerID
        crewID = assignment.crewID; employeeIDs = employees; arrival = now; createdAt = now; editedAt = now; editedBy = actor
        services = property.services.filter(\.active).map(VisitService.init)
        checklist = property.checklist.map(ChecklistResponse.init)
    }
    public var hours: Decimal { Decimal(max(0, (departure ?? Date()).timeIntervalSince(arrival)) / 3600) }
}
public enum Severity: String, Codable, CaseIterable, Sendable { case normal, high, critical }
public struct Issue: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var stormID: UUID
    public var propertyID: UUID
    public var category: String
    public var note: String
    public var severity: Severity
    public var createdBy: UUID
    public var createdAt = Date()
    public var resolved = false
    public init(stormID: UUID, propertyID: UUID, category: String, note: String, severity: Severity, createdBy: UUID) {
        self.stormID = stormID; self.propertyID = propertyID; self.category = category; self.note = note; self.severity = severity; self.createdBy = createdBy
    }
}
public struct BillingRecord: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var stormID: UUID
    public var propertyID: UUID
    public var calculated: Decimal
    public var override: Decimal?
    public var reason = ""
    public var needsReview = true
    public var entered = false
    public var final: Decimal { override ?? calculated }
    public init(stormID: UUID, propertyID: UUID, calculated: Decimal) { self.stormID = stormID; self.propertyID = propertyID; self.calculated = calculated }
}
public struct AuditEvent: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var entityID: UUID
    public var actorID: UUID
    public var action: String
    public var reason: String
    public var before: Data
    public var after: Data
    public var timestamp = Date()
    public init(entityID: UUID, actorID: UUID, action: String, reason: String, before: Data, after: Data) {
        self.entityID = entityID; self.actorID = actorID; self.action = action; self.reason = reason; self.before = before; self.after = after
    }
}
public struct Workspace: Codable, Sendable {
    public var schemaVersion = 1
    public var customers: [Customer] = []
    public var properties: [Property] = []
    public var crews: [Crew] = []
    public var employees: [Operator] = []
    public var templates: [ChecklistTemplate] = []
    public var storms: [Storm] = []
    public var assignments: [Assignment] = []
    public var visits: [Visit] = []
    public var issues: [Issue] = []
    public var billing: [BillingRecord] = []
    public var audit: [AuditEvent] = []
    public init() {}
}
