import Foundation

enum AppConstants {
    static let appSupportDirectoryName = "Sotto"

    static let keychainServicePrefix: String = {
        #if DEBUG
        return "com.sotto.dev.apikey."
        #else
        return "com.sotto.apikey."
        #endif
    }()

    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    static let loggerSubsystem: String = Bundle.main.bundleIdentifier ?? "com.sotto.app"
}
