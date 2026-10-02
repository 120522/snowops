import SwiftUI

@main struct SnowOpsApp: App {
    @State private var store: OperationsStore?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store { RootView().environment(store) }
                else if let startupError {
                    ContentUnavailableView("Local data could not be opened", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError + "\nYour saved data has been preserved. No reset was performed."))
                } else { ProgressView("Opening Snow Ops…") }
            }
            .task {
                guard store == nil, startupError == nil else { return }
                do { store = try OperationsStore(repository: LocalRepository()) }
                catch { startupError = error.localizedDescription }
            }
        }
    }
}
