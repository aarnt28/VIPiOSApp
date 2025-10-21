import SwiftUI

// Root tabs
struct RootView: View {
    @StateObject var state = AppState()
    var body: some View {
        TabView {
            ClientsView().environmentObject(state)
                .tabItem { Label("Clients", systemImage: "person.3") }
            TicketsView().environmentObject(state)
                .tabItem { Label("Tickets", systemImage: "list.bullet.rectangle") }
            HardwareView().environmentObject(state)
                .tabItem { Label("Hardware", systemImage: "shippingbox") }
        }
        .task { await state.loadAll() }
        .overlay(alignment: .bottom) {
            if let err = state.error {
                Text(err).font(.footnote).padding(8).background(.red.opacity(0.9)).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Clients
struct ClientsView: View {
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @State private var showNew = false

    var filtered: [(key: String, client: Client)] {
        guard !search.isEmpty else { return state.clients }
        return state.clients.filter { $0.client.name.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.key) { pair in
                NavigationLink {
                    ClientDetailView(clientKey: pair.key, model: pair.client)
                } label: {
                    VStack(alignment: .leading) {
                        Text(pair.client.name)
                        Text(pair.key).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Clients")
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") { Task { await state.loadClients() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                ClientEditView(mode: .create) { key, name, attrs in
                    Task {
                        try? await state.api.createClient(client_key: key, name: name, attributes: attrs)
                        await state.loadClients()
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct ClientDetailView: View {
    let clientKey: String
    @State var model: Client
    @EnvironmentObject var state: AppState
    @State private var showEdit = false
    @State private var note = ""
    @State private var showScanner = false
    @State private var scannedBarcode: String?

    var body: some View {
        Form {
            Section("Info") {
                TextField("Name", text: $model.name).disabled(true)
                Text(clientKey).font(.footnote).foregroundStyle(.secondary)
                if !model.attributes.isEmpty {
                    ForEach(model.attributes.sorted(by: {$0.key<$1.key}), id: \.key) { k, v in
                        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) }
                    }
                } else {
                    Text("No attributes").foregroundStyle(.secondary)
                }
            }

            Section("New ticket") {
                TextField("Note", text: $note)
                HStack {
                    Button("Start Time (15m)") {
                        Task {
                            let now = ISO8601DateFormatter().string(from: Date())
                            let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(15 * 60))
                            let create = TicketCreate(client_key: clientKey, entry_type: "time", start_iso: now, end_iso: end, note: note.isEmpty ? nil : note, hardware_id: nil, hardware_barcode: scannedBarcode)
                            _ = try? await state.api.createTicket(create)
                            await state.loadTickets(for: clientKey)
                        }
                    }
                    Spacer()
                    Button {
                        showScanner = true
                    } label: {
                        Label(scannedBarcode == nil ? "Scan hw" : "Scanned: \(scannedBarcode!)", systemImage: "barcode.viewfinder")
                            .lineLimit(1)
                    }
                }
            }

            Section("Active tickets") {
                List(state.tickets.filter { $0.client_key == clientKey }) { t in
                    VStack(alignment: .leading) {
                        Text(t.note ?? "(no note)")
                        Text("\(t.entry_type.uppercased()) • \(t.rounded_minutes ?? 0) min").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 80, maxHeight: 240)
                .task { await state.loadTickets(for: clientKey) }
            }
        }
        .navigationTitle(model.name)
        .toolbar {
            Button("Edit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) {
            ClientEditView(mode: .edit(existing: model)) { _, name, attrs in
                Task {
                    try? await state.api.patchClient(client_key: clientKey, name: name, attributes: attrs)
                    await state.loadClients()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in self.scannedBarcode = code }
        }
    }
}

struct ClientEditView: View {
    enum Mode { case create, edit(existing: Client) }
    let mode: Mode
    var onCommit: (_ client_key: String, _ name: String, _ attributes: [String:String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clientKey = ""
    @State private var name = ""
    @State private var kvPairs: [KV] = []
    struct KV: Identifiable { var id = UUID(); var key: String; var value: String }

    

    var body: some View {
        NavigationStack {
            Form {
                if case .create = mode {
                    TextField("client_key (unique)", text: $clientKey).autocapitalization(.none)
                } else {
                    HStack { Text("client_key"); Spacer(); Text(clientKey).foregroundStyle(.secondary) }
                }
                TextField("name", text: $name)
                Section("Attributes") {
                    ForEach($kvPairs) { $pair in
                        HStack {
                            TextField("key", text: $pair.key).autocapitalization(.none)
                            TextField("value", text: $pair.value)
                        }
                    }
                    Button { kvPairs.append(.init(key: "", value: "")) } label: { Label("Add attribute", systemImage: "plus") }
                }
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var attrs: [String:String] = [:]
                        kvPairs.forEach { if !$0.key.isEmpty { attrs[$0.key] = $0.value } }
                        onCommit(clientKey.isEmpty ? clientKeyFromName(name) : clientKey, name, attrs)
                        dismiss()
                    }.disabled(name.isEmpty || (clientKey.isEmpty && isCreate))
                }
            }
        }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }
    private var modeTitle: String { isCreate ? "New Client" : "Edit Client" }
    private func clientKeyFromName(_ n: String) -> String {
        n.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Tickets
struct TicketsView: View {
    @EnvironmentObject var state: AppState
    @State private var showNew = false
    var body: some View {
        NavigationStack {
            List(state.tickets) { t in
                NavigationLink {
                    TicketDetailView(ticket: t)
                } label: {
                    VStack(alignment: .leading) {
                        Text(t.client).font(.headline)
                        if let n = t.note, !n.isEmpty { Text(n).font(.subheadline) }
                        Text("\(t.entry_type.uppercased()) • \(t.rounded_minutes ?? 0) min").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tickets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Refresh") { Task { await state.loadTickets() } } }
                ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showNew) {
                TicketCreateView(clients: state.clients.map(\.client)) { create in
                    Task { _ = try? await state.api.createTicket(create); await state.loadTickets() }
                }.presentationDetents([.medium, .large])
            }
            .task { await state.loadTickets() }
        }
    }
}

struct TicketDetailView: View {
    @EnvironmentObject var state: AppState
    let ticket: Ticket
    @State private var note = ""
    @State private var showScanner = false
    @State private var scanned: String?

    var body: some View {
        Form {
            Section("Info") {
                Text(ticket.client).font(.headline)
                Text("Type: \(ticket.entry_type)").foregroundStyle(.secondary)
                Text("Minutes: \(ticket.rounded_minutes ?? 0)").foregroundStyle(.secondary)
            }
            Section("Edit") {
                TextField("note", text: $note)
                HStack {
                    Button("Attach barcode") { showScanner = true }
                    if let scanned { Text(scanned).font(.footnote).foregroundStyle(.secondary) }
                }
                Button("Save Patch") {
                    Task {
                        let patch = TicketPatch(end_iso: nil, note: note.isEmpty ? nil : note, hardware_id: nil, hardware_barcode: scanned)
                        _ = try? await state.api.patchTicket(id: ticket.id, patch: patch)
                        await state.loadTickets()
                    }
                }
            }
        }
        .navigationTitle("Ticket #\(ticket.id)")
        .sheet(isPresented: $showScanner) { BarcodeScannerView { scanned = $0 } }
    }
}

// Create ticket with optional barcode
struct TicketCreateView: View {
    let clients: [Client]
    var onCreate: (TicketCreate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Client?
    @State private var isHardware = false
    @State private var note = ""
    @State private var barcode: String?
    @State private var showScanner = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Client", selection: $selected) {
                    ForEach(clients) { c in Text(c.name).tag(Optional(c)) }
                }
                Toggle("Hardware entry", isOn: $isHardware)
                TextField("Note", text: $note)
                HStack {
                    Button("Scan barcode") { showScanner = true }
                    if let b = barcode { Text(b).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("New Ticket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let c = selected else { return }
                        let now = Date()
                        let start = ISO8601DateFormatter().string(from: now)
                        let end = ISO8601DateFormatter().string(from: now.addingTimeInterval(15*60))
                        let t = TicketCreate(client_key: c.client_key,
                                             entry_type: isHardware ? "hardware" : "time",
                                             start_iso: start, end_iso: end,
                                             note: note.isEmpty ? nil : note,
                                             hardware_id: nil, hardware_barcode: barcode)
                        onCreate(t); dismiss()
                    }.disabled(selected == nil)
                }
            }
        }
        .sheet(isPresented: $showScanner) { BarcodeScannerView { barcode = $0 } }
    }
}

// MARK: - Hardware
struct HardwareView: View {
    @EnvironmentObject var state: AppState
    @State private var showNew = false
    @State private var showScanner = false
    @State private var scanTarget: ScanTarget?

    enum ScanTarget { case createBarcode, adjustBarcodeReceive, adjustBarcodeUse }

    @State private var adjustQty = "1"
    @State private var adjustNote = ""
    @State private var adjustBarcode: String = ""

    var body: some View {
        NavigationStack {
            List(state.hardware) { h in
                NavigationLink {
                    HardwareDetailView(item: h)
                } label: {
                    VStack(alignment: .leading) {
                        Text("\(h.description)")
                        Text("\(h.barcode)").font(.footnote).foregroundStyle(.secondary)
                        Text("Sale: \(h.sales_price ?? "-")  Cost: \(h.acquisition_cost ?? "-")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Hardware")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Refresh") { Task { await state.loadHardware() } } }
                ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Divider()
                    HStack {
                        TextField("Barcode", text: $adjustBarcode).textInputAutocapitalization(.never)
                        TextField("Qty ±", text: $adjustQty).keyboardType(.numberPad)
                        TextField("Note", text: $adjustNote)
                        Button { scanTarget = .adjustBarcodeReceive; showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                        Button("Receive") {
                            Task { try? await state.api.receive(barcode: adjustBarcode, qty: Int(adjustQty) ?? 0, note: adjustNote)
                                await state.loadHardware()
                            }
                        }
                        Button("Use") {
                            Task { try? await state.api.use(barcode: adjustBarcode, qty: Int(adjustQty) ?? 0, note: adjustNote)
                                await state.loadHardware()
                            }
                        }
                    }.padding(.horizontal).padding(.bottom, 8)
                }.background(.thinMaterial)
            }
            .sheet(isPresented: $showNew) {
                HardwareEditView(mode: .create) { create in
                    Task { _ = try? await state.api.createHardware(create); await state.loadHardware() }
                }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    switch scanTarget {
                    case .createBarcode: NotificationCenter.default.post(name: .hardwareCreateScan, object: code)
                    case .adjustBarcodeReceive, .adjustBarcodeUse: adjustBarcode = code
                    case .none: break
                    }
                }
            }
            .task { await state.loadHardware() }
        }
    }
}

extension Notification.Name { static let hardwareCreateScan = Notification.Name("hardwareCreateScan") }

struct HardwareEditView: View {
    enum Mode { case create, edit(HardwareItem) }
    let mode: Mode
    var onCommitCreate: ((HardwareCreate)->Void)?
    var onCommitPatch: ((HardwarePatch)->Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var barcode = ""
    @State private var desc = ""
    @State private var cost = ""
    @State private var price = ""

    init(mode: Mode, onCommit: @escaping (HardwareCreate)->Void) {
        self.mode = mode; self.onCommitCreate = onCommit; self.onCommitPatch = nil
    }
    init(mode: Mode, onPatch: @escaping (HardwarePatch)->Void) {
        self.mode = mode; self.onCommitCreate = nil; self.onCommitPatch = onPatch
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Barcode", text: $barcode).textInputAutocapitalization(.never)
                    Button { NotificationCenter.default.addObserver(forName: .hardwareCreateScan, object: nil, queue: .main) { n in
                        if let code = n.object as? String { self.barcode = code }
                    }} label: { Image(systemName: "barcode.viewfinder") }
                }
                TextField("Description", text: $desc)
                TextField("Cost", text: $cost).keyboardType(.decimalPad)
                TextField("Price", text: $price).keyboardType(.decimalPad)
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        switch mode {
                        case .create:
                            onCommitCreate?(HardwareCreate(barcode: barcode, description: desc,
                                                           acquisition_cost: cost.isEmpty ? nil : cost,
                                                           sales_price: price.isEmpty ? nil : price))
                        case .edit:
                            onCommitPatch?(HardwarePatch(barcode: barcode.isEmpty ? nil : barcode,
                                                         description: desc.isEmpty ? nil : desc,
                                                         acquisition_cost: cost.isEmpty ? nil : cost,
                                                         sales_price: price.isEmpty ? nil : price))
                        }
                        dismiss()
                    }.disabled(desc.isEmpty || barcode.isEmpty)
                }
            }
            .onAppear {
                if case .edit(let h) = mode {
                    barcode = h.barcode; desc = h.description
                    cost = h.acquisition_cost ?? ""; price = h.sales_price ?? ""
                }
            }
        }
    }

    private var modeTitle: String { if case .create = mode { "New Hardware" } else { "Edit Hardware" } }
}

struct HardwareDetailView: View {
    @EnvironmentObject var state: AppState
    @State var item: HardwareItem
    @State private var showEdit = false

    var body: some View {
        Form {
            Text(item.description).font(.headline)
            Text(item.barcode).font(.footnote).foregroundStyle(.secondary)
            HStack { Text("Cost"); Spacer(); Text(item.acquisition_cost ?? "-") }
            HStack { Text("Price"); Spacer(); Text(item.sales_price ?? "-") }
        }
        .navigationTitle("Hardware #\(item.id)")
        .toolbar { Button("Edit") { showEdit = true } }
        .sheet(isPresented: $showEdit) {
            HardwareEditView(mode: .edit(item)) { patch in
                Task {
                    if let updated = try? await state.api.patchHardware(id: item.id, patch: patch) {
                        self.item = updated
                        await state.loadHardware()
                    }
                }
            }.presentationDetents([.medium, .large])
        }
    }
}
