
import SwiftUI
import WebKit

struct ContentView: View {
    let urlString = "https://appfux.sytes.net/grilla/"
    
    var body: some View {
        WebView(url: URL(string: urlString)!)
            .edgesIgnoringSafeArea(.all)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}
