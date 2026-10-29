import AppKit
import SwiftUI

// A local integration harness: real capture, real Responses client, real Keychain.
// Kept outside the synchronized app source folder and the production app target.
@MainActor
final class TAIntegrationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = TAAssistantModel()
    private var window: NSWindow?
    private var reader: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.automatic = false
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Textream TA Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Textream TA · Local Integration Test"
        window.minSize = NSSize(width: 520, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            VStack(spacing: 0) {
                Text("Local integration test · real audio and OpenAI API")
                    .font(.caption).padding(10).frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.08))
                TAAssistantView(model: model, onRead: { [weak self] text in
                    self?.showReader(text)
                })
            }
        )
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showReader(_ text: String) {
        reader?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = "TA reply · Reader test"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 12) {
                Text("Reader handoff test. The full Textream overlay is not part of this harness.")
                    .font(.caption).foregroundColor(.secondary)
                ScrollView {
                    Text(text).font(.system(size: 26)).lineSpacing(7)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(20)
        )
        reader = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.setEnabled(false)
        model.newStudent()
        reader?.close()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.setEnabled(false)
    }
}

@main
struct TAIntegrationMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = TAIntegrationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        _ = delegate
    }
}
