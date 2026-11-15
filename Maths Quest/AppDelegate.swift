import UIKit
import FirebaseCore
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #if DEBUG
        // Must happen before anything uses Firestore, so before any screen is built.
        if let settings = UITestFirestore.settings(forLaunchArguments: ProcessInfo.processInfo.arguments) {
            Firestore.firestore().settings = settings
        }
        #endif
        return true
    }
}

#if DEBUG
/// The UI tests launch the app with `launchArgument`. Firestore then talks only to the local
/// emulator set up in firebase/firebase.json, and keeps its cache in memory, so a UI test can't
/// write feedback to the live project, either straight away or from a write queued on disk for a
/// later launch. Release builds don't contain this.
enum UITestFirestore {
    static let launchArgument = "-MathsQuestUITesting"
    static let emulatorHost = "127.0.0.1:8080"
    /// Followed by a port number, this points a UI-test launch at an emulator a test started itself on that port,
    /// so the test can count what Feedback sends. The host is always this Mac, and without `launchArgument` it is
    /// ignored. A missing or unusable port falls back to `emulatorHost`.
    static let portArgument = "-MathsQuestFirestorePort"

    static func host(forLaunchArguments arguments: [String]) -> String {
        guard let index = arguments.firstIndex(of: portArgument), arguments.indices.contains(index + 1),
              let port = Int(arguments[index + 1]), (1024...65535).contains(port) else { return emulatorHost }
        return "127.0.0.1:\(port)"
    }

    static func settings(forLaunchArguments arguments: [String]) -> FirestoreSettings? {
        guard arguments.contains(launchArgument) else { return nil }
        let settings = FirestoreSettings()
        settings.host = host(forLaunchArguments: arguments)
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        return settings
    }
}
#endif
