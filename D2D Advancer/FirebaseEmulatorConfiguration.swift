import Foundation
import FirebaseAuth
import FirebaseFirestore

enum FirebaseEmulatorConfiguration {
    private static var didApply = false

    static var isEnabled: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["D2D_USE_FIREBASE_EMULATORS"] == "1"
            || arguments.contains("-useFirebaseEmulators")
        #else
        return false
        #endif
    }

    static func applyIfNeeded(auth: Auth = Auth.auth(), firestore: Firestore = Firestore.firestore()) {
        #if DEBUG
        guard isEnabled, !didApply else { return }
        didApply = true

        auth.useEmulator(withHost: "127.0.0.1", port: 9099)

        let settings = firestore.settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        print("🧪 Firebase emulators enabled for Auth and Firestore")
        #endif
    }
}
