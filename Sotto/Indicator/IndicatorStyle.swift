enum IndicatorStyle: String, CaseIterable, Identifiable {
    case pill
    case notch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pill: "Floating Pill"
        case .notch: "Notch"
        }
    }
}
