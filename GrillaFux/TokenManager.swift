import Foundation
import Combine

class TokenManager: ObservableObject {
    static let shared = TokenManager()
    @Published var fcmToken: String?
}
