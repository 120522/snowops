import Foundation

public enum Seed {
    public static func workspace() -> Workspace {
        var state = Workspace()
        let names = ["Snow 1", "Snow 2", "Sidewalk 1"]
        state.crews = names.map { Crew(name: $0, equipment: $0 == "Sidewalk 1" ? "Sidewalk machine · calcium spreader" : "F-350 · 8 ft plow · salt spreader") }
        state.employees = [Operator(name: "Alex Morgan", role: .admin),
                           Operator(name: "Jordan Lee", role: .manager, grants: [.dispatch, .manageCrews, .reviewVisits]),
                           Operator(name: "Cameron Davis", role: .field, crewID: state.crews[0].id),
                           Operator(name: "Sam Rivera", role: .field, crewID: state.crews[1].id),
                           Operator(name: "Taylor Brooks", role: .field, crewID: state.crews[2].id)]
        for index in state.crews.indices { state.crews[index].employeeIDs = [state.employees[index + 2].id] }
        state.customers = [Customer(name: "Lehigh Valley Medical"), Customer(name: "Northside Property Group"), Customer(name: "Bethlehem Commerce")]
        let checklist = [ChecklistItem("Main lot cleared"), ChecklistItem("Fire lane accessible"), ChecklistItem("Entrances and sidewalks cleared"), ChecklistItem("Salt applied"), ChecklistItem("Final inspection complete")]
        state.templates = [ChecklistTemplate(name: "Commercial final pass", items: checklist)]
        let locations: [(String, String, Double, Double)] = [
            ("St. Luke’s Building", "801 Ostrum Street, Bethlehem, PA", 40.6084, -75.4057),
            ("Northside Commons", "1200 Main Street, Bethlehem, PA", 40.6285, -75.3820),
            ("ABC Warehouse", "1600 Union Boulevard, Allentown, PA", 40.6250, -75.4350),
            ("Riverwalk Offices", "101 River Street, Bethlehem, PA", 40.6150, -75.3780),
            ("Cedar Medical Center", "410 Cedar Crest Boulevard, Allentown, PA", 40.5920, -75.5190),
            ("Westgate Plaza", "2285 Schoenersville Road, Bethlehem, PA", 40.6450, -75.4030),
            ("Oak Terrace", "700 Linden Street, Bethlehem, PA", 40.6230, -75.3670),
            ("Commerce Park", "2200 Avenue A, Bethlehem, PA", 40.6640, -75.4230),
            ("Southside Market", "315 East 3rd Street, Bethlehem, PA", 40.6110, -75.3710),
            ("Hanover Logistics", "5000 Hanoverville Road, Bethlehem, PA", 40.6860, -75.3900)
        ]
        for (index, location) in locations.enumerated() {
            var property = Property(customerID: state.customers[index % 3].id, name: location.0, address: location.1, latitude: location.2, longitude: location.3)
            property.instructions = "Push snow to the north perimeter. Keep all entrances and fire lanes open. Finish with salt."
            property.access = "Use the service entrance. Gate remains open during storms."
            property.hazards = index % 3 == 0 ? "Raised drain at south entrance. Do not stack snow near hydrants." : "Watch for parked vehicles and pedestrian traffic."
            property.defaultCrewID = state.crews[index % 3].id
            property.checklist = checklist
            let tiers = [SnowTier(lower: 0, upper: 3, amount: 250), SnowTier(lower: 3, upper: 6, amount: 475),
                         SnowTier(lower: 6, upper: 9, amount: 650), SnowTier(lower: 9, upper: 12, amount: 825),
                         SnowTier(lower: 12, upper: nil, amount: 825, additionalInchRate: 80)]
            property.services = [PropertyService(name: "Snow plowing", method: index % 2 == 0 ? .snowfallTier : .perPush, rate: 325, trigger: 1, tiers: tiers),
                                 PropertyService(name: "Sidewalk clearing", method: .perVisit, rate: 110),
                                 PropertyService(name: "Lot salt", method: .perApplication, rate: 180)]
            state.properties.append(property)
        }
        var storm = Storm(name: "February 6 Snow Event")
        storm.status = .active; storm.forecastLow = 4; storm.forecastHigh = 7; storm.operationalSnowfall = Decimal(string: "5.8")!
        storm.start = ISO8601DateFormatter().date(from: "2026-02-06T02:00:00Z")!
        state.storms = [storm]
        for (index, property) in state.properties.enumerated() {
            var assignment = Assignment(stormID: storm.id, propertyID: property.id, crewID: property.defaultCrewID!, order: index)
            if index < 3 {
                assignment.status = .completed
                var visit = Visit(assignment: assignment, property: property, employees: state.crews[index].employeeIDs, actor: state.employees[index + 2].id, now: storm.start.addingTimeInterval(Double(index) * 3600))
                visit.departure = visit.arrival.addingTimeInterval(2700)
                for item in visit.checklist.indices { visit.checklist[item].checked = true }
                visit.materials = [MaterialUsage(name: "Rock salt", quantity: 300, unit: "lb")]
                state.visits.append(visit)
            }
            state.assignments.append(assignment)
        }
        return state
    }
}
