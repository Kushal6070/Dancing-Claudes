import AppKit
import SwiftUI

@main
struct VibeClaudingApp: App {
    @State private var store = AgentStore()
    @State private var audio = AudioEngine()

    var body: some Scene {
        Window("Vibe Clauding", id: "stage") {
            ContentView()
                .environment(store)
                .environment(audio)
                .preferredColorScheme(.dark)
                .frame(minWidth: 820, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1240, height: 780)

        MenuBarExtra {
            MenuBarContent()
                .environment(store)
                .environment(audio)
        } label: {
            MenuBarLabel(store: store)
        }
    }
}

struct ContentView: View {
    @Environment(AudioEngine.self) private var audio
    @AppStorage("floatOnTop") private var floatOnTop = false
    @State private var visibility = WindowVisibility()

    var body: some View {
        ZStack {
            Color.black
            WaveBackground(analyzer: audio.analyzer, paused: !visibility.isVisible)
            StageView(analyzer: audio.analyzer)
            VStack {
                HUDView(floatOnTop: $floatOnTop)
                Spacer()
                SilenceHint().padding(.bottom, 14)
            }
        }
        .ignoresSafeArea()
        .environment(visibility)
        .background(WindowConfigurator(floatOnTop: floatOnTop, visibility: visibility))
    }
}

/// Tracks whether the stage window is actually on screen, so all animation
/// stops (≈0% CPU) while it's minimized, covered or on another Space.
@Observable
final class WindowVisibility {
    var isVisible = true
}

/// Reaches the hosting NSWindow for things SwiftUI scenes don't expose directly.
struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool
    let visibility: WindowVisibility

    func makeCoordinator() -> Coordinator { Coordinator(visibility: visibility) }

    func makeNSView(context: Context) -> NSView {
        let probe = WindowProbe()
        let coordinator = context.coordinator
        probe.onWindow = { [weak coordinator] w in coordinator?.attach(w) }
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = floatOnTop ? .floating : .normal
        if floatOnTop { window.collectionBehavior.insert(.canJoinAllSpaces) } else { window.collectionBehavior.remove(.canJoinAllSpaces) }
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }

    final class Coordinator {
        let visibility: WindowVisibility
        private weak var window: NSWindow?
        private var token: NSObjectProtocol?

        init(visibility: WindowVisibility) { self.visibility = visibility }

        func attach(_ w: NSWindow?) {
            guard let w, w !== window else { return }
            window = w
            if let token { NotificationCenter.default.removeObserver(token) }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main
            ) { [weak self] _ in self?.refresh() }
            refresh()
        }

        private func refresh() {
            let visible = window?.occlusionState.contains(.visible) ?? true
            if visibility.isVisible != visible { visibility.isVisible = visible }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }

    final class WindowProbe: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.backgroundColor = .black
            onWindow?(window)
        }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    let store: AgentStore
    var body: some View {
        let needs = store.needsYouCount
        if needs > 0 {
            Label("\(needs) need you", systemImage: "exclamationmark.bubble.fill")
        } else {
            Label("\(store.workingCount)", systemImage: "waveform")
        }
    }
}

struct MenuBarContent: View {
    @Environment(AgentStore.self) private var store
    @Environment(AudioEngine.self) private var audio
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.agents.isEmpty {
            Text("No Claude Code agents running")
        } else {
            ForEach(store.agents.sorted { $0.status.sortRank < $1.status.sortRank }) { agent in
                Button {
                    store.open(agent)
                } label: {
                    Text(line(agent))
                }
            }
        }
        Divider()
        Button("Show Dance Floor") {
            openWindow(id: "stage")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("0")
        Picker("Listen to", selection: Binding(get: { audio.source }, set: { audio.setSource($0) })) {
            ForEach(AudioSource.allCases) { Text($0.label).tag($0) }
        }
        Divider()
        Button("Quit Vibe Clauding") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func line(_ a: Agent) -> String {
        let marker: String = switch a.status {
        case .needsYou: "◆"
        case .working: "●"
        case .idle: "○"
        }
        var s = "\(marker)  \(a.project) — \(a.status.label)"
        if a.status != .idle, let act = a.activity { s += " · \(act)" }
        return s
    }
}
