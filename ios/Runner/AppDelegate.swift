import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var localStorageChannel: FlutterMethodChannel?
  private var shareImageChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    shareImageChannel = FlutterMethodChannel(
      name: "com.pipiele.antkeep/share_image",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shareImageChannel?.setMethodCallHandler { call, result in
      guard call.method == "saveImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let bytes = arguments["bytes"] as? FlutterStandardTypedData,
            UIImage(data: bytes.data) != nil else {
        result(FlutterError(code: "invalid_image", message: "无效的图片", details: nil))
        return
      }
      let save: (PHAuthorizationStatus) -> Void = { status in
        guard status == .authorized else {
          DispatchQueue.main.async {
            result(FlutterError(code: "permission_denied", message: "未获得保存照片权限", details: nil))
          }
          return
        }
        PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCreationRequest.forAsset()
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = arguments["name"] as? String
          request.addResource(with: .photo, data: bytes.data, options: options)
        }) { success, _ in
          DispatchQueue.main.async {
            if success { result("已保存到相册") }
            else { result(FlutterError(code: "save_failed", message: "图片保存失败，请重试", details: nil)) }
          }
        }
      }
      if #available(iOS 14, *) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: save)
      } else {
        PHPhotoLibrary.requestAuthorization(save)
      }
    }
    localStorageChannel = FlutterMethodChannel(
      name: "com.pipiele.antkeep/storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    localStorageChannel?.setMethodCallHandler { call, result in
      guard call.method == "excludeFromCloudBackup",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "backup_exclusion_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
