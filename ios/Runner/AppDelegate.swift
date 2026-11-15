import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "Toomu")?.messenger() else { return }

    // Android-only features (PiP, notifications, share intents): answer nil so Dart sees "off" instead of MissingPluginException.
    for name in ["toomu/video", "toomu/download_notify", "toomu/intents"] {
      FlutterMethodChannel(name: name, binaryMessenger: messenger).setMethodCallHandler { _, result in result(nil) }
    }

    FlutterMethodChannel(name: "toomu/media_merge", binaryMessenger: messenger).setMethodCallHandler { call, result in
      guard call.method == "merge", let a = call.arguments as? [String: String],
            let video = a["video"], let audio = a["audio"], let out = a["out"] else {
        return result(FlutterMethodNotImplemented)
      }
      AppDelegate.merge(video: video, audio: audio, out: out, result: result)
    }
  }

  private static func merge(video: String, audio: String, out: String, result: @escaping FlutterResult) {
    func fail(_ message: String) {
      DispatchQueue.main.async { result(FlutterError(code: "merge", message: message, details: nil)) }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let v = AVURLAsset(url: URL(fileURLWithPath: video))
      let a = AVURLAsset(url: URL(fileURLWithPath: audio))
      guard let vt = v.tracks(withMediaType: .video).first, let at = a.tracks(withMediaType: .audio).first else {
        return fail("Missing video or audio track")
      }
      let comp = AVMutableComposition()
      do {
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
          .insertTimeRange(CMTimeRange(start: .zero, duration: v.duration), of: vt, at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
          .insertTimeRange(CMTimeRange(start: .zero, duration: min(v.duration, a.duration)), of: at, at: .zero)
      } catch {
        return fail(error.localizedDescription)
      }
      let outURL = URL(fileURLWithPath: out)
      try? FileManager.default.removeItem(at: outURL)
      guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
        return fail("Can't join these streams")
      }
      export.outputURL = outURL
      export.outputFileType = .mp4
      export.exportAsynchronously {
        if export.status == .completed {
          DispatchQueue.main.async { result(nil) }
        } else {
          fail(export.error?.localizedDescription ?? "Join failed")
        }
      }
    }
  }
}
