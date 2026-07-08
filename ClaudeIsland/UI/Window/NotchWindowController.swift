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
        var notchSize = screen.notchSize

        // Cap the closed notch height at the menu bar height so the black box
        // never hangs below the macOS bar (matters on displays without a
        // physical notch, where the fallback size is taller than the bar).
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if menuBarHeight > 1 {
            notchSize.height = min(notchSize.height, menuBarHeight)
        }

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
        notchWindow.lockedFrame = windowFrame

        // Safety net for move paths the setFrame overrides don't see:
        // snap back the moment anything shifts the window.
        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: notchWindow),
            NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: notchWindow)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak notchWindow] _ in
            guard let notchWindow,
                  let locked = notchWindow.lockedFrame,
                  notchWindow.frame != locked else { return }
            notchWindow.setFrame(locked, display: true)
        }
        .store(in: &cancellables)

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
                    notchWindow?.makeFirstResponder(nil)
                    notchWindow?.resignKey()
                    if let previousApp = self?.previousApp, !previousApp.isTerminated {
                        // Cooperative handoff: while we are still the active app,
                        // explicitly yield activation to the previous app. Without
                        // the yield, macOS 14+/Tahoe silently downgrades the
                        // activate() and keyboard focus stays with us.
                        if #available(macOS 14.0, *) {
                            NSApp.yieldActivation(to: previousApp)
                        }
                        let activated = previousApp.activate()
                        if !activated, let bundleURL = previousApp.bundleURL {
                            // Fallback: LaunchServices path (same as a Dock-icon
                            // click) forces a full key-window handoff.
                            let config = NSWorkspace.OpenConfiguration()
                            config.activates = true
                            NSWorkspace.shared.openApplication(
                                at: bundleURL,
                                configuration: config,
                                completionHandler: nil
                            )
                        }
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
