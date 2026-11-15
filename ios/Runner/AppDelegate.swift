import AVFoundation
import CommonCrypto
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
      let a = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "merge":
        guard let out = a["out"] as? String else { return result(FlutterMethodNotImplemented) }
        AppDelegate.merge(
          video: a["video"] as? String,
          audio: a["audio"] as? String,
          out: out,
          audioOnly: a["audioOnly"] as? Bool ?? false,
          result: result
        )
      case "finish":
        guard let input = a["input"] as? String, let out = a["out"] as? String else {
          return result(FlutterMethodNotImplemented)
        }
        AppDelegate.finish(input: input, out: out, audioOnly: a["audioOnly"] as? Bool ?? false, result: result)
      case "probe":
        guard let path = a["path"] as? String else { return result(FlutterMethodNotImplemented) }
        DispatchQueue.global(qos: .userInitiated).async {
          let info = AppDelegate.probe(path: path, decode: a["decode"] as? Bool ?? false)
          DispatchQueue.main.async { result(info) }
        }
      case "decrypt":
        guard let path = a["path"] as? String,
              let key = a["key"] as? FlutterStandardTypedData,
              let iv = a["iv"] as? FlutterStandardTypedData else { return result(FlutterMethodNotImplemented) }
        DispatchQueue.global(qos: .userInitiated).async {
          let error = AppDelegate.decrypt(path: path, key: key.data, iv: iv.data)
          DispatchQueue.main.async {
            result(error.map { FlutterError(code: "decrypt", message: $0, details: nil) })
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func merge(video: String?, audio: String?, out: String, audioOnly: Bool, result: @escaping FlutterResult) {
    func fail(_ message: String) {
      DispatchQueue.main.async { result(FlutterError(code: "merge", message: message, details: nil)) }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let v = video.map { AVURLAsset(url: URL(fileURLWithPath: $0)) }
      let a = audio.map { AVURLAsset(url: URL(fileURLWithPath: $0)) } ?? v
      let tracks = [audioOnly ? nil : v?.tracks(withMediaType: .video).first, a?.tracks(withMediaType: .audio).first]
        .compactMap { $0 }
      guard !tracks.isEmpty else { return fail("No video or audio track found") }
      // Stream pieces often don't start at time 0; keep the tracks' offsets
      // relative to each other so sound stays in sync.
      let start = tracks.map { $0.timeRange.start }.min() ?? .zero
      let comp = AVMutableComposition()
      do {
        for t in tracks {
          try comp.addMutableTrack(withMediaType: t.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(t.timeRange, of: t, at: CMTimeSubtract(t.timeRange.start, start))
        }
      } catch {
        return fail(error.localizedDescription)
      }
      let outURL = URL(fileURLWithPath: out)
      try? FileManager.default.removeItem(at: outURL)
      guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
        return fail("Can't join these streams")
      }
      export.outputURL = outURL
      export.outputFileType = audioOnly ? .m4a : .mp4
      export.exportAsynchronously {
        if export.status == .completed {
          DispatchQueue.main.async { result(nil) }
        } else {
          fail(export.error?.localizedDescription ?? "Join failed")
        }
      }
    }
  }

  private static func finish(input: String, out: String, audioOnly: Bool, result: @escaping FlutterResult) {
    // The muxer writes fragmented MP4. When AVFoundation can read every track,
    // rewrite it as a regular MP4 (widest compatibility, e.g. Photos);
    // otherwise (say VP9 or Opus on an older iPhone) the fragmented file stays.
    DispatchQueue.global(qos: .userInitiated).async {
      let asset = AVURLAsset(url: URL(fileURLWithPath: input))
      let outURL = URL(fileURLWithPath: out)
      try? FileManager.default.removeItem(at: outURL)
      guard !asset.tracks.isEmpty, asset.tracks.allSatisfy({ $0.isPlayable }),
            let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
        return DispatchQueue.main.async { result(false) }
      }
      export.outputURL = outURL
      export.outputFileType = audioOnly ? .m4a : .mp4
      export.shouldOptimizeForNetworkUse = true
      export.exportAsynchronously {
        let ok = export.status == .completed
        if !ok { try? FileManager.default.removeItem(at: outURL) }
        DispatchQueue.main.async { result(ok) }
      }
    }
  }

  private static func probe(path: String, decode: Bool) -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    func fourcc(_ v: FourCharCode) -> String {
      String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "?"
    }
    var tracks: [[String: Any]] = []
    for t in asset.tracks {
      let desc = t.formatDescriptions.first.map { $0 as! CMFormatDescription }
      var entry: [String: Any] = [
        "type": t.mediaType.rawValue,
        "codec": desc.map { fourcc(CMFormatDescriptionGetMediaSubType($0)) } ?? "?",
        "width": Int(t.naturalSize.width),
        "height": Int(t.naturalSize.height),
        "playable": t.isPlayable,
        "decodable": t.isDecodable,
        "seconds": CMTimeGetSeconds(t.timeRange.duration),
      ]
      if decode, let reader = try? AVAssetReader(asset: asset) {
        let settings: [String: Any] = t.mediaType == .video
          ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
          : [AVFormatIDKey: kAudioFormatLinearPCM]
        let output = AVAssetReaderTrackOutput(track: t, outputSettings: settings)
        if reader.canAdd(output) {
          reader.add(output)
          reader.startReading()
          var samples = 0
          while let buffer = output.copyNextSampleBuffer() {
            samples += t.mediaType == .video ? (CMSampleBufferGetImageBuffer(buffer) != nil ? 1 : 0)
              : CMSampleBufferGetNumSamples(buffer)
          }
          entry["decoded"] = samples
          entry["readerCompleted"] = reader.status == .completed
          entry["readerError"] = reader.error?.localizedDescription ?? ""
        }
      }
      tracks.append(entry)
    }
    return [
      "playable": asset.isPlayable,
      "exportable": asset.isExportable,
      "seconds": CMTimeGetSeconds(asset.duration),
      "tracks": tracks,
    ]
  }

  private static func decrypt(path: String, key: Data, iv: Data) -> String? {
    let url = URL(fileURLWithPath: path)
    guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128, let input = try? Data(contentsOf: url) else {
      return "Can't read the encrypted piece"
    }
    var output = Data(count: input.count + kCCBlockSizeAES128)
    let capacity = output.count
    var moved = 0
    let status = output.withUnsafeMutableBytes { out in
      input.withUnsafeBytes { inp in
        key.withUnsafeBytes { k in
          iv.withUnsafeBytes { v in
            CCCrypt(
              CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
              k.baseAddress, kCCKeySizeAES128, v.baseAddress,
              inp.baseAddress, inp.count, out.baseAddress, capacity, &moved
            )
          }
        }
      }
    }
    guard status == CCCryptorStatus(kCCSuccess) else { return "Decryption failed (\(status))" }
    output.removeSubrange(moved..<output.count)
    do {
      try output.write(to: url)
    } catch {
      return error.localizedDescription
    }
    return nil
  }
}
