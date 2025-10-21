import SwiftUI

struct TicketDetailView: View {
    @EnvironmentObject var api: APIClient
    @State var ticket: Ticket
    var onUpdate: (Ticket) -> Void
    var onDelete: () -> Void
    
    @State private var note: String = ""
    @State private var invoiceNumber: String = ""
    @State private var invoicedTotal: String = ""
    @State private var hardwareBarcode: String = ""
    @State private var hardwareQuantity: String = ""
    @State private var flatRateAmount: String = ""
    @State private var flatRateQuantity: String = ""
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
                        infoRow("Type", ticket.entry_type.displayName)
                        if let value = ticket.calculated_value, !value.isEmpty {
                            infoRow("Calculated", value)
                        }
                        if let total = ticket.invoiced_total, !total.isEmpty {
                            infoRow("Invoiced", total)
                        }
                        if let elapsed = ticket.elapsed_minutes {
                            infoRow("Elapsed", "\(elapsed) min")
                        }
                        if let rounded = ticket.rounded_minutes {
                            if let hours = ticket.rounded_hours, !hours.isEmpty {
                                infoRow("Rounded", "\(rounded) min (\(hours))")
                            } else {
                                infoRow("Rounded", "\(rounded) min")
                            }
                        }
                        if let mins = ticket.minutes, ticket.elapsed_minutes == nil && ticket.rounded_minutes == nil {
                            infoRow("Minutes", "\(mins)")
                        }
                        if let start = ISO8601DateTransformer.parse(ticket.start_iso) {
                            infoRow("Start", start.formatted(date: .numeric, time: .shortened))
                        }
                        if let end = ticket.end_iso,
                           let date = ISO8601DateTransformer.parse(end) {
                            infoRow("End", date.formatted(date: .numeric, time: .shortened))
                        }
                        if let created = ticket.created_at {
                            infoRow("Created", created)
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
                    TextField("Invoiced Total", text: $invoicedTotal)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                }
                
                // MARK: HARDWARE
                if ticket.entry_type == .hardware {
                    GroupBox("Hardware") {
                        if let desc = ticket.hardware_description {
                            Text(desc).font(.subheadline)
                        }
                        if let sales = ticket.hardware_sales_price, !sales.isEmpty {
                            Text("Unit Price: \(sales)")
                                .font(.caption)
                        }
                        TextField("Barcode", text: $hardwareBarcode)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                        TextField("Quantity", text: $hardwareQuantity)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        if let hwid = ticket.hardware_id {
                            Text("Hardware ID: \(hwid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: FLAT RATE
                if ticket.entry_type == .deployment_flat_rate {
                    GroupBox("Flat Rate") {
                        TextField("Amount", text: $flatRateAmount)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                        TextField("Quantity", text: $flatRateQuantity)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // MARK: NOTE
                GroupBox("Note") {
                    TextEditor(text: $note)
                        .frame(height: 140)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // MARK: ATTACHMENTS
                if !ticket.attachments.isEmpty {
                    GroupBox("Attachments") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(ticket.attachments.enumerated()), id: \.element.id) { index, attachment in
                                let resolved = attachmentURL(for: attachment)
                                Group {
                                    if let url = resolved {
                                        Link(destination: url) {
                                            AttachmentContent(attachment: attachment)
                                        }
                                    } else {
                                        AttachmentContent(attachment: attachment)
                                    }
                                }
                                if index < ticket.attachments.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
        invoicedTotal = ticket.invoiced_total ?? ""
        hardwareBarcode = ticket.hardware_barcode ?? ""
        hardwareQuantity = ticket.hardware_quantity.map { String($0) } ?? ""
        flatRateAmount = ticket.flat_rate_amount ?? ""
        flatRateQuantity = ticket.flat_rate_quantity.map { String($0) } ?? ""
        startDate = ticket.startDate
        endDate = ticket.endDate
        completed = ticket.completed
        sent = ticket.sent
    }
    
    // MARK: - Save Patch
    private func save() async {
        await MainActor.run { self.error = nil }
        saving = true; defer { saving = false }
        var patch: [String: Any] = [
            "note": note,
            "completed": completed ? 1 : 0,
            "sent": sent ? 1 : 0
        ]
        
        let trimmedInvoice = invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["invoice_number"] = trimmedInvoice.isEmpty ? NSNull() : trimmedInvoice
        let trimmedTotal = invoicedTotal.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["invoiced_total"] = trimmedTotal.isEmpty ? NSNull() : trimmedTotal
        
        if ticket.entry_type == .hardware {
            let trimmedBarcode = hardwareBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
            patch["hardware_barcode"] = trimmedBarcode.isEmpty ? NSNull() : trimmedBarcode
            let qtyString = hardwareQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
            if qtyString.isEmpty {
                patch["hardware_quantity"] = NSNull()
            } else if let qty = Int(qtyString), qty > 0 {
                patch["hardware_quantity"] = qty
            } else {
                await MainActor.run { self.error = "Hardware quantity must be a positive integer." }
                return
            }
        }
        
        if ticket.entry_type == .deployment_flat_rate {
            let amount = flatRateAmount.trimmingCharacters(in: .whitespacesAndNewlines)
            patch["flat_rate_amount"] = amount.isEmpty ? NSNull() : amount
            let qtyString = flatRateQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
            if qtyString.isEmpty {
                patch["flat_rate_quantity"] = NSNull()
            } else if let qty = Int(qtyString), qty > 0 {
                patch["flat_rate_quantity"] = qty
            } else {
                await MainActor.run { self.error = "Flat rate quantity must be a positive integer." }
                return
            }
        }
        
        do {
            let updated = try await api.updateTicket(id: ticket.id, patch: patch)
            await MainActor.run {
                ticket = updated
                loadValues()
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
                loadValues()
                onUpdate(updated)
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("\(label):")
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
    
    private func attachmentURL(for attachment: TicketAttachment) -> URL? {
        guard let path = attachment.url, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let base = api.baseURL.hasSuffix("/") ? api.baseURL : api.baseURL + "/"
        return URL(string: base + trimmed)
    }
}

private struct AttachmentContent: View {
    let attachment: TicketAttachment
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "paperclip")
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename).font(.subheadline)
                HStack(spacing: 6) {
                    if let size = attachment.size {
                        Text(byteCount(size)).foregroundStyle(.secondary)
                    }
                    Text(attachment.uploaded_at).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func byteCount(_ size: Int) -> String {
        AttachmentContent.formatter.string(fromByteCount: Int64(size))
    }
}
