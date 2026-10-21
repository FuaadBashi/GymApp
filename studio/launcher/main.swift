// GymApp Studio launcher: a native window around the local studio server.
// Starts the server if it isn't running, shows it in a WKWebView, and stops it on quit.
import AppKit
import WebKit

let port = 8765
let url = URL(string: "http://127.0.0.1:\(port)/")!

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var server: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let studio = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        // The bundle sits next to its source: <studio>/build/GymApp Studio.app, or the path is baked in.
        let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "StudioRoot") as? String ?? studio.path)
        if !isServing() {
            let p = Process()
            p.executableURL = root.appendingPathComponent(".venv/bin/python")
            p.arguments = ["-m", "gymstudio", "--no-browser", "--port", "\(port)"]
            p.currentDirectoryURL = root
            try? p.run()
            server = p
        }
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Bashi Gym Studio"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("GymAppStudio")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        waitThenLoad(web, tries: 60)
    }

    func isServing() -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url.appendingPathComponent("api/status")) { _, r, _ in
            ok = (r as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1)
        return ok
    }

    func waitThenLoad(_ web: WKWebView, tries: Int) {
        if isServing() || tries == 0 { web.load(URLRequest(url: url)); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.waitThenLoad(web, tries: tries - 1) }
    }

    // Links outside the studio open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, u.host != "127.0.0.1", action.navigationType == .linkActivated {
            NSWorkspace.shared.open(u); decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { server?.terminate() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
let sub = NSMenu(); sub.addItem(withTitle: "Quit Bashi Gym Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = sub
let edit = NSMenuItem(); menu.addItem(edit)
let editMenu = NSMenu(title: "Edit")
for (t, s, k) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"), ("Undo", "undo:", "z")] {
    editMenu.addItem(withTitle: t, action: Selector(s), keyEquivalent: k)
}
edit.submenu = editMenu
app.mainMenu = menu
app.run()
