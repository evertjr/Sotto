import Foundation

enum IndicatorStyle: String, CaseIterable, Identifiable {
    // Keeps the raw value from when this style only worked on notched Macs, so saved choices carry over.
    case island = "notch"
    case pill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .island: String(localized: "Dynamic Island")
        case .pill: String(localized: "Floating Pill")
        }
    }
}
