import UIKit
import WebKit
import ObjectiveC.runtime

enum TPIOSSaleRuntimeDiagnostics {

    static func inspectCurrentApp() -> String {
        let windows = visibleAppWindows()

        guard windows.isEmpty == false else {
            return "SALE DIAGNOSTIC\n\nKhông tìm thấy window ứng dụng."
        }

        var output = "SALE DEEP DIAGNOSTIC\n\n"
        output += "Windows: \(windows.count)\n"

        var webViews: [WKWebView] = []
        var scrollViews: [UIScrollView] = []
        var controllerNames = Set<String>()
        var matchedNativeClasses = Set<String>()
        var matchedSelectors = Set<String>()

        let keywords = [
            "sale", "product", "item", "price", "voucher", "coupon",
            "discount", "promotion", "promo", "shipping", "freeship",
            "refresh", "reload", "home", "detail", "cart", "checkout",
            "shopee"
        ]

        for (index, window) in windows.enumerated() {
            let rootName = window.rootViewController.map {
                NSStringFromClass(type(of: $0))
            } ?? "<nil>"

            output += "\nWINDOW[\(index)] class=\(NSStringFromClass(type(of: window)))\n"
            output += "Root=\(rootName)\n"

            collectControllers(
                from: window.rootViewController,
                into: &controllerNames
            )

            collectRuntimeMatches(
                from: window,
                keywords: keywords,
                classes: &matchedNativeClasses,
                selectors: &matchedSelectors
            )

            collectViews(
                from: window,
                webViews: &webViews,
                scrollViews: &scrollViews
            )
        }

        output += "\n=== CONTROLLERS ===\n"
        if controllerNames.isEmpty {
            output += "Không phát hiện.\n"
        } else {
            for name in controllerNames.sorted().prefix(60) {
                output += "\(name)\n"
            }
        }

        output += "\n=== NATIVE MATCHES ===\n"
        if matchedNativeClasses.isEmpty {
            output += "Không có class khớp từ khóa.\n"
        } else {
            for name in matchedNativeClasses.sorted().prefix(80) {
                output += "\(name)\n"
            }
        }

        output += "\n=== SELECTOR MATCHES ===\n"
        if matchedSelectors.isEmpty {
            output += "Không có selector khớp từ khóa.\n"
        } else {
            for name in matchedSelectors.sorted().prefix(120) {
                output += "\(name)\n"
            }
        }

        output += "\n=== WEBVIEWS: \(webViews.count) ===\n"
        if webViews.isEmpty {
            output += "Không có WKWebView.\n"
        } else {
            for (index, webView) in webViews.prefix(10).enumerated() {
                let url = webView.url?.absoluteString ?? "<nil>"
                let title = webView.title ?? "<nil>"
                output += "WEBVIEW[\(index)] url=\(url) title=\(title)\n"

                inspectWebView(
                    webView,
                    index: index
                )
            }
        }

        output += "\n=== SCROLLVIEWS: \(scrollViews.count) ===\n"
        if scrollViews.isEmpty {
            output += "Không phát hiện UIScrollView.\n"
        } else {
            for (index, scrollView) in scrollViews.prefix(40).enumerated() {
                let className = NSStringFromClass(type(of: scrollView))
                let delegate = scrollView.delegate.map {
                    NSStringFromClass(type(of: $0))
                } ?? "<nil>"

                let refresh = scrollView.refreshControl.map {
                    NSStringFromClass(type(of: $0))
                } ?? "<nil>"

                let frame = scrollView.convert(scrollView.bounds, to: nil)

                output += """
                SCROLL[\(index)] class=\(className)
                delegate=\(delegate)
                refresh=\(refresh)
                frame=\(frame)
                content=\(scrollView.contentSize)
                """

                output += "\n"
            }
        }

        output += """
        
        === KẾT LUẬN ===
        """

        if !webViews.isEmpty {
            output += "\nCó WKWebView. Bước tiếp theo là đọc DOM có kiểm soát để xác định product/price/voucher và endpoint tài nguyên của màn hình hiện tại."
        } else if !scrollViews.isEmpty {
            output += "\nKhông có WKWebView. Bước tiếp theo là đào sâu Native/RN: class hierarchy, selector refresh/data, delegate và component chứa text/giá/voucher."
        } else {
            output += "\nChưa xác định được tầng render."
        }

        return output
    }

