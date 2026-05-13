import SwiftUI
import FirebaseCore
import FirebaseMessaging

// --- APP DELEGATE ---
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { _, _ in }
        )

        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("[FCM] Token recibido: \(token.prefix(20))...")

        DispatchQueue.main.async {
            // 1. Actualizar TokenManager para que la WebView lo inyecte vía JS
            TokenManager.shared.fcmToken = token

            // 2. Registro nativo directo al backend (no depende del timing de la WebView)
            let userId = UserDefaults.standard.string(forKey: "notif_name") ?? ""
            AppDelegate.registerDevice(token: token, userId: userId)
        }
    }

    // Registro nativo directo al backend
    static func registerDevice(token: String, userId: String) {
        guard let url = URL(string: "https://appfux.sytes.net/api/register-device") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: String] = ["token": token, "platform": "ios", "userId": userId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}

// --- MAIN STRUCT ---
@main
struct GrillaFuxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
