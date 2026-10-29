import AppKit
import SwiftUI

// A local integration harness: real capture, real Responses client, real Keychain.
// Kept outside the synchronized app source folder and the production app target.
@MainActor
final class TAIntegrationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = TAAssistantModel()
    private var window: NSWindow?
    private let notch = TANotchController()

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
                HStack {
                    Text("TA assistant · real audio and OpenAI API").font(.caption)
                    Spacer()
                    Button("预览刘海字幕") { [weak self] in self?.previewNotch() }
                }.padding(10).frame(maxWidth: .infinity)
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
        model.pauseAudio()
        notch.show(text: text, title: "TA 回复 · \(model.model)")
    }

    private func previewNotch() {
        model.pauseAudio()
        if !model.answer.isEmpty {
            showReader(model.answer)
        } else {
            notch.show(text: "这是刘海字幕的显示效果。字幕固定在屏幕顶部，切换到会议或浏览器时仍然可见。\n\n你可以用滚轮阅读，点击播放让字幕缓慢滚动，用 A− / A+ 调整字号。\n\n生成 Terra 回复后，点击 Read in prompter，就会在这里显示真实回复。点击右上角 × 或在字幕获得焦点时按 Esc 关闭。", title: "刘海字幕 · 预览")
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.setEnabled(false)
        model.newStudent()
        notch.close()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.setEnabled(false)
        notch.close()
    }
}

// A native top-attached overlay that builds with Xcode 14. This uses the same
// panel placement/level as Textream, without depending on its newer Swift UI.
private final class TANotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
private final class TANotchState: ObservableObject {
    @Published var fontSize: CGFloat = 24
    @Published var scrolling = false
    @Published var restart = 0
    @Published var progress: CGFloat = 0
}

@MainActor
private final class TANotchController {
    private var panel: TANotchPanel?
    private var state = TANotchState()
    private var screenIndex = 0
    private var text = ""
    private var title = ""
    private var screenObserver: NSObjectProtocol?

    func show(text: String, title: String) {
        close()
        guard !NSScreen.screens.isEmpty else { return }
        self.text = text
        self.title = title
        state = TANotchState()
        // Prefer the physical camera notch; the display button can move it.
        screenIndex = NSScreen.screens.firstIndex(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.screens.firstIndex(where: { $0 == NSScreen.main }) ?? 0
        let panel = TANotchPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.title = "Textream TA · 刘海字幕"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.onEscape = { [weak self] in self?.close() }
        self.panel = panel
        placePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in DispatchQueue.main.async { [weak self] in self?.placePanel() } }
    }

    private func placePanel() {
        guard let panel, !NSScreen.screens.isEmpty else { close(); return }
        screenIndex = min(screenIndex, NSScreen.screens.count - 1)
        let screen = NSScreen.screens[screenIndex]
        let topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let width = min(CGFloat(700), screen.frame.width - 32)
        let height = topInset + 218
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2,
                              y: screen.frame.maxY - height,
                              width: width, height: height), display: true)
        panel.contentView = NSHostingView(rootView: TANotchView(
            state: state, text: text, title: title, topInset: topInset,
            screenName: screen.localizedName, hasMultipleScreens: NSScreen.screens.count > 1,
            onScreen: { [weak self] in self?.nextScreen() },
            onClose: { [weak self] in self?.close() }
        ))
    }

    private func nextScreen() {
        guard !NSScreen.screens.isEmpty else { return }
        screenIndex = (screenIndex + 1) % NSScreen.screens.count
        placePanel()
    }

    func close() {
        state.scrolling = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

private struct TANotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - 12, y: 12), control: CGPoint(x: w - 12, y: 0))
        p.addLine(to: CGPoint(x: w - 12, y: h - 26))
        p.addQuadCurve(to: CGPoint(x: w - 38, y: h), control: CGPoint(x: w - 12, y: h))
        p.addLine(to: CGPoint(x: 38, y: h))
        p.addQuadCurve(to: CGPoint(x: 12, y: h - 26), control: CGPoint(x: 12, y: h))
        p.addLine(to: CGPoint(x: 12, y: 12))
        p.addQuadCurve(to: .zero, control: CGPoint(x: 12, y: 0))
        p.closeSubpath()
        return p
    }
}