    private static func visibleAppWindows() -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }

        var windows: [UIWindow] = []

        for scene in scenes where scene.activationState != .unattached {
            for window in scene.windows {
                guard window.isHidden == false,
                      window.alpha > 0.01,
                      window.bounds.width > 0,
                      window.bounds.height > 0 else {
                    continue
                }

                let className = NSStringFromClass(type(of: window))
                if className.contains("TPIOS") {
                    continue
                }

                windows.append(window)
            }
        }

        return windows
    }

    private static func collectControllers(
        from controller: UIViewController?,
        into names: inout Set<String>
    ) {
        guard let controller else {
            return
        }

        names.insert(NSStringFromClass(type(of: controller)))

        if let presented = controller.presentedViewController {
            collectControllers(from: presented, into: &names)
        }

        for child in controller.children {
            collectControllers(from: child, into: &names)
        }

        if let navigation = controller as? UINavigationController {
            for child in navigation.viewControllers {
                collectControllers(from: child, into: &names)
            }
        }

        if let tab = controller as? UITabBarController {
            for child in tab.viewControllers ?? [] {
                collectControllers(from: child, into: &names)
            }
        }
    }

    private static func collectViews(
        from view: UIView,
        webViews: inout [WKWebView],
        scrollViews: inout [UIScrollView]
    ) {
        if let webView = view as? WKWebView {
            webViews.append(webView)
        }

        if let scrollView = view as? UIScrollView {
            scrollViews.append(scrollView)
        }

        for child in view.subviews {
            collectViews(
                from: child,
                webViews: &webViews,
                scrollViews: &scrollViews
            )
        }
    }

    private static func collectRuntimeMatches(
        from view: UIView,
        keywords: [String],
        classes: inout Set<String>,
        selectors: inout Set<String>
    ) {
        let className = NSStringFromClass(type(of: view))
        let lowerClass = className.lowercased()

        if keywords.contains(where: { lowerClass.contains($0) }) {
            classes.insert(className)
        }

        var methodCount: UInt32 = 0

        if let methods = class_copyMethodList(type(of: view), &methodCount) {
            defer {
                free(methods)
            }

            for index in 0..<Int(methodCount) {
                let selector = method_getName(methods[index])
                let selectorName = NSStringFromSelector(selector)
                let lowerSelector = selectorName.lowercased()

                if keywords.contains(where: { lowerSelector.contains($0) }) {
                    selectors.insert("\(className).\(selectorName)")
                }
            }
        }

        for child in view.subviews {
            collectRuntimeMatches(
                from: child,
                keywords: keywords,
                classes: &classes,
                selectors: &selectors
            )
        }
    }

    private static func inspectWebView(
        _ webView: WKWebView,
        index: Int
    ) {
        let script = """
        (function() {
            const terms = [
                "price", "voucher", "coupon", "discount",
                "promotion", "promo", "freeship", "shipping",
                "product", "item", "sale", "shop"
            ];

            function clean(value) {
                return String(value || "")
                    .replace(/\\s+/g, " ")
                    .trim()
                    .slice(0, 180);
            }

            const nodes = Array.from(
                document.querySelectorAll(
                    "body *"
                )
            ).filter(el => {
                const text = clean(el.innerText);
                if (!text) return false;
                const lower = text.toLowerCase();
                return terms.some(term => lower.includes(term));
            }).slice(0, 80).map(el => ({
                tag: el.tagName,
                id: clean(el.id),
                cls: typeof el.className === "string" ? clean(el.className) : "",
                text: clean(el.innerText)
            }));

            const resources = performance
                .getEntriesByType("resource")
                .map(x => x.name)
                .filter(Boolean)
                .slice(-100);

            return JSON.stringify({
                href: location.href,
                title: document.title,
                htmlLength: document.documentElement
                    ? document.documentElement.outerHTML.length
                    : 0,
                bodyTextLength: document.body
                    ? document.body.innerText.length
                    : 0,
                nodes: nodes,
                resources: resources
            });
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                TPIOSLog.shared.log(
                    "SaleDeep: WEBVIEW[\(index)] JS ERROR \(error.localizedDescription)"
                )
                return
            }

            guard let value = result as? String else {
                TPIOSLog.shared.log(
                    "SaleDeep: WEBVIEW[\(index)] JS result không phải String"
                )
                return
            }

            TPIOSLog.shared.log(
                "SaleDeep: WEBVIEW[\(index)] DOM \(value)"
            )
        }
    }
}
