import SwiftUI

@main
struct TimeTrackerPlaygroundApp: App {
    @StateObject private var api = APIClient()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
        }
    }
}
