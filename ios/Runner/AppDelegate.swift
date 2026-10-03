import Flutter
import UIKit
import Photos
import os

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backupBridge: BackupBridge?
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
    backupBridge = BackupBridge(messenger: engineBridge.applicationRegistrar.messenger())
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


private final class BackupBridge: NSObject, UIDocumentPickerDelegate {
  private var channel: FlutterMethodChannel!
  private var pending: FlutterResult?
  private var exportURL: URL?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    channel = FlutterMethodChannel(name: "com.pipiele.antkeep/backup", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "resources":
        do {
          let directory = arguments?["path"] as? String ?? NSHomeDirectory()
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory)
          result([
            "availableMemory": UInt64(os_proc_available_memory()),
            "totalMemory": ProcessInfo.processInfo.physicalMemory,
            "freeDisk": (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
          ])
        } catch {
          result(FlutterError(code: "resources_failed", message: "无法获取设备资源信息", details: nil))
        }
      case "saveBackup":
        guard self.pending == nil else {
          result(FlutterError(code: "busy", message: "正在保存备份", details: nil))
          return
        }
        guard let path = arguments?["path"] as? String,
              let name = arguments?["name"] as? String,
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "invalid_file", message: "备份文件不存在", details: nil))
          return
        }
        do {
          // Rename within the operation directory so the document picker uses the
          // desired filename without another archive-sized in-memory copy.
          let source = URL(fileURLWithPath: path)
          let named = source.deletingLastPathComponent().appendingPathComponent(name)
          try FileManager.default.moveItem(at: source, to: named)
          guard var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
            throw NSError(domain: "AntKeepBackup", code: 1)
          }
          while let presented = presenter.presentedViewController { presenter = presented }
          self.pending = result
          self.exportURL = named
          let picker = UIDocumentPickerViewController(forExporting: [named], asCopy: true)
          picker.delegate = self
          presenter.present(picker, animated: true)
        } catch {
          result(FlutterError(code: "save_failed", message: "无法保存备份文件，请重试", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }

  private func finish(_ saved: Bool) {
    let callback = pending
    pending = nil
    exportURL = nil
    callback?(saved)
  }
}
