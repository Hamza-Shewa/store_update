import Flutter
import StoreKit
import UIKit

/// Shows the app's App Store page over the app for the update prompt
/// (lib/src/method_channel_store_update.dart). Channel `store_update`:
/// `openStore` {trackId, url} answers true once the in-app store page (or,
/// failing that, the App Store app) is shown, false when neither could open.
public class StoreUpdatePlugin: NSObject, FlutterPlugin, SKStoreProductViewControllerDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "store_update", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(StoreUpdatePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openStore":
      let args = call.arguments as? [String: Any]
      let trackId = (args?["trackId"] as? NSNumber)?.intValue
      let url = (args?["url"] as? String).flatMap(URL.init(string:))
      openStore(trackId: trackId, url: url, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openStore(trackId: Int?, url: URL?, result: @escaping FlutterResult) {
    guard let trackId = trackId, let top = StoreUpdatePlugin.topViewController() else {
      openLink(url, result: result)
      return
    }
    let store = SKStoreProductViewController()
    store.delegate = self
    let parameters = [SKStoreProductParameterITunesItemIdentifier: NSNumber(value: trackId)]
    // Captures self strongly: the closure is short-lived, and `result` must be
    // called on every path.
    store.loadProduct(withParameters: parameters) { loaded, _ in
      DispatchQueue.main.async {
        if loaded {
          top.present(store, animated: true)
          result(true)
        } else {
          self.openLink(url, result: result)
        }
      }
    }
  }

  private func openLink(_ url: URL?, result: @escaping FlutterResult) {
    guard let url = url else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    viewController.dismiss(animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
