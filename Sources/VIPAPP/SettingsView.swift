import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var api: APIClient
    @State private var tmpURL: String = ""
    @State private var tmpKey: String = ""
    @State private var info: String?
    
    var body: some View {
        Form {
            Section("Server") {
                TextField("Base URL (https://…)", text: $tmpURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("X-API-Key", text: $tmpKey)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                Button("Apply") {
                    api.baseURL = tmpURL
                    api.apiKey = tmpKey
                    info = "Updated."
                }
            }
            if let info { Section { Text(info).foregroundStyle(.secondary) } }
            Section("Tips") {
                Text("Use your public HTTPS host (Cloudflare proxy, Full-Strict). Example: https://tracker.turnernet.co\nOn iPad, localhost won’t work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            tmpURL = api.baseURL
            tmpKey = api.apiKey
        }
    }
}
