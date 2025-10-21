import SwiftUI

struct TicketsScreen: View {
    @EnvironmentObject var api: APIClient
    
    @State private var tickets: [Ticket] = []
    @State private var loading = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(tickets) { t in
                    NavigationLink {
                        TicketDetailView(
                            ticket: t,
                            onUpdate: updateLocalTicket(_:),
                            onDelete: { Task { await deleteTicket(t) } }
                        )
                    } label: {
                        TicketRow(t: t)
                    }
                }
            }
            .overlay {
                if loading { ProgressView().controlSize(.large) }
                if let e = error { Text(e).foregroundColor(.red).padding() }
            }
            .navigationTitle("Recent Tickets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await loadTickets() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await loadTickets() }
        }
    }
    
    // MARK: - Helpers
    
    private func updateLocalTicket(_ updated: Ticket) {
        if let idx = tickets.firstIndex(where: { $0.id == updated.id }) {
            tickets[idx] = updated
        }
    }
    
    private func loadTickets() async {
        self.error = nil
        loading = true
        defer { loading = false }
        do {
            tickets = try await api.listTickets()
        } catch {
            // Use self.error to avoid shadowing the 'error' in catch
            self.error = error.localizedDescription
        }
    }
    
    private func deleteTicket(_ t: Ticket) async {
        do {
            try await api.deleteTicket(id: t.id)
            await MainActor.run { tickets.removeAll { $0.id == t.id } }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Row used by Tickets list
private struct TicketRow: View {
    let t: Ticket
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t.client ?? t.client_key).font(.headline)
                Spacer()
                Text(t.entry_type.rawValue.uppercased())
                    .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.thinMaterial))
            }
            Text(t.note ?? "—").lineLimit(2).foregroundColor(.secondary)
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
