import Foundation

enum Config {
    // CHANGE THESE
    static let baseURL = URL(string: "https://tracker.turnernet.co")! // or http://<LAN>:8089 (dev)
    static let apiKey  = "CaRpoauTdDYdxQwWhWeXUQy" // required for writes
}

let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.withoutEscapingSlashes]
    return e
}()
