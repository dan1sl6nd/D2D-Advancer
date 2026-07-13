import Foundation
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

enum FirebaseBootstrap {
    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        if FirebaseApp.app() != nil {
            didConfigure = true
            return
        }
        configureAppCheckIfNeeded()
        FirebaseApp.configure()
        print("🔥 Firebase configured")
        didConfigure = true
    }

    private static func configureAppCheckIfNeeded() {
        guard !FirebaseEmulatorConfiguration.isEnabled else { return }

        #if targetEnvironment(simulator)
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        print("🛡️ Firebase App Check debug provider configured for Simulator")
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        print("🛡️ Firebase App Check DeviceCheck provider configured")
        #endif
    }
}

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

    static var activeHostDescription: String {
        #if DEBUG
        return emulatorHost()
        #else
        return ""
        #endif
    }

    static func applyIfNeeded() {
        FirebaseBootstrap.configureIfNeeded()
        applyIfNeeded(auth: Auth.auth(), firestore: Firestore.firestore())
    }

    static func applyIfNeeded(
        auth: Auth,
        firestore: Firestore,
        functions: Functions = Functions.functions()
    ) {
        #if DEBUG
        guard isEnabled, !didApply else { return }
        didApply = true

        let host = emulatorHost()

        auth.useEmulator(withHost: host, port: 9099)

        let settings = firestore.settings
        settings.host = "\(host):8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        functions.useEmulator(withHost: host, port: 5001)
        print("🧪 Firebase emulators enabled for Auth, Firestore, and Functions at \(host)")
        #endif
    }

    static func applyIfNeeded(firestore: Firestore) {
        FirebaseBootstrap.configureIfNeeded()
        applyIfNeeded(auth: Auth.auth(), firestore: firestore)
    }

    #if DEBUG
    private static func emulatorHost() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let host = environment["D2D_FIREBASE_EMULATOR_HOST"], !host.isEmpty {
            return host
        }

        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-firebaseEmulatorHost"),
           arguments.indices.contains(arguments.index(after: index)) {
            let host = arguments[arguments.index(after: index)]
            if !host.isEmpty {
                return host
            }
        }

        if let host = Bundle.main.object(forInfoDictionaryKey: "D2DFirebaseEmulatorHost") as? String {
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedHost.isEmpty, !trimmedHost.contains("$(") {
                return trimmedHost
            }
        }

        return "127.0.0.1"
    }
    #endif
}
