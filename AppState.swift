import Foundation
import Combine

/// Minimal app-wide state holder that won’t clash with API types.
final class AppState: ObservableObject {
    @Published var api = APIClient()
}
