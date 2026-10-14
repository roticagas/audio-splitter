import Cocoa
import FlutterMacOS
import AVFoundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 960, height: 760)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()
    self.minSize = NSSize(width: 850, height: 680)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "audio_splitter/native", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getAudioDuration" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing filePath", details: nil))
          return
        }
        let url = URL(fileURLWithPath: filePath)
        let asset = AVAsset(url: url)
        if #available(macOS 12.0, *) {
          Task {
            do {
              let duration = try await asset.load(.duration)
              let seconds = CMTimeGetSeconds(duration)
              result(seconds)
            } catch {
              result(FlutterError(code: "AV_ERROR", message: error.localizedDescription, details: nil))
            }
          }
        } else {
          let seconds = CMTimeGetSeconds(asset.duration)
          result(seconds)
        }
      } else if call.method == "splitAudioSegment" {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let startTime = args["startTime"] as? Double,
              let duration = args["duration"] as? Double else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid split parameters", details: nil))
          return
        }

        let inputUrl = URL(fileURLWithPath: inputPath)
        let outputUrl = URL(fileURLWithPath: outputPath)

        // Ensure output parent directory exists
        let parentDir = outputUrl.deletingLastPathComponent()
        do {
          try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
          result(FlutterError(code: "DIR_CREATE_ERROR", message: "Failed to create output directory: \(error.localizedDescription)", details: nil))
          return
        }

        let asset = AVAsset(url: inputUrl)
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)

        var presetsToTry: [String] = []
        if compatiblePresets.contains(AVAssetExportPresetAppleM4A) {
          presetsToTry.append(AVAssetExportPresetAppleM4A)
        }
        if compatiblePresets.contains(AVAssetExportPresetPassthrough) {
          presetsToTry.append(AVAssetExportPresetPassthrough)
        }
        if presetsToTry.isEmpty {
          presetsToTry = [AVAssetExportPresetAppleM4A, AVAssetExportPresetPassthrough]
        }

        self.exportWithPresets(asset: asset, outputUrl: outputUrl, startTime: startTime, duration: duration, presets: presetsToTry, index: 0, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func exportWithPresets(asset: AVAsset, outputUrl: URL, startTime: Double, duration: Double, presets: [String], index: Int, result: @escaping FlutterResult) {
    guard index < presets.count else {
      result(FlutterError(code: "EXPORT_ERROR", message: "All export presets failed.", details: nil))
      return
    }

    let preset = presets[index]
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      self.exportWithPresets(asset: asset, outputUrl: outputUrl, startTime: startTime, duration: duration, presets: presets, index: index + 1, result: result)
      return
    }

    // Remove output file if already exists
    try? FileManager.default.removeItem(at: outputUrl)

    session.outputURL = outputUrl
    session.outputFileType = .m4a

    let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
    let durCM = CMTime(seconds: duration, preferredTimescale: 600)
    session.timeRange = CMTimeRange(start: startCM, duration: durCM)

    session.exportAsynchronously {
      DispatchQueue.main.async {
        if session.status == .completed {
          result(true)
        } else {
          if index + 1 < presets.count {
            self.exportWithPresets(asset: asset, outputUrl: outputUrl, startTime: startTime, duration: duration, presets: presets, index: index + 1, result: result)
          } else {
            let errMessage = session.error?.localizedDescription ?? "Unknown export error"
            result(FlutterError(code: "EXPORT_ERROR", message: errMessage, details: nil))
          }
        }
      }
    }
  }
}

