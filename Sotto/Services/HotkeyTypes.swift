import AppKit
import Foundation

private let _modifierKeyCodes: Set<UInt16> = [
    0x37, 0x36, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E,
]

struct UnifiedHotkey: Equatable, Hashable, Sendable, Codable {
    let keyCode: UInt16
    let modifierFlags: UInt
    let isFn: Bool
    let isDoubleTap: Bool
    let modifierKeyCodes: Set<UInt16>
    let mouseButton: UInt16?

    static let modifierComboKeyCode: UInt16 = 0xFFFF

    enum Kind: Sendable, Equatable {
        case fn
        case modifierOnly
        case modifierCombo
        case keyWithModifiers
        case bareKey
        case mouseButton
    }

    var kind: Kind {
        if mouseButton != nil { return .mouseButton }
        if isFn { return .fn }
        if modifierFlags == 0 && _modifierKeyCodes.contains(keyCode) { return .modifierOnly }
        if keyCode == Self.modifierComboKeyCode && modifierFlags != 0 { return .modifierCombo }
        if modifierFlags != 0 { return .keyWithModifiers }
        return .bareKey
    }

    init(
        keyCode: UInt16,
        modifierFlags: UInt,
        isFn: Bool,
        isDoubleTap: Bool = false,
        modifierKeyCodes: Set<UInt16> = []
    ) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.isFn = isFn
        self.isDoubleTap = isDoubleTap
        self.modifierKeyCodes = modifierKeyCodes
        self.mouseButton = nil
    }

    init(mouseButton: UInt16, isDoubleTap: Bool = false) {
        self.keyCode = 0
        self.modifierFlags = 0
        self.isFn = false
        self.isDoubleTap = isDoubleTap
        self.modifierKeyCodes = []
        self.mouseButton = mouseButton
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifierFlags = try container.decode(UInt.self, forKey: .modifierFlags)
        isFn = try container.decode(Bool.self, forKey: .isFn)
        isDoubleTap = try container.decodeIfPresent(Bool.self, forKey: .isDoubleTap) ?? false
        modifierKeyCodes = try container.decodeIfPresent(Set<UInt16>.self, forKey: .modifierKeyCodes) ?? []
        mouseButton = try container.decodeIfPresent(UInt16.self, forKey: .mouseButton)
    }

    func conflicts(with other: UnifiedHotkey) -> Bool {
        if self == other { return true }
        guard keyCode == other.keyCode,
              modifierFlags == other.modifierFlags,
              isFn == other.isFn,
              mouseButton == other.mouseButton else {
            return false
        }

        if kind == .modifierCombo, other.kind == .modifierCombo {
            return modifierKeyCodes.isEmpty
                || other.modifierKeyCodes.isEmpty
                || modifierKeyCodes == other.modifierKeyCodes
        }

        return isDoubleTap != other.isDoubleTap
    }
}

enum HotkeySlotType: String, CaseIterable, Sendable {
    case hybrid
    case pushToTalk
    case toggle
    case promptPalette
    case recentTranscriptions
    case copyLastTranscription
    case recorderToggle

    var defaultsKey: String {
        switch self {
        case .hybrid: return UserDefaultsKeys.hybridHotkey
        case .pushToTalk: return UserDefaultsKeys.pttHotkey
        case .toggle: return UserDefaultsKeys.toggleHotkey
        case .promptPalette: return UserDefaultsKeys.promptPaletteHotkey
        case .recentTranscriptions: return UserDefaultsKeys.recentTranscriptionsHotkey
        case .copyLastTranscription: return UserDefaultsKeys.copyLastTranscriptionHotkey
        case .recorderToggle: return UserDefaultsKeys.recorderToggleHotkey
        }
    }
}
