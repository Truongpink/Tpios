import UIKit
import WebKit
import ObjectiveC.runtime

enum TPIOSSaleRuntimeDiagnostics {

    static func inspectCurrentApp() -> String {
        let windows = visibleAppWindows()

        guard windows.isEmpty == false else {
            return "SALE DIAGNOSTIC\n\nKhông tìm thấy window ứng dụng."
        }

        var output = "SALE DIAGNOSTIC\n\n"
        output += "Windows: \(windows.count)\n\n"

        var webViewCount = 0
        var scrollViewCount = 0
        var controllerNames = Set<String>()
        var webViewDetails: [String] = []
        var scrollViewDetails: [String] = []

        for (index, window) in windows.enumerated() {
            let rootName = window.rootViewController.map {
                NSStringFromClass(type(of: $0))
            } ?? "<nil>"
            output += "WINDOW[\(index)] \(NSStringFromClass(type(of: window)))\n"
            output += "Root: \(rootName)\n"

            collectControllers(
                from: window.rootViewController,
                into: &controllerNames
            )

            collectViews(
                from: window,
                webViewCount: &webViewCount,
                scrollViewCount: &scrollViewCount,
                webViewDetails: &webViewDetails,
                scrollViewDetails: &scrollViewDetails
            )
        }

        output += "\nCONTROLLERS\n"
        if controllerNames.isEmpty {
            output += "Không phát hiện.\n"
        } else {
            for name in controllerNames.sorted().prefix(30) {
                output += "\(name)\n"
            }
        }

        output += "\nWEBVIEWS: \(webViewCount)\n"
        if webViewDetails.isEmpty {
            output += "Không có WKWebView.\n"
        } else {
            for item in webViewDetails.prefix(10) {
                output += "\(item)\n"
            }
        }

        output += "\nSCROLLVIEWS: \(scrollViewCount)\n"
        if scrollViewDetails.isEmpty {
            output += "Không phát hiện UIScrollView.\n"
        } else {
            for item in scrollViewDetails.prefix(20) {
                output += "\(item)\n"
            }
        }

        output += "\nKẾT LUẬN\n"
        if webViewCount > 0 {
            output += "Có WKWebView → ưu tiên nghiên cứu DOM/JS và URL trang hiện tại."
        } else if scrollViewCount > 0 {
            output += "Không có WKWebView → ưu tiên phân tích Native/RN và delegate/refresh component."
        } else {
            output += "Chưa xác định được tầng render của màn hình."
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
        webViewCount: inout Int,
        scrollViewCount: inout Int,
        webViewDetails: inout [String],
        scrollViewDetails: inout [String]
    ) {
        if let webView = view as? WKWebView {
            webViewCount += 1

            let urlText: String
            if let url = webView.url {
                urlText = "(url.host ?? "<no-host>")\(url.path)"
            } else {
                urlText = "<nil>"
            }

            webViewDetails.append(
                "WKWebView url=\(urlText) title=\(webView.title ?? "<nil>")"
            )
        }

        if let scrollView = view as? UIScrollView {
            scrollViewCount += 1

            let className = NSStringFromClass(type(of: scrollView))
            let delegateName = scrollView.delegate.map {
                NSStringFromClass(type(of: $0))
            } ?? "<nil>"

            let refreshName: String
            if let refresh = scrollView.refreshControl {
                refreshName = NSStringFromClass(type(of: refresh))
            } else {
                refreshName = "<nil>"
            }

            scrollViewDetails.append(
                "UIScrollView class=\(className) delegate=\(delegateName) refresh=\(refreshName)"
            )
        }

        for child in view.subviews {
            collectViews(
                from: child,
                webViewCount: &webViewCount,
                scrollViewCount: &scrollViewCount,
                webViewDetails: &webViewDetails,
                scrollViewDetails: &scrollViewDetails
            )
        }
    }
}
