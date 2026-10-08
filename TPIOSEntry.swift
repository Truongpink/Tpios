import UIKit

@_cdecl("TPIOSStart")
public func TPIOSStart() {
    TPIOSCartBody.shared.install()

    DispatchQueue.main.async {
        TPIOSController.shared.start()
    }
}

@_cdecl("TPIOSStop")
public func TPIOSStop() {
    DispatchQueue.main.async {
        TPIOSController.shared.stop()
    }
}