import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Tray-only app: the engine only runs main() once this window is shown, so
    // we can't suppress it. Make it fully transparent and shadowless so the
    // brief moment before Dart's window_manager.hide() is imperceptible.
    self.alphaValue = 0
    self.hasShadow = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
