import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

// Helper para mandar eventos diagnostico al backend
func logIOSEvent(_ stage: String, _ detail: String = "") {
    guard let url = URL(string: "https://appfux.sytes.net/api/log-fcm-error") else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 10
    let body: [String: String] = [
        "error": "[\(stage)] \(detail)",
        "platform": "ios",
        "userId": UserDefaults.standard.string(forKey: "notif_name") ?? "anon"
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
}

// --- APP DELEGATE ---
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logIOSEvent("01_launch", "App iniciada")
        FirebaseApp.configure()
        logIOSEvent("02_firebase_configured", "")

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                logIOSEvent("03_auth_response", "granted=\(granted) err=\(error?.localizedDescription ?? "nil")")
            }
        )

        application.registerForRemoteNotifications()
        logIOSEvent("04_register_called", "registerForRemoteNotifications llamado")
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        logIOSEvent("05_apns_token_received", "len=\(deviceToken.count) start=\(String(tokenStr.prefix(20)))")
        Messaging.messaging().apnsToken = deviceToken
        logIOSEvent("06_apns_set_in_firebase", "")

        // PLAN B: tambien registrar APNs token DIRECTAMENTE en el backend
        // (no esperamos a Firebase porque puede tardar/fallar)
        DispatchQueue.main.async {
            TokenManager.shared.fcmToken = tokenStr  // reutilizar TokenManager
            let userId = UserDefaults.standard.string(forKey: "notif_name") ?? ""
            logIOSEvent("06b_registering_apns_direct", "userId=\(userId)")
            AppDelegate.registerDevice(token: tokenStr, userId: userId)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logIOSEvent("XX_apns_failed", error.localizedDescription)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            logIOSEvent("07_fcm_token_received", "len=\(token.count) start=\(String(token.prefix(20)))")
            print("[FCM] Token recibido: \(token.prefix(20))...")

            DispatchQueue.main.async {
                TokenManager.shared.fcmToken = token
                let userId = UserDefaults.standard.string(forKey: "notif_name") ?? ""
                logIOSEvent("08_calling_register", "userId=\(userId)")
                AppDelegate.registerDevice(token: token, userId: userId)
            }
        } else {
            logIOSEvent("XX_fcm_token_nil", "")
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
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse {
                logIOSEvent("09_register_response", "status=\(http.statusCode)")
            }
            if let error = error {
                logIOSEvent("XX_register_error", error.localizedDescription)
            }
        }.resume()
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
