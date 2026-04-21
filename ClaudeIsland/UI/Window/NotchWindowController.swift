//
//  NotchWindowController.swift
//  ClaudeIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private var cancellables = Set<AnyCancellable>()
    private var previousApp: NSRunningApplication?

    init(screen: NSScreen) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow] status in
                switch status {
                case .opened:
                    // Snapshot the app the user was in so we can hand focus back on close
                    let frontmost = NSWorkspace.shared.frontmostApplication
                    if let frontmost, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
                        self?.previousApp = frontmost
                    }
                    // Accept mouse events when opened so buttons work
                    notchWindow?.ignoresMouseEvents = false
                    // Activate app and focus window so keyboard shortcuts work
                    NSApp.activate()
                    notchWindow?.makeKey()
                    notchWindow?.makeFirstResponder(notchWindow?.contentViewController?.view)
                case .closed:
                    notchWindow?.ignoresMouseEvents = true
                    // Yield key-window status so keystrokes stop routing to the panel.
                    // Cooperative activate() on macOS 14+ hands visual focus back
                    // but leaves the key window with us, forcing the user to Cmd+Tab.
                    notchWindow?.makeFirstResponder(nil)
                    notchWindow?.resignKey()
                    // Activate the previously-frontmost app via LaunchServices.
                    // openApplication(activates:true) uses the same path as a
                    // Dock-icon click — forces a full key-window handoff, unlike
                    // the cooperative NSRunningApplication.activate() which macOS
                    // can silently downgrade on Tahoe.
                    if let previousApp = self?.previousApp,
                       let bundleURL = previousApp.bundleURL {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = true
                        NSWorkspace.shared.openApplication(
                            at: bundleURL,
                            configuration: config,
                            completionHandler: nil
                        )
                    }
                    self?.previousApp = nil
                case .popping:
                    notchWindow?.ignoresMouseEvents = true
                }
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Perform boot animation after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewModel.performBootAnimation()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
