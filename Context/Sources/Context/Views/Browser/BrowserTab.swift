import Foundation
import WebKit
import Combine

class BrowserTab: NSObject, Identifiable, ObservableObject {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = "New Tab"
    @Published var currentURL: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        observations = [
            webView.observe(\.title) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.title = wv.title ?? "New Tab" }
            },
            webView.observe(\.url) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.currentURL = wv.url?.absoluteString ?? "" }
            },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.isLoading = wv.isLoading }
            },
            webView.observe(\.canGoBack) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoForward = wv.canGoForward }
            },
        ]
    }

    func navigate(to urlString: String) {
        var input = urlString.trimmingCharacters(in: .whitespaces)
        if !input.contains("://") {
            if input.hasPrefix("localhost") || input.hasPrefix("127.0.0.1") {
                input = "http://\(input)"
            } else {
                input = "https://\(input)"
            }
        }
        guard let url = URL(string: input) else { return }
        webView.load(URLRequest(url: url))
    }
}
