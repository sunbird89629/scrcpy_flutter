import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var trackingArea: NSTrackingArea?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    setWindowButtonsHidden(true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    setupTracking()
  }

  private func setupTracking() {
    guard let contentView = self.contentView else { return }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: contentView.bounds, options: options, owner: self, userInfo: nil)
    contentView.addTrackingArea(trackingArea!)
  }

  private func setWindowButtonsHidden(_ hidden: Bool) {
    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
      self.standardWindowButton($0)?.isHidden = hidden
    }
  }

  override func mouseEntered(with event: NSEvent) {
    setWindowButtonsHidden(false)
  }

  override func mouseExited(with event: NSEvent) {
    setWindowButtonsHidden(true)
  }
}
