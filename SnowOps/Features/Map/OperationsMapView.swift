import SwiftUI
import MapKit
import SnowOpsCore

struct OperationsMapView: View {
    @Environment(OperationsStore.self) private var store
    var stormID: UUID?
    @State private var selection: UUID?
    @State private var camera: MapCameraPosition = .automatic
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let storm = stormID.flatMap(store.storm) ?? store.activeStorm
        let assignments = storm.map { store.route(stormID: $0.id, crewID: store.isAdminInterface ? nil : store.actor.crewID) } ?? []
        Map(position: $camera, selection: $selection) {
            ForEach(assignments) { assignment in
                if let property = store.property(assignment.propertyID) {
                    Marker(property.name, systemImage: assignment.status.symbol, coordinate: CLLocationCoordinate2D(latitude: property.latitude, longitude: property.longitude))
                        .tint(assignment.status.color).tag(assignment.id)
                }
            }
        }.mapControls { MapCompass(); MapScaleView() }.mapStyle(.standard(elevation: .realistic))
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Label("\(assignments.filter { $0.status == .completed }.count)/\(assignments.count) complete", systemImage: "checkmark.circle")
                    Button("Fit route", systemImage: "arrow.up.left.and.arrow.down.right") { camera = .automatic }
                        .frame(minHeight: 44)
                }.font(.subheadline.weight(.medium)).padding(.horizontal, 16)
                    .modifier(MapControlMaterial(opaque: reduceTransparency)).padding()
            }
            .navigationTitle("Operations map").navigationBarTitleDisplayMode(.inline)
            .overlay { if assignments.isEmpty { ContentUnavailableView("No dispatched properties", systemImage: "map", description: Text("Active storm assignments appear here.")) } }
            .sheet(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
                if let id = selection { NavigationStack { AssignmentDetailView(assignmentID: id) }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
            }
    }
}
private struct MapControlMaterial: ViewModifier {
    let opaque: Bool
    func body(content: Content) -> some View {
        if opaque { content.background(Color(uiColor: .systemBackground), in: Capsule()) }
        else { content.glassEffect(.regular.interactive(), in: Capsule()) }
    }
}
