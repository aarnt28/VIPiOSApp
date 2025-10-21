import SwiftUI

struct ActiveView: View {
    @EnvironmentObject var api: APIClient
    
    @State private var active: [Ticket] = []
    @State private var clients: [ClientRecord] = []
    @State private var newClientKey: String = ""
    @State private var newType: EntryType = .time
    @State private var loading = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            VStack {
                // Start new
                Form {
                    Section("Start New") {
                        Picker("Type", selection: $newType) {
                            ForEach(EntryType.allCases) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        Picker("Client", selection: $newClientKey) {
                            ForEach(clients, id: \.client_key) { c in
                                Text(c.name).tag(c.client_key)
                            }
                        }
                        Button("Start") { Task { await startNew() } }
                            .disabled(newClientKey.isEmpty)
                    }
                }
                .frame(maxHeight: 260)
                
                // Active list
                List {
                    ForEach(active) { t in
                        NavigationLink {
                            TicketDetailView(
                                ticket: t,
                                onUpdate: { updated in
                                    if let idx = active.firstIndex(where: { $0.id == updated.id }) {
                                        active[idx] = updated
                                    }
                                },
                                onDelete: { Task { await delete(t) } }
                            )
                        } label: {
                            ActiveTicketRow(t: t)
                        }
                    }
                }
                .overlay { if loading { ProgressView() } }
            }
            .navigationTitle("Active")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await initialLoad() }
        }
    }
    
    // MARK: - Data
    
    private func initialLoad() async {
        do {
            self.clients = try await api.fetchClientsFlat()
            if let first = clients.first { newClientKey = first.client_key }
        } catch {
            self.error = error.localizedDescription
        }
        await load()
    }
    
    private func load() async {
        loading = true; defer { loading = false }
        do { active = try await api.listActiveTickets() }
        catch { self.error = error.localizedDescription }
    }
    
    private func startNew() async {
        do {
            _ = try await api.startNew(clientKey: newClientKey, type: newType)
            await load()
        } catch { self.error = error.localizedDescription }
    }
    
    private func delete(_ t: Ticket) async {
        do { try await api.deleteTicket(id: t.id); await load() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Row only for Active list
private struct ActiveTicketRow: View {
    let t: Ticket
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t.client ?? t.client_key).font(.headline)
                Spacer()
                Text(t.entry_type.rawValue.uppercased())
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.thinMaterial))
            }
            if let note = t.note, !note.isEmpty {
                Text(note).lineLimit(2).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if t.end_iso == nil {
                    Label("Running", systemImage: "play.fill").foregroundColor(.green)
                } else {
                    Label("Stopped", systemImage: "pause.fill").foregroundColor(.secondary)
                }
                if let mins = t.rounded_minutes ?? t.minutes {
                    Label("\(mins) min", systemImage: "clock")
                }
                if t.sent { Label("Sent", systemImage: "paperplane.fill") }
                if t.completed { Label("Done", systemImage: "checkmark.seal.fill") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
