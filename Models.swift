import Foundation

// MARK: - API Error

struct APIError: Error, LocalizedError, Codable {
    let detail: String?
    var errorDescription: String? { detail ?? "Unknown server error" }
}

// MARK: - EntryType

enum EntryType: String, Codable, CaseIterable, Identifiable {
    case time
    case hardware
    var id: String { rawValue }
}

// MARK: - IntBool (0/1 ⇄ Bool)

@propertyWrapper
struct IntBool: Codable {
    var wrappedValue: Bool
    init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { wrappedValue = (i != 0) }
        else if let b = try? c.decode(Bool.self) { wrappedValue = b }
        else { wrappedValue = false }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue ? 1 : 0)
    }
}

// MARK: - Ticket

struct Ticket: Codable, Identifiable, Equatable {
    let id: Int
    var client: String?
    var client_key: String
    var start_iso: String
    var end_iso: String?
    var note: String?
    var elapsed_minutes: Int?
    var rounded_minutes: Int?
    var rounded_hours: String?
    @IntBool var completed: Bool
    @IntBool var sent: Bool
    var invoice_number: String?
    var created_at: String?
    var minutes: Int?
    var entry_type: EntryType
    var hardware_id: Int?
    var hardware_barcode: String?
    var hardware_description: String?
    var hardware_sales_price: String?
    
    static func == (lhs: Ticket, rhs: Ticket) -> Bool { lhs.id == rhs.id }
    
    var startDate: Date {
        get { ISO8601DateTransformer.parse(start_iso) ?? Date() }
        set { start_iso = ISO8601DateTransformer.string(newValue) }
    }
    var endDate: Date? {
        get { end_iso.flatMap { ISO8601DateTransformer.parse($0) } }
        set { end_iso = newValue.map { ISO8601DateTransformer.string($0) } }
    }
}

struct NewTicket: Codable {
    var client_key: String
    var entry_type: EntryType = .time
    var start_iso: String
    var end_iso: String?
    var note: String?
    var invoice_number: String?
    var sent: Int?
    var completed: Int?
    var hardware_id: Int?
    var hardware_barcode: String?
}

// MARK: - Clients

struct ClientRecord: Codable, Identifiable {
    var id: String { client_key }
    let client_key: String
    var name: String
    var attributes: [String: String]?
}

/// A forgiving /clients wrapper that accepts:
/// 1) { "clients": { "<key>": { ... }, ... }, "attribute_keys": [...] }
/// 2) { "clients": [ ClientRecord, ... ], "attribute_keys": [...] }
/// 3) [ ClientRecord, ... ]  (top-level array)
struct ClientsResult: Decodable {
    let records: [ClientRecord]
    let attribute_keys: [String]
    
    private enum CodingKeys: String, CodingKey { case clients, attribute_keys }
    
    init(from decoder: Decoder) throws {
        // Try keyed container first
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            // 1) Map-of-dictionaries (values may simply be attributes, must synthesize ClientRecord)
            if let map = try? c.decode([String:[String:String]].self, forKey: .clients) {
                self.records = map.map { (k, v) in
                    ClientRecord(client_key: k, name: v["name"] ?? k, attributes: v)
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.attribute_keys = (try? c.decode([String].self, forKey: .attribute_keys)) ?? []
                return
            }
            // 1b) Map-of-ClientRecord
            if let map2 = try? c.decode([String:ClientRecord].self, forKey: .clients) {
                self.records = map2.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.attribute_keys = (try? c.decode([String].self, forKey: .attribute_keys)) ?? []
                return
            }
            // 2) Array under "clients"
            if let arr = try? c.decode([ClientRecord].self, forKey: .clients) {
                self.records = arr.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.attribute_keys = (try? c.decode([String].self, forKey: .attribute_keys)) ?? []
                return
            }
        }
        
        // 3) Top-level array
        let sv = try decoder.singleValueContainer()
        if let arr = try? sv.decode([ClientRecord].self) {
            self.records = arr.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.attribute_keys = []
            return
        }
        
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognized clients payload"))
    }
}

// MARK: - Hardware

struct Hardware: Codable, Identifiable, Hashable {
    let id: Int
    let barcode: String
    let description: String
    let acquisition_cost: String?
    let sales_price: String?
    let created_at: String?
}

/// A forgiving /hardware wrapper that accepts:
/// 1) { "items": [ Hardware, ... ], "total": N }
/// 2) [ Hardware, ... ]
struct HardwareResult: Decodable {
    let items: [Hardware]
    let total: Int?
    
    private enum CodingKeys: String, CodingKey { case items, total }
    
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let arr = try? c.decode([Hardware].self, forKey: .items) {
            self.items = arr
            self.total = try? c.decode(Int.self, forKey: .total)
            return
        }
        let sv = try decoder.singleValueContainer()
        if let arr = try? sv.decode([Hardware].self) {
            self.items = arr
            self.total = arr.count
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognized hardware payload"))
    }
}

// MARK: - ISO8601 helpers

enum ISO8601DateTransformer {
    private static let encoder: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let decoder: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func string(_ date: Date) -> String { encoder.string(from: date) }
    static func parse(_ string: String) -> Date? {
        if let d = decoder.date(from: string) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
