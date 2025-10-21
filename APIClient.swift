import Foundation

final class APIClient: ObservableObject {
    @Published var baseURL: String
    @Published var apiKey: String
    
    init(baseURL: String = "https://tracker.turnernet.co", apiKey: String = "") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = "CaRpoauTdDYdxQwWhWeXUQy"
    }
    
    // MARK: - Core
    
    private func request(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let query { comps.queryItems = query }
        guard let finalURL = comps.url else { throw URLError(.badURL) }
        
        var req = URLRequest(url: finalURL)
        req.httpMethod = method
        
        if !apiKey.isEmpty { req.addValue(apiKey, forHTTPHeaderField: "X-API-Key") }
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let decidedContentType = contentType ?? (body != nil ? "application/json" : nil)
        if let decidedContentType { req.addValue(decidedContentType, forHTTPHeaderField: "Content-Type") }
        
        req.httpBody = body
        return req
    }
    
    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) {
                throw apiErr
            }
            throw URLError(.init(rawValue: http.statusCode))
        }
    }
    
    // MARK: - Tickets
    
    func listTickets() async throws -> [Ticket] {
        let req = try request("/api/v1/tickets")
        return try await send(req)
    }
    
    func listActiveTickets(clientKey: String? = nil) async throws -> [Ticket] {
        var items: [URLQueryItem]? = nil
        if let k = clientKey, !k.isEmpty { items = [URLQueryItem(name: "client_key", value: k)] }
        let req = try request("/api/v1/tickets/active", query: items)
        return try await send(req)
    }
    
    func createTicket(_ new: NewTicket) async throws -> Ticket {
        let body = try JSONEncoder().encode(new)
        let req = try request("/api/v1/tickets", method: "POST", body: body)
        return try await send(req)
    }
    
    func updateTicket(id: Int, patch: [String: Any]) async throws -> Ticket {
        let body = try JSONSerialization.data(withJSONObject: patch, options: [])
        let req = try request("/api/v1/tickets/\(id)", method: "PATCH", body: body)
        return try await send(req)
    }
    
    func deleteTicket(id: Int) async throws {
        let req = try request("/api/v1/tickets/\(id)", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }
    
    // MARK: - Clients (super-tolerant)
    
    /// Always returns a flat array of ClientRecord, regardless of payload shape.
    /// Supported shapes:
    ///  - { "clients": { "<key>": { ... }, ... }, "attribute_keys": [...] }
    ///  - { "clients": [ {client_key,name,...}, ... ] }
    ///  - [ {client_key,name,...}, ... ]
    ///  - { "clients": { "<key>": { arbitrary attributes; may include "name" }, ... } }
    func fetchClientsFlat() async throws -> [ClientRecord] {
        let req = try request("/api/v1/clients")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let dec = JSONDecoder()
        
        // 1) Try a forgiving wrapper (map/array forms)
        if let wrapper = try? dec.decode(ClientsResult.self, from: data) {
            return wrapper.records
        }
        // 2) Try an array of ClientRecord
        if let arr = try? dec.decode([ClientRecord].self, from: data) {
            return arr.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        // 3) Try a map of ClientRecord values
        if let dict = try? dec.decode([String: ClientRecord].self, from: data) {
            return dict.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        // 4) Try a map of arbitrary attributes; synthesize ClientRecord
        if let dict2 = try? dec.decode([String: [String:String]].self, from: data) {
            return dict2.map { (k, v) in
                ClientRecord(client_key: k, name: v["name"] ?? k, attributes: v)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        // Fallback: throw a readable parsing error
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unrecognized /clients payload"))
    }
    
    // MARK: - Hardware (forgiving shapes)
    
    func listHardware(limit: Int = 100, offset: Int = 0) async throws -> HardwareResult {
        let q = [URLQueryItem(name: "limit", value: "\(limit)"),
                 URLQueryItem(name: "offset", value: "\(offset)")]
        let req = try request("/api/v1/hardware", query: q)
        return try await send(req)
    }
}

// MARK: - Convenience Ticket Patches

extension APIClient {
    func markCompleted(_ ticket: Ticket, completed: Bool) async throws -> Ticket {
        try await updateTicket(id: ticket.id, patch: ["completed": completed ? 1 : 0])
    }
    
    func markSent(_ ticket: Ticket, sent: Bool, invoice: String?) async throws -> Ticket {
        var p: [String: Any] = ["sent": sent ? 1 : 0]
        if let invoice { p["invoice_number"] = invoice }
        return try await updateTicket(id: ticket.id, patch: p)
    }
    
    func stopNow(_ ticket: Ticket) async throws -> Ticket {
        try await updateTicket(id: ticket.id, patch: ["end_iso": ISO8601DateTransformer.string(Date())])
    }
    
    func startNew(clientKey: String, type: EntryType) async throws -> Ticket {
        let payload = NewTicket(
            client_key: clientKey,
            entry_type: type,
            start_iso: ISO8601DateTransformer.string(Date()),
            end_iso: nil,
            note: nil,
            invoice_number: nil,
            sent: 0,
            completed: 0,
            hardware_id: nil,
            hardware_barcode: nil
        )
        return try await createTicket(payload)
    }
}
