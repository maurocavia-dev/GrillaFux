import SwiftUI
import WebKit
import Combine

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
        
        // --- 1. Bridge Inicial ---
        let scriptSource = """
            try {
                Object.defineProperty(window.navigator, 'standalone', {get: function(){return true;}});
                window.isIOSNative = true;
            } catch(e) {}
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator // Asignamos el delegado
        webView.customUserAgent = "GrillaFuxApp/1.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        webView.allowsBackForwardNavigationGestures = true
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Caso 1: El token cambia mientras la app ya está abierta
        injectToken(into: uiView)
    }
    
    func injectToken(into webView: WKWebView) {
        if let t = token {
            // Intentamos inyectar. Si la web no está lista, fallará (pero el Coordinator lo hará luego)
            // Si la web está lista, funcionará ahora.
            let js = "if(window.onFirebaseTokenReceived) window.onFirebaseTokenReceived('\(t)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // --- COORDINATOR PARA MANEJAR EVENTOS DE CARGA ---
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Caso 2: La página termina de cargar. Inyectamos el token si ya lo tenemos.
            print("WebView didFinish loading. Injecting token if available.")
            parent.injectToken(into: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
             print("WebView error: \(error.localizedDescription)")
        }
    }
}
