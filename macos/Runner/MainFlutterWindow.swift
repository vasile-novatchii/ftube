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

    super.awakeFromNib()
  }

  // Dragging an edge is a live resize: keep the size. Zoom and full screen
  // still resize the window (docs/spec-v0.2.md D-20).
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    sender.inLiveResize ? sender.frame.size : frameSize
  }
}