@MainActor
private struct TANotchView: View {
    @ObservedObject var state: TANotchState
    let text: String
    let title: String
    let topInset: CGFloat
    let screenName: String
    let hasMultipleScreens: Bool
    let onScreen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: topInset)
            HStack(spacing: 10) {
                Circle().fill(Color.mint).frame(width: 6, height: 6)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button("A−") { state.fontSize = max(18, state.fontSize - 2) }
                    .help("缩小字幕")
                Button("A+") { state.fontSize = min(36, state.fontSize + 2) }
                    .help("放大字幕")
                Button { state.restart += 1 } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("回到开头").help("回到开头")
                Button { state.scrolling.toggle() } label: {
                    Image(systemName: state.scrolling ? "pause.fill" : "play.fill")
                }.accessibilityLabel(state.scrolling ? "暂停滚动" : "自动滚动")
                    .help(state.scrolling ? "暂停滚动" : "自动滚动")
                if hasMultipleScreens {
                    Button(action: onScreen) { Image(systemName: "display.2") }
                        .accessibilityLabel("切换屏幕").help("切换屏幕 · 当前：\(screenName)")
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("关闭刘海字幕").help("关闭刘海字幕")
            }.font(.system(size: 13)).buttonStyle(.plain).foregroundColor(.white.opacity(0.78))
            TANotchText(text: text, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(state.scrolling ? "自动滚动中" : "滚轮阅读 · 点击 ▶ 自动滚动")
                Spacer()
                Text("\(Int(state.fontSize)) pt")
            }.font(.system(size: 10)).foregroundColor(.white.opacity(0.42))
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color.mint.opacity(0.85)).frame(width: geo.size.width * state.progress)
            }.frame(height: 2)
        }
        .padding(.horizontal, 34).padding(.bottom, 19)
        .background(TANotchShape().fill(Color.black))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private struct TANotchText: NSViewRepresentable {
    let text: String
    @ObservedObject var state: TANotchState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 140))
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 0, height: 5)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        context.coordinator.start(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        if coordinator.text != text || coordinator.fontSize != state.fontSize {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 7
            view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: state.fontSize, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style
            ]))
            coordinator.text = text
            coordinator.fontSize = state.fontSize
        }
        if coordinator.restart != state.restart {
            coordinator.restart = state.restart
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator {
        let state: TANotchState
        var text = ""
        var fontSize: CGFloat = 0
        var restart = 0
        private var timer: Timer?
        private var scrollObserver: NSObjectProtocol?

        init(state: TANotchState) { self.state = state }

        func start(_ scroll: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
            ) { [weak self] _ in DispatchQueue.main.async { [weak self] in self?.state.scrolling = false } }
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self, weak scroll] _ in
                DispatchQueue.main.async { [weak self, weak scroll] in if let scroll { self?.tick(scroll) } }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func tick(_ scroll: NSScrollView) {
            guard timer != nil, let view = scroll.documentView as? NSTextView,
                  let container = view.textContainer, let layout = view.layoutManager else { return }
            let width = scroll.contentSize.width
            guard width > 0 else { return }
            if abs(container.containerSize.width - width) > 0.5 {
                container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            }
            layout.ensureLayout(for: container)
            let height = max(scroll.contentSize.height, layout.usedRect(for: container).maxY + 10)
            if abs(view.frame.height - height) > 1 || abs(view.frame.width - width) > 0.5 {
                view.setFrameSize(NSSize(width: width, height: height))
            }
            let end = max(0, height - scroll.contentSize.height)
            let y = max(0, min(end, scroll.contentView.bounds.minY))
            if state.scrolling {
                let next = min(end, y + 18.0 / 30)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: next))
                scroll.reflectScrolledClipView(scroll.contentView)
                if next >= end { state.scrolling = false }
            }
            let progress = end > 0 ? min(1, max(0, scroll.contentView.bounds.minY / end)) : 1
            if abs(state.progress - progress) > 0.002 { state.progress = progress }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
        }

        deinit { timer?.invalidate(); if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
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
