import AppKit
import Carbon.HIToolbox
import Foundation
import MagusCommon
import os

/// Hotkey global enregistré via Carbon RegisterEventHotKey — fonctionne même
/// si Magus n'a pas le focus. Utilisé pour le panic stop ⌘⌥.
@MainActor
public final class GlobalHotkey {

    public typealias Handler = @MainActor () -> Void

    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyId = EventHotKeyID(signature: OSType("MGUS".fourCharCode), id: 1)
    private var handler: Handler?
    private var eventHandler: EventHandlerRef?
    private let logger = MagusLogger.execution

    public init() {}

    /// Enregistre le hotkey. `keyCode` Carbon (ex: 47 = `.`).
    /// `modifiers` Carbon (cmdKey | optionKey).
    public func register(
        keyCode: Int = kVK_ANSI_Period,
        modifiers: Int = cmdKey | optionKey,
        handler: @escaping Handler
    ) {
        unregister()
        self.handler = handler

        // Installe le handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in me.handler?() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return
        }

        let regStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotkeyId,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        if regStatus == noErr {
            logger.info("Hotkey ⌘⌥. registered globally")
        } else {
            logger.error("RegisterEventHotKey failed: \(regStatus)")
        }
    }

    public func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        handler = nil
    }

    deinit {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let h = eventHandler { RemoveEventHandler(h) }
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for (i, char) in utf8.prefix(4).enumerated() {
            result |= FourCharCode(char) << (8 * (3 - i))
        }
        return result
    }
}
