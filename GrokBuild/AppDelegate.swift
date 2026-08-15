import AppKit
import SwiftUI
import Darwin   // POSIX: open, O_EXCL, close, write, kill, getpid

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private weak var updateCheckItem: NSMenuItem?
    private weak var sidebarToggleItem: NSMenuItem?
    /// Guards against concurrent update checks: the menu item's disable alone
    /// is not enough because menu tracking re-fires the action.
    private var isCheckingForUpdates = false
    private var lockFd: Int32 = -1   // fd that holds the flock for the lifetime of the process

    func applicationDidFinishLaunching(_ notification: Notification) {
        GrokBuildPerformance.mark(.appLaunch)
        let launchInterval = GrokBuildPerformance.begin(.appLaunchToWindow)
        defer { launchInterval.end() }
        // Enforce single instance with flock (advisory lock held by open fd).
        // This is race-free even for rapid `make run ; make run`.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let pidFile = support.appendingPathComponent("instance.pid")

        let fd = open(pidFile.path, O_WRONLY | O_CREAT, 0o644)
        if fd == -1 {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.grokbuild.showMainWindow"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // Another instance already holds the lock
            close(fd)
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.grokbuild.showMainWindow"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        // We hold the lock as long as this process (and this fd) lives
        self.lockFd = fd

        // Write PID for convenience
        lseek(fd, 0, SEEK_SET)
        let pidStr = "\(getpid())\n"
        _ = pidStr.withCString { write(fd, $0, pidStr.utf8.count) }

        // Normal windowed app: Dock + standard application menus, without a
        // redundant status item in the system menu bar.
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        if let appIcon = AppIconProvider.image() {
            NSApp.applicationIconImage = appIcon
        }

        LegacySettingsMigration.run()
        GrokBuildAppearance.apply(GrokBuildAppearance.load())
        do {
            try GrokConfigLegacyMigration.run()
        } catch {
            NSLog("GrokBuild could not sanitize the Grok CLI configuration: %@", error.localizedDescription)
        }
        UpdateScheduler.start()
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalShowMainWindow),
            name: NSNotification.Name("com.grokbuild.showMainWindow"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuStateChanged),
            name: .grokBuildUpdateAvailable,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuStateChanged),
            name: .grokBuildUpdateStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionTeardownCompleted),
            name: .grokBuildShutdownComplete,
            object: nil
        )

        // Open a main window on launch
        openMainWindow()
        GrokBuildPerformance.mark(.firstWindow)
    }

    private var sessionTeardownComplete = false
    private var terminationReplyPending = false

    @objc private func sessionTeardownCompleted() {
        sessionTeardownComplete = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Give live grok sessions a bounded window to close cleanly. The previous
        // fire-and-forget shutdown raced process exit, so SIGTERM frequently lost and
        // children were left to die on stdin EOF instead.
        // A quit that arrives while one is already in flight must keep waiting on the
        // same reply — the old `.terminateNow` here silently skipped the teardown gate
        // for every quit after the first. The deadline matches Gate G's five-second
        // graceful window.
        guard !terminationReplyPending else { return .terminateLater }
        terminationReplyPending = true
        sessionTeardownComplete = false
        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)
        Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !sessionTeardownComplete, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            terminationReplyPending = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        // Closing the fd releases the flock.
        // We also clean the PID file only if we are the owner.
        if lockFd != -1 {
            close(lockFd)
            lockFd = -1
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild")
        let pidFile = support.appendingPathComponent("instance.pid")

        if let content = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let filePid = Int32(content),
           filePid == getpid() {
            try? FileManager.default.removeItem(at: pidFile)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    private static let mainWindowDefaultSize = NSSize(
        width: MainWindowLayout.defaultSize.width,
        height: MainWindowLayout.defaultSize.height
    )
    private static let mainWindowMinimumSize = NSSize(
        width: MainWindowLayout.minimumSize.width,
        height: MainWindowLayout.minimumSize.height
    )

    private func openMainWindow() {
        // If a window is already open, just bring it forward
        if let existing = NSApp.windows.first(where: { $0.contentViewController is NSHostingController<ContentView> }) {
            presentMainWindow(existing)
            return
        }

        let contentView = ContentView()
        let hosting = NSHostingController(rootView: contentView)
        hosting.safeAreaRegions = []

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.mainWindowDefaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "GrokBuild"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = GrokBuildAppearance.load().nsAppearance
        window.backgroundColor = AppTheme.Palette.canvasNSColor
        window.delegate = self
        window.contentViewController = hosting
        // Restore the user's saved frame when one exists; fill the screen only
        // on first launch. Restore must run before setFrameAutosaveName so the
        // decision is explicit rather than relying on AppKit's implicit restore.
        let restoredSavedFrame = window.setFrameUsingName("MainWindow")
        window.setFrameAutosaveName("MainWindow")
        presentMainWindow(window, fillAvailableScreen: !restoredSavedFrame)
    }

    private func presentMainWindow(_ window: NSWindow, fillAvailableScreen: Bool = false) {
        window.minSize = Self.mainWindowMinimumSize
        normalizeMainWindowFrame(window, fillAvailableScreen: fillAvailableScreen)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func normalizeMainWindowFrame(_ window: NSWindow, fillAvailableScreen: Bool = false) {
        let minSize = Self.mainWindowMinimumSize
        var frame = window.frame

        if fillAvailableScreen, let screen = window.screen ?? NSScreen.main {
            let screenFrame = MainWindowLayout.screenFillingFrame(visibleFrame: screen.visibleFrame)
            window.setFrame(screenFrame, display: false)
            window.saveFrame(usingName: window.frameAutosaveName)
            return
        }

        if frame.width < minSize.width || frame.height < minSize.height {
            frame.size = Self.mainWindowDefaultSize
            window.setFrame(frame, display: false)
            window.center()
            window.saveFrame(usingName: window.frameAutosaveName)
            return
        }

        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let intersection = frame.intersection(visible)
            if intersection.width < minSize.width || intersection.height < minSize.height {
                window.center()
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        // Manual enablement so the update item can stay disabled while a check
        // runs; every other item in this menu is always valid.
        appMenu.autoenablesItems = false
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let about = NSMenuItem(title: "About GrokBuild", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        let updates = NSMenuItem(title: AppMenuCopy.updateMenuTitle(hasActionableUpdate: false), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updateCheckItem = updates
        appMenu.addItem(updates)
#if DEBUG
        appMenu.addItem(makeSimulateUpdatesMenuItem())
#endif
        appMenu.addItem(.separator())
        let viewUsage = NSMenuItem(title: AppMenuCopy.viewUsageTitle, action: #selector(openUsagePage), keyEquivalent: "")
        viewUsage.target = self
        appMenu.addItem(viewUsage)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide GrokBuild", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit GrokBuild", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let viewMenu = NSMenu(title: "View")
        viewMenu.delegate = self
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        let toggleSidebar = NSMenuItem(
            title: AppMenuCopy.sidebarMenuTitle(isVisible: SidebarVisibility.currentPreference()),
            action: #selector(toggleSidebarFromMenu),
            keyEquivalent: "s"
        )
        toggleSidebar.keyEquivalentModifierMask = [.command, .control]
        toggleSidebar.target = self
        viewMenu.addItem(toggleSidebar)
        sidebarToggleItem = toggleSidebar

        let projectMenu = NSMenu(title: "Project")
        let projectItem = NSMenuItem()
        projectItem.submenu = projectMenu
        mainMenu.addItem(projectItem)
        let addProject = NSMenuItem(title: "Add Project…", action: #selector(chooseWorkspace), keyEquivalent: "o")
        addProject.keyEquivalentModifierMask = [.command, .shift]
        addProject.target = self
        projectMenu.addItem(addProject)

        let sessionMenu = NSMenu(title: "Session")
        let sessionItem = NSMenuItem()
        sessionItem.submenu = sessionMenu
        mainMenu.addItem(sessionItem)
        let newSession = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSession.target = self
        sessionMenu.addItem(newSession)
        let browseSessions = NSMenuItem(title: "Browse Sessions…", action: #selector(browseSessions), keyEquivalent: "r")
        browseSessions.keyEquivalentModifierMask = [.command, .shift]
        browseSessions.target = self
        sessionMenu.addItem(browseSessions)
        let stopGeneration = NSMenuItem(title: "Stop Generation", action: #selector(stopGeneration), keyEquivalent: ".")
        stopGeneration.target = self
        sessionMenu.addItem(stopGeneration)
        let focusInput = NSMenuItem(title: "Focus Input", action: #selector(focusInput), keyEquivalent: "l")
        focusInput.target = self
        sessionMenu.addItem(focusInput)

        let windowMenu = NSMenu(title: "Window")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleExternalShowMainWindow(_ notification: Notification) {
        openMainWindow()
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func openSettings() {
        openMainWindow()
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    @objc private func chooseWorkspace() {
        openMainWindow()
        NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
    }

    @objc private func newSession() {
        openMainWindow()
        NotificationCenter.default.post(name: .newSessionRequested, object: nil)
    }

    @objc private func browseSessions() {
        openMainWindow()
        NotificationCenter.default.post(name: .sessionsRequested, object: nil)
    }

    @objc private func stopGeneration() {
        NotificationCenter.default.post(name: .stopGenerationRequested, object: nil)
    }

    @objc private func focusInput() {
        openMainWindow()
        NotificationCenter.default.post(name: .focusInputRequested, object: nil)
    }

    @objc private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        updateCheckItem?.isEnabled = false
        updateCheckItem?.title = "Checking for Updates…"

        Task { @MainActor [weak self] in
            await UpdateScheduler.checkNow()
            await UpdateUI.presentUpdatePanel(refresh: false) { [weak self] in
                self?.refreshUpdateMenuItem()
            }
            self?.isCheckingForUpdates = false
            self?.refreshUpdateMenuItem()
        }
    }

    @objc private func updateMenuStateChanged() {
        Task { @MainActor [weak self] in
            self?.refreshUpdateMenuItem()
        }
    }

    @MainActor
    private func refreshUpdateMenuItem() {
        // Keep the "Checking…" state intact while a check is in flight, even
        // when background update notifications arrive mid-check.
        guard !isCheckingForUpdates else {
            updateCheckItem?.isEnabled = false
            return
        }
        updateCheckItem?.title = AppMenuCopy.updateMenuTitle(
            hasActionableUpdate: UpdateScheduler.hasAnyActionableUpdate
        )
        updateCheckItem?.isEnabled = true
    }

    @objc private func openUsagePage() {
        if let url = URL(string: "https://grok.com/?_s=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleSidebarFromMenu() {
        openMainWindow()
        NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let item = sidebarToggleItem, item.menu === menu else { return }
        item.title = AppMenuCopy.sidebarMenuTitle(isVisible: SidebarVisibility.currentPreference())
    }

#if DEBUG
    private func makeSimulateUpdatesMenuItem() -> NSMenuItem {
        let submenu = NSMenu()

        for (title, action) in [
            ("App Update Available", #selector(simulateAppUpdate)),
            ("grok CLI Update Available", #selector(simulateCLIUpdate)),
            ("Both Updates Available", #selector(simulateBothUpdates)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: "Clear Simulation",
            action: #selector(clearSimulatedUpdates),
            keyEquivalent: ""
        )
        clearItem.target = self
        submenu.addItem(clearItem)

        let item = NSMenuItem(title: "Simulate Updates", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func simulateAppUpdate() {
        Task { @MainActor [weak self] in
            UpdateDebugSimulator.apply(.app)
            self?.refreshUpdateMenuItem()
        }
    }

    @objc private func simulateCLIUpdate() {
        Task { @MainActor [weak self] in
            UpdateDebugSimulator.apply(.cli)
            self?.refreshUpdateMenuItem()
        }
    }

    @objc private func simulateBothUpdates() {
        Task { @MainActor [weak self] in
            UpdateDebugSimulator.apply(.both)
            self?.refreshUpdateMenuItem()
        }
    }

    @objc private func clearSimulatedUpdates() {
        Task { @MainActor [weak self] in
            await UpdateDebugSimulator.clear()
            self?.refreshUpdateMenuItem()
        }
    }
#endif

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of miniaturize so frame autosave does not persist a dock-icon-sized frame.
        sender.orderOut(nil)
        return false
    }
}

enum AppMenuCopy {
    static let viewUsageTitle = "View Usage on grok.com…"

    static func updateMenuTitle(hasActionableUpdate: Bool) -> String {
        hasActionableUpdate ? "Updates Available…" : "Check for Updates…"
    }

    static func sidebarMenuTitle(isVisible: Bool) -> String {
        isVisible ? "Hide Sidebar" : "Show Sidebar"
    }
}
