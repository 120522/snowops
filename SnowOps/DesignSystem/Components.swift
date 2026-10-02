import SwiftUI
import SnowOpsCore

extension Decimal {
    var currency: String { formatted(.currency(code: "USD")) }
    var inches: String { "\(self)″" }
}
extension AssignmentStatus {
    var color: Color {
        switch self { case .pending: .secondary; case .inProgress: .blue; case .completed: .green; case .attention: .orange; case .skipped: .secondary }
    }
    var symbol: String {
        switch self { case .pending: "circle"; case .inProgress: "arrow.trianglehead.2.clockwise"; case .completed: "checkmark.circle.fill"; case .attention: "exclamationmark.triangle.fill"; case .skipped: "forward.end" }
    }
}
struct StatusLabel: View {
    let status: AssignmentStatus
    var body: some View { Label(status.title, systemImage: status.symbol).font(.subheadline.weight(.medium)).foregroundStyle(status.color) }
}
struct PrimaryAction: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(disabled)
    }
}
struct SyncBanner: View {
    @Environment(OperationsStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive")
            Text(store.outbox.isEmpty ? "Development · saved on this device" : "Saved locally · \(store.outbox.count) pending changes")
            Spacer(minLength: 0)
        }.font(.caption.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 8)
            .background(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
            .accessibilityLabel("Development mode. Backend is not connected. All records are saved on this device.")
    }
}
struct PropertyRow: View {
    let property: Property
    var status: AssignmentStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(property.name).font(.headline)
            Text(property.address).font(.subheadline).foregroundStyle(.secondary)
            if let status { StatusLabel(status: status) }
            else { Text(property.services.filter(\.active).map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
}
struct Metric: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.blue)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}
