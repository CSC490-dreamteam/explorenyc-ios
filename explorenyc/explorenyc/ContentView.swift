import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    @State private var topBarColor = UIColor.systemBackground
    @State private var bottomBarColor = UIColor.systemBackground

    private let siteURL = URL(string: "https://explorenewyork.city")!

    var body: some View {
        GeometryReader { proxy in
            let topBarHeight = proxy.safeAreaInsets.top
            let bottomBarHeight = proxy.safeAreaInsets.bottom
            let topContentInset = topBarHeight - 58
            let bottomContentInset = bottomBarHeight - 33.8

            ZStack {
                VStack(spacing: 0) {
                    Color(topBarColor)
                    Color(bottomBarColor)
                }
                .ignoresSafeArea()

                WebView(
                    url: siteURL,
                    onEdgeColorsChange: { topColor, bottomColor in
                        if !topBarColor.isVisuallyClose(to: topColor) {
                            topBarColor = topColor
                        }

                        if !bottomBarColor.isVisuallyClose(to: bottomColor) {
                            bottomBarColor = bottomColor
                        }
                    }
                )
                .ignoresSafeArea()
                .padding(.top, topContentInset)
                .padding(.bottom, bottomContentInset)

                VStack(spacing: 0) {
                    Color(topBarColor)
                        .frame(height: topBarHeight)

                    Spacer()

                    Color(bottomBarColor)
                        .frame(height: bottomBarHeight)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(
            StatusBarStyleView(
                style: topBarColor.prefersLightStatusBarContent ? .lightContent : .darkContent
            )
        )
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let onEdgeColorsChange: (UIColor, UIColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdgeColorsChange: onEdgeColorsChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = makeUserContentController(for: context.coordinator)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEdgeColorsChange = onEdgeColorsChange
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandlerName)
    }

    private func makeUserContentController(for coordinator: Coordinator) -> WKUserContentController {
        let controller = WKUserContentController()
        controller.add(coordinator, name: Coordinator.messageHandlerName)
        controller.addUserScript(WKUserScript(source: Self.edgeColorScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return controller
    }
    
    private static let edgeColorScript = #"""
    (function() {
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.edgeColors;
        if (!handler) { return; }

        function firstOpaqueBackground(element) {
            let current = element;
            while (current) {
                const color = window.getComputedStyle(current).backgroundColor;
                if (color && color !== "transparent" && color !== "rgba(0, 0, 0, 0)") {
                    return color;
                }
                current = current.parentElement;
            }

            const bodyColor = window.getComputedStyle(document.body).backgroundColor;
            return bodyColor && bodyColor !== "rgba(0, 0, 0, 0)" ? bodyColor : "rgb(255, 255, 255)";
        }

        function colorAtPoint(x, y) {
            const element = document.elementFromPoint(x, y);
            if (!element) {
                return firstOpaqueBackground(document.body);
            }
            return firstOpaqueBackground(element);
        }

        function sendEdgeColors() {
            const x = Math.max(1, Math.floor(window.innerWidth / 2));
            const topY = Math.min(window.innerHeight - 1, 8);
            const bottomY = Math.max(1, window.innerHeight - 8);

            handler.postMessage({
                top: colorAtPoint(x, topY),
                bottom: colorAtPoint(x, bottomY)
            });
        }

        let state = { isScheduled: false, timeoutID: null };
        function scheduleSend() {
            if (state.timeoutID !== null) {
                window.clearTimeout(state.timeoutID);
            }

            state.timeoutID = window.setTimeout(function() {
                state.timeoutID = null;
                if (state.isScheduled) { return; }
                state.isScheduled = true;
                sendEdgeColors();
                window.requestAnimationFrame(function() {
                    state.isScheduled = false;
                });
            }, 120);
        }

        window.addEventListener("scroll", scheduleSend, { passive: true });
        window.addEventListener("resize", scheduleSend);
        window.addEventListener("load", scheduleSend);
        document.addEventListener("DOMContentLoaded", scheduleSend);
        document.addEventListener("focusin", scheduleSend);
        document.addEventListener("focusout", scheduleSend);
        document.addEventListener("transitionend", scheduleSend, true);

        if (document.documentElement) {
            new MutationObserver(scheduleSend).observe(document.documentElement, {
                attributes: true,
                attributeFilter: ["class", "style"]
            });
        }

        if (document.body) {
            new MutationObserver(scheduleSend).observe(document.body, {
                attributes: true,
                attributeFilter: ["class", "style"]
            });
        }

        scheduleSend();
        window.setTimeout(scheduleSend, 300);
        window.setTimeout(scheduleSend, 1000);
        window.setInterval(scheduleSend, 750);
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "edgeColors"

        var onEdgeColorsChange: (UIColor, UIColor) -> Void

        init(onEdgeColorsChange: @escaping (UIColor, UIColor) -> Void) {
            self.onEdgeColorsChange = onEdgeColorsChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                message.name == Self.messageHandlerName,
                let body = message.body as? [String: String],
                let topString = body["top"],
                let bottomString = body["bottom"],
                let topColor = UIColor(cssColor: topString),
                let bottomColor = UIColor(cssColor: bottomString)
            else {
                return
            }

            onEdgeColorsChange(topColor, bottomColor)
        }
    }
}

private extension UIColor {
    convenience init?(cssColor: String) {
        let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            guard let value = UInt64(hex, radix: 16) else { return nil }

            switch hex.count {
            case 6:
                self.init(
                    red: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1
                )
            case 8:
                self.init(
                    red: CGFloat((value >> 24) & 0xFF) / 255,
                    green: CGFloat((value >> 16) & 0xFF) / 255,
                    blue: CGFloat((value >> 8) & 0xFF) / 255,
                    alpha: CGFloat(value & 0xFF) / 255
                )
            default:
                return nil
            }

            return
        }

        let pattern = #"rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let redRange = Range(match.range(at: 1), in: trimmed),
            let greenRange = Range(match.range(at: 2), in: trimmed),
            let blueRange = Range(match.range(at: 3), in: trimmed)
        else {
            return nil
        }

        let red = CGFloat(Double(trimmed[redRange]) ?? 0) / 255
        let green = CGFloat(Double(trimmed[greenRange]) ?? 0) / 255
        let blue = CGFloat(Double(trimmed[blueRange]) ?? 0) / 255

        let alpha: CGFloat
        if let alphaRange = Range(match.range(at: 4), in: trimmed) {
            alpha = CGFloat(Double(trimmed[alphaRange]) ?? 1)
        } else {
            alpha = 1
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func isVisuallyClose(to other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0

        guard
            getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        else {
            return false
        }

        return abs(red - otherRed) < tolerance
            && abs(green - otherGreen) < tolerance
            && abs(blue - otherBlue) < tolerance
            && abs(alpha - otherAlpha) < tolerance
    }
    var prefersLightStatusBarContent: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }

        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance < 0.5
    }
}

private struct StatusBarStyleView: UIViewControllerRepresentable {
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> StatusBarStyleViewController {
        let controller = StatusBarStyleViewController()
        controller.statusBarStyle = style
        return controller
    }

    func updateUIViewController(_ uiViewController: StatusBarStyleViewController, context: Context) {
        uiViewController.statusBarStyle = style
    }
}

private final class StatusBarStyleViewController: UIViewController {
    var statusBarStyle: UIStatusBarStyle = .darkContent {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }
}

#Preview {
    ContentView()
}
