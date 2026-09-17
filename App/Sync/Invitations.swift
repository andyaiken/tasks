import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Passes invitations from the system to sync, holding any that arrive before the app has set up (§7).
final class Invitations {
    static let shared = Invitations()

    private var handler: ((CKShare.Metadata) -> Void)?
    private var waiting: [CKShare.Metadata] = []

    func deliver(_ metadata: CKShare.Metadata) {
        if let handler {
            handler(metadata)
        } else {
            waiting.append(metadata)
        }
    }

    func handle(with handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler
        waiting.forEach(handler)
        waiting = []
    }
}

#if os(iOS)
/// On iPhone, invitations arrive through the window scene, so the app names its own scene delegate.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = InvitationSceneDelegate.self
        return configuration
    }
}

final class InvitationSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// An invitation that launched the app.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Invitations.shared.deliver(metadata)
        }
    }

    /// An invitation opened while the app was running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Invitations.shared.deliver(cloudKitShareMetadata)
    }
}
#endif
