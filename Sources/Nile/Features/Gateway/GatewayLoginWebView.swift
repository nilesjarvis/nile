import SwiftUI
import WebKit

enum GatewayLoginPageState {
    case started(URL)
    case finished(URL)
    case failed(String)
}

struct GatewayLoginWebView: UIViewRepresentable {
    let loginURL: URL
    let fixtureHTML: String?
    let approvedExternalOrigins: Set<String>
    let reloadGeneration: Int
    let onState: (GatewayLoginPageState) -> Void
    let onExternalNavigation: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(NileColors.background)
        view.scrollView.backgroundColor = UIColor(NileColors.background)
        view.navigationDelegate = context.coordinator
        context.coordinator.load(in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.reloadGeneration != reloadGeneration {
            context.coordinator.reloadGeneration = reloadGeneration
            if let pending = context.coordinator.pendingApprovedExternalURL,
               let origin = gatewayOriginKey(pending),
               approvedExternalOrigins.contains(origin) {
                context.coordinator.pendingApprovedExternalURL = nil
                view.load(URLRequest(url: pending))
            } else {
                context.coordinator.load(in: view)
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: GatewayLoginWebView
        var reloadGeneration: Int
        var pendingApprovedExternalURL: URL?

        init(parent: GatewayLoginWebView) {
            self.parent = parent
            reloadGeneration = parent.reloadGeneration
        }

        func load(in view: WKWebView) {
            if let fixtureHTML = parent.fixtureHTML {
                view.loadHTMLString(
                    fixtureHTML,
                    baseURL: parent.loginURL.deletingLastPathComponent()
                )
            } else {
                view.load(URLRequest(url: parent.loginURL))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable
                (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let target = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }
            let policy = GatewayLoginNavigationPolicy(
                gatewayLoginURL: parent.loginURL
            )
            switch policy.decision(
                for: target,
                approvedExternalOrigins: parent.approvedExternalOrigins
            ) {
            case .allow:
                decisionHandler(.allow)
            case .approveExternal:
                pendingApprovedExternalURL = target
                parent.onExternalNavigation(target)
                decisionHandler(.cancel)
            case let .block(message):
                parent.onState(.failed(message))
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation?
        ) {
            parent.onState(.started(webView.url ?? parent.loginURL))
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation?
        ) {
            parent.onState(.finished(webView.url ?? parent.loginURL))
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: any Error
        ) {
            parent.onState(.failed(error.localizedDescription))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            parent.onState(.failed(error.localizedDescription))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable
                (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse,
               response.statusCode >= 400 {
                parent.onState(
                    .failed(
                        "The sign-in page returned HTTP \(response.statusCode)"
                    )
                )
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
