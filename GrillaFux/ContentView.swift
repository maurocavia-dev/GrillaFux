import SwiftUI
import WebKit
import Combine
import FirebaseMessaging

struct ContentView: View {
    let urlString = "https://appfux.sytes.net/grilla/"
    @ObservedObject var tokenManager = TokenManager.shared

    var body: some View {
        WebView(url: URL(string: urlString)!, token: tokenManager.fcmToken)
            .edgesIgnoringSafeArea(.all)
    }
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

    // Logging de error FCM al backend para diagnóstico
    static func logFCMError(_ error: Error) {
        guard let url = URL(string: "https://appfux.sytes.net/api/register-device") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: String] = [
            "token": "FCM_ERR:\(error.localizedDescription)",
            "platform": "ios_debug",
            "userId": "FCM_ERROR"
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
            // Inyectar desde TokenManager si ya está disponible
            parent.injectToken(into: webView)

            // Obtener token de Firebase directamente
            Messaging.messaging().token { token, error in
                if let error = error {
                    // Loguear error al backend para diagnóstico
                    WebView.logFCMError(error)
                    return
                }
                guard let token = token else { return }

                // 1. Inyectar al JS (para que el app asocie el userId)
                let js = "if(window.onFirebaseTokenReceived) window.onFirebaseTokenReceived('\(token)');"
                DispatchQueue.main.async {
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }

                // 2. Registro nativo directo (fallback por si JS falla)
                let savedUserId = UserDefaults.standard.string(forKey: "notif_name") ?? ""
                WebView.registerNative(token: token, userId: savedUserId)
            }
        }
    }
}
