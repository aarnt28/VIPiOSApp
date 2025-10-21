import SwiftUI

struct ClientsView: View {
    @EnvironmentObject var api: APIClient
    @State private var clients: [ClientRecord] = []
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            List(clients) { record in
                VStack(alignment: .leading) {
                    Text(record.name).font(.headline)
                    Text(record.client_key).font(.caption).foregroundStyle(.secondary)
                    if let attrs = record.attributes, !attrs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(attrs.keys.sorted(), id: \.self) { k in
                                    if k != "name", let v = attrs[k] {
                                        Text("\(k): \(v)")
                                            .font(.caption2)
                                            .padding(6)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clients")
            .task { await load() }
            .overlay {
                if clients.isEmpty && error == nil { ProgressView() }
                if let e = error { Text(e).foregroundStyle(.red) }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }
    
    private func load() async {
        do {
            clients = try await api.fetchClientsFlat()
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
