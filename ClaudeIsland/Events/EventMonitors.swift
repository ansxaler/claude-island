//
//  EventMonitors.swift
//  ClaudeIsland
//
//  Singleton that aggregates all event monitors
//

import AppKit
import Carbon
import Combine

/// Stored reference to EventMonitors for the Carbon hotkey callback
private var _sharedEventMonitors: EventMonitors?

class EventMonitors {
    static let shared = EventMonitors()

    let mouseLocation = CurrentValueSubject<CGPoint, Never>(.zero)
    let mouseDown = PassthroughSubject<NSEvent, Never>()
    let globalHotkey = PassthroughSubject<Void, Never>()

    private var mouseMoveMonitor: EventMonitor?
    private var mouseDownMonitor: EventMonitor?
    private var mouseDraggedMonitor: EventMonitor?
    private var hotkeyRef: EventHotKeyRef?
    private var localHotkeyMonitor: Any?

    private init() {
        _sharedEventMonitors = self
        setupMonitors()
        setupGlobalHotkey()
    }

    private func setupMonitors() {
        mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            self?.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseMoveMonitor?.start()

        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] event in
            self?.mouseDown.send(event)
        }
        mouseDownMonitor?.start()

        mouseDraggedMonitor = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
            self?.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseDraggedMonitor?.start()
    }

    /// Cmd+Return hotkey to toggle the notch (Carbon global + NSEvent local)
    private func setupGlobalHotkey() {
        // Global: Carbon RegisterEventHotKey — works without accessibility permissions
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            _sharedEventMonitors?.globalHotkey.send()
            return noErr
        }, 1, &eventType, nil, nil)

        // Cmd+Return: keyCode 36 = Return, cmdKey modifier
        let hotkeyID = EventHotKeyID(signature: OSType(0x434C4944), id: 1)  // "CLID"
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey), hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        self.hotkeyRef = hotKeyRef

        // Local: works when notch is focused
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 36 {
                self?.globalHotkey.send()
                return nil
            }
            return event
        }
    }

    deinit {
        mouseMoveMonitor?.stop()
        mouseDownMonitor?.stop()
        mouseDraggedMonitor?.stop()
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
