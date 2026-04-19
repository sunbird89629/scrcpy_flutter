import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let initialSize = NSSize(width: 1280, height: 800)
    let minSize = NSSize(width: 1024, height: 640)

    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let originX = screenFrame.midX - initialSize.width / 2
      let originY = screenFrame.midY - initialSize.height / 2
      self.setFrame(
        NSRect(x: originX, y: originY,
               width: initialSize.width, height: initialSize.height),
        display: true
      )
    } else {
      self.setFrame(
        NSRect(x: 0, y: 0,
               width: initialSize.width, height: initialSize.height),
        display: true
      )
    }
    self.minSize = minSize
    self.title = "AutoGLM"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
