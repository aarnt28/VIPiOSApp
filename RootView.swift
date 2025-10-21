import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TicketsScreen()
                .tabItem { Label("Tickets", systemImage: "list.bullet.rectangle") }
            
            ActiveView()
                .tabItem { Label("Active", systemImage: "stopwatch") }
            
            HardwareView()
                .tabItem { Label("Hardware", systemImage: "barcode.viewfinder") }
            
            ClientsView()
                .tabItem { Label("Clients", systemImage: "person.3") }
            
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
