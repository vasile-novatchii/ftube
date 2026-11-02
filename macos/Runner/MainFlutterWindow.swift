import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.delegate = self
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerTrashChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // See FileSystemService.trash in lib/data/services/.
  private func registerTrashChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "io.github.infvyr.ftube/trash", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "trash",
        let args = call.arguments as? [String: Any],
        let paths = args["paths"] as? [String]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      var moved: [String] = []
      var firstError: String?
      for path in paths {
        do {
          try FileManager.default.trashItem(
            at: URL(fileURLWithPath: path), resultingItemURL: nil)
          moved.append(path)
        } catch {
          if firstError == nil { firstError = "\(path): \(error.localizedDescription)" }
        }
      }
      result(["moved": moved, "error": firstError.map { $0 as Any } ?? NSNull()])
    }
  }

  // Dragging an edge is a live resize: keep the size. Zoom and full screen
  // still resize the window (docs/spec-v0.2.md D-20).
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    sender.inLiveResize ? sender.frame.size : frameSize
  }
}
