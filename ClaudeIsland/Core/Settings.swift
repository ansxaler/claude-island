//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import AppKit
import Combine
import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let doNotDisturb = "doNotDisturb"
    }

    // MARK: - Do Not Disturb

    /// When on, the notch never auto-opens or steals keyboard focus
    static var doNotDisturb: Bool {
        get { defaults.bool(forKey: Keys.doNotDisturb) }
        set { defaults.set(newValue, forKey: Keys.doNotDisturb) }
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }
}

// MARK: - Do Not Disturb State

/// Observable Do Not Disturb state, persisted via AppSettings.
/// When on: no auto-open on permission requests, no focus stealing, no sounds.
/// The closed-notch indicators (amber dot, spinner, checkmark) still show.
@MainActor
final class DoNotDisturbState: ObservableObject {
    static let shared = DoNotDisturbState()

    @Published var isOn: Bool {
        didSet { AppSettings.doNotDisturb = isOn }
    }

    private init() {
        isOn = AppSettings.doNotDisturb
    }

    /// Toggle DND with a subtle audio cue so hotkey toggles are confirmable
    /// without anything visual stealing attention.
    func toggle() {
        isOn.toggle()
        NSSound(named: isOn ? "Tink" : "Pop")?.play()
    }
}
