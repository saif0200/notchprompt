import AppKit
import Carbon
import Foundation

enum ShortcutCommand: CaseIterable {
    case startPause
    case reset
    case jumpBack
    case togglePrivacy
    case toggleOverlay
    case speedUp
    case speedDown

    var keyEquivalent: String {
        switch self {
        case .startPause:
            return "p"
        case .reset:
            return "r"
        case .jumpBack:
            return "j"
        case .togglePrivacy:
            return "h"
        case .toggleOverlay:
            return "o"
        case .speedUp:
            return "="
        case .speedDown:
            return "-"
        }
    }

    var displayShortcut: String {
        switch self {
        case .startPause:
            return "⌥⌘P"
        case .reset:
            return "⌥⌘R"
        case .jumpBack:
            return "⌥⌘J"
        case .togglePrivacy:
            return "⌥⌘H"
        case .toggleOverlay:
            return "⌥⌘O"
        case .speedUp:
            return "⌥⌘="
        case .speedDown:
            return "⌥⌘-"
        }
    }

    fileprivate var hotKeyID: UInt32 {
        switch self {
        case .startPause:
            return 1
        case .reset:
            return 2
        case .jumpBack:
            return 3
        case .togglePrivacy:
            return 4
        case .toggleOverlay:
            return 5
        case .speedUp:
            return 6
        case .speedDown:
            return 7
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .startPause:
            return UInt32(kVK_ANSI_P)
        case .reset:
            return UInt32(kVK_ANSI_R)
        case .jumpBack:
            return UInt32(kVK_ANSI_J)
        case .togglePrivacy:
            return UInt32(kVK_ANSI_H)
        case .toggleOverlay:
            return UInt32(kVK_ANSI_O)
        case .speedUp:
            return UInt32(kVK_ANSI_Equal)
        case .speedDown:
            return UInt32(kVK_ANSI_Minus)
        }
    }

    fileprivate var carbonModifiers: UInt32 {
        UInt32(optionKey | cmdKey)
    }
}

final class GlobalHotkeyManager {
    private static let signature: OSType = 0x4E_50_48_4B // "NPHK"

    private var hotKeyRefs: [ShortcutCommand: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let onCommand: (ShortcutCommand) -> Void

    private(set) var failedRegistrations: [ShortcutCommand] = []

    init(onCommand: @escaping (ShortcutCommand) -> Void) {
        self.onCommand = onCommand
    }

    deinit {
        unregisterAll()
    }

    func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()

        var failed: [ShortcutCommand] = []
        for command in ShortcutCommand.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: command.hotKeyID)
            let status = RegisterEventHotKey(
                command.keyCode,
                command.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs[command] = hotKeyRef
            } else {
                failed.append(command)
            }
        }

        failedRegistrations = failed
    }

    func unregisterAll() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        failedRegistrations = []
    }

    #if DEBUG
    static func runSelfChecks() {
        let commands = ShortcutCommand.allCases
        assert(Set(commands.map(\.hotKeyID)).count == commands.count, "Shortcut hotkey IDs must be unique")
        assert(Set(commands.map(\.displayShortcut)).count == commands.count, "Display shortcuts must be unique")
        for command in commands {
            assert(!command.keyEquivalent.isEmpty, "Missing keyEquivalent for \(command)")
            assert(command.carbonModifiers == UInt32(optionKey | cmdKey), "Unexpected modifiers for \(command)")
        }
    }
    #endif

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyPressed(eventRef)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func handleHotKeyPressed(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        guard let command = ShortcutCommand.allCases.first(where: { $0.hotKeyID == hotKeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [onCommand] in
            onCommand(command)
        }
        return noErr
    }
}
