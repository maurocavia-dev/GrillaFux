import SwiftUI
import WebKit
import Combine
import FirebaseMessaging

struct ContentView: View {
    let urlString = "https://appfux.sytes.net/grilla/"
    @ObservedObject var tokenManager = TokenManager.shared
    @State private var updateInfo: VersionCheckInfo? = nil

    var body: some View {
        WebView(url: URL(string: urlString)!, token: tokenManager.fcmToken)
            .edgesIgnoringSafeArea(.all)
            .onAppear { checkAppVersion() }
            .alert("Actualización requerida", isPresented: Binding(
                get: { updateInfo != nil },
                set: { if !$0 { updateInfo = nil } }
            )) {
                Button("Actualizar") {
                    if let urlStr = updateInfo?.updateUrl, let url = URL(string: urlStr) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Después", role: .cancel) { }
            } message: {
                Text(updateInfo?.message ?? "")
            }
    }

    private func checkAppVersion() {
        let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        guard let url = URL(string: "https://appfux.sytes.net/api/min-version") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ios = json["ios"] as? [String: Any],
                  let minBuild = ios["minBuild"] as? Int else { return }
            if currentBuild < minBuild {
                let info = VersionCheckInfo(
                    updateUrl: ios["updateUrl"] as? String ?? "",
                    message: (ios["message"] as? String ?? "Hay una nueva versión disponible.") + "\n\nTu versión: build \(currentBuild)\nMínima requerida: build \(minBuild)"
                )
                DispatchQueue.main.async {
                    self.updateInfo = info
                }
            }
        }.resume()
    }
}

struct VersionCheckInfo {
    let updateUrl: String
    let message: String
}

struct WebView: UIViewRepresentable {
    let url: URL
    let token: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        let scriptSource = """
            try {
                Object.defineProperty(window.navigator, 'standalone', {get: function(){return true;}});
                window.isIOSNative = true;
            } catch(e) {}
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "GrillaFuxApp/1.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        injectToken(into: uiView)
    }

    func injectToken(into webView: WKWebView) {
        if let t = token {
            let js = "if(window.onFirebaseTokenReceived) window.onFirebaseTokenReceived('\(t)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // Registro nativo directo al backend (no depende del JS)
    static func registerNative(token: String, userId: String = "") {
        guard let url = URL(string: "https://appfux.sytes.net/api/register-device") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: String] = ["token": token, "platform": "ios", "userId": userId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // Logging de error FCM al backend para diagnóstico (endpoint separado, no toca la colección Device)
    static func logFCMError(_ error: Error) {
        guard let url = URL(string: "https://appfux.sytes.net/api/log-fcm-error") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: String] = [
            "error": error.localizedDescription,
            "platform": "ios",
            "userId": UserDefaults.standard.string(forKey: "notif_name") ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inyectar token al JS si ya esta disponible (lo guarda el AppDelegate cuando FCM lo entrega)
            parent.injectToken(into: webView)
            // NOTA: NO llamamos a Messaging.messaging().token aqui porque puede ejecutarse
            // antes de que APNs entregue su token. El delegate
            // messaging(_:didReceiveRegistrationToken:) en AppDelegate maneja todo el ciclo:
            // espera APNs -> obtiene FCM token -> guarda en TokenManager -> registra en backend.
        }
    }
}
