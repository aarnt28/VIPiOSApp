import SwiftUI

struct TicketDetailView: View {
    @EnvironmentObject var api: APIClient
    @State var ticket: Ticket
    var onUpdate: (Ticket) -> Void
    var onDelete: () -> Void
    
    @State private var note: String = ""
    @State private var invoiceNumber: String = ""
    @State private var hardwareBarcode: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date? = nil
    @State private var completed = false
    @State private var sent = false
    @State private var saving = false
    @State private var error: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                // MARK: INFO
                GroupBox("Info") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ticket.client ?? ticket.client_key)
                            .font(.headline)
                        HStack {
                            Text("Type:")
                            Text(ticket.entry_type.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        if let mins = ticket.rounded_minutes ?? ticket.minutes {
                            HStack {
                                Text("Minutes:")
                                Text("\(mins)")
                            }
                        }
                        if let start = ISO8601DateTransformer.parse(ticket.start_iso) {
                            HStack {
                                Text("Start:")
                                Text(start.formatted(date: .numeric, time: .shortened))
                            }
                        }
                        if let end = ticket.end_iso,
                           let date = ISO8601DateTransformer.parse(end) {
                            HStack {
                                Text("End:")
                                Text(date.formatted(date: .numeric, time: .shortened))
                            }
                        }
                        if let created = ticket.created_at {
                            Text("Created: \(created)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // MARK: BILLING
                GroupBox("Billing") {
                    Toggle("Completed", isOn: $completed)
                    Toggle("Sent", isOn: $sent)
                    TextField("Invoice #", text: $invoiceNumber)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                }
                
                // MARK: HARDWARE
                if ticket.entry_type == .hardware {
                    GroupBox("Hardware") {
                        if let desc = ticket.hardware_description {
                            Text(desc).font(.subheadline)
                        }
                        if let sales = ticket.hardware_sales_price {
                            Text("Sales Price: \(sales)")
                                .font(.caption)
                        }
                        TextField("Barcode", text: $hardwareBarcode)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                        if let hwid = ticket.hardware_id {
                            Text("Hardware ID: \(hwid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: NOTE
                GroupBox("Note") {
                    TextEditor(text: $note)
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // MARK: ACTIONS
                VStack(spacing: 14) {
                    Button(action: { Task { await save() } }) {
                        Label("Save Patch", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                    
                    Button(action: { Task { await stopNow() } }) {
                        Label("Stop Now", systemImage: "pause.circle")
                    }
                    .disabled(ticket.end_iso != nil)
                    
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Ticket", systemImage: "trash")
                    }
                }
                .padding(.top, 6)
                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Ticket #\(ticket.id)")
        .task { loadValues() }
    }
    
    // MARK: - Load initial data
    private func loadValues() {
        note = ticket.note ?? ""
        invoiceNumber = ticket.invoice_number ?? ""
        hardwareBarcode = ticket.hardware_barcode ?? ""
        startDate = ticket.startDate
        endDate = ticket.endDate
        completed = ticket.completed
        sent = ticket.sent
    }
    
    // MARK: - Save Patch
    private func save() async {
        saving = true; defer { saving = false }
        var patch: [String: Any] = [
            "note": note,
            "completed": completed ? 1 : 0,
            "sent": sent ? 1 : 0,
            "invoice_number": invoiceNumber
        ]
        if ticket.entry_type == .hardware {
            patch["hardware_barcode"] = hardwareBarcode
        }
        do {
            let updated = try await api.updateTicket(id: ticket.id, patch: patch)
            await MainActor.run {
                ticket = updated
                onUpdate(updated)
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func stopNow() async {
        do {
            let updated = try await api.stopNow(ticket)
            await MainActor.run {
                ticket = updated
                onUpdate(updated)
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}
