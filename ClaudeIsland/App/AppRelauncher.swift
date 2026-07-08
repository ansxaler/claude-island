//
//  AppRelauncher.swift
//  ClaudeIsland
//
//  Quit/restart entry points for the menu's Quit and Restart actions
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Relaunch")

enum AppRelauncher {
    /// Quit from a UI action. terminate() called synchronously inside a
    /// button action can be swallowed while AppKit is still processing
    /// the click, so defer it a runloop tick — and since a successful
    /// terminate() never returns, force the exit if it does.
    static func quit() {
        DispatchQueue.main.async {
            logger.info("Quit requested — calling NSApp.terminate")
            NSApplication.shared.terminate(nil)
            logger.error("terminate() returned (swallowed) — forcing exit(0)")
            exit(0)
        }
    }

    /// Spawn a detached shell that waits for this process to exit, then
    /// reopens the bundle. The wait matters: `open` on a still-running
    /// app would just activate the dying instance instead of launching
    /// a fresh one. Bounded (~60s) so a failed quit can't leave a
    /// poller behind.
    static func restart() {
        let bundlePath = Bundle.main.bundlePath
        let pid = getpid()

        let script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; i=$((i+1)); [ $i -ge 600 ] && exit 1; done; /usr/bin/open \"\(bundlePath)\""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            logger.error("Failed to spawn relaunch helper: \(error.localizedDescription)")
        }

        quit()
    }
}
