import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The system's screen for inviting people to the list and managing who's in it (§7).
/// It only offers private, read-write sharing, so there's never a public link.
enum SharingScreen {
    /// Keeps the screen's delegate alive while it's open.
    private static var delegate: AnyObject?

    #if os(iOS)
    static func present(_ share: CKShare, sync: CloudSync) {
        let controller = UICloudSharingController(share: share, container: sync.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = Delegate(sync: sync)
        controller.delegate = delegate
        Self.delegate = delegate

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let sync: CloudSync
        init(sync: CloudSync) { self.sync = sync }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Needs Doing" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            sync.notice = "Couldn't save the sharing changes: \(error.localizedDescription)"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            sync.sharingScreenClosed()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            sync.sharingScreenClosed()
        }
    }
    #else
    static func present(_ share: CKShare, sync: CloudSync) {
        guard let service = NSSharingService(named: .cloudSharing) else { return }
        let provider = NSItemProvider()
        provider.registerCKShare(share, container: sync.container, allowedSharingOptions: CloudSync.sharingOptions)
        let delegate = Delegate(sync: sync)
        service.delegate = delegate
        Self.delegate = delegate
        service.perform(withItems: [provider])
    }

    private final class Delegate: NSObject, NSCloudSharingServiceDelegate {
        let sync: CloudSync
        init(sync: CloudSync) { self.sync = sync }

        func sharingService(
            _ sharingService: NSSharingService,
            sourceWindowForShareItems items: [Any],
            sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
        ) -> NSWindow? {
            NSApp.keyWindow
        }

        func options(for cloudKitSharingService: NSSharingService, share provider: NSItemProvider) -> NSSharingService.CloudKitOptions {
            [.allowPrivate, .allowReadWrite]
        }

        func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) {
            sync.sharingScreenClosed()
        }

        func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) {
            sync.sharingScreenClosed()
        }

        func sharingService(_ sharingService: NSSharingService, didCompleteForItems items: [Any], error: (any Error)?) {
            if let error, (error as? CocoaError)?.code != .userCancelled {
                sync.notice = "Couldn't share the list: \(error.localizedDescription)"
            }
            sync.sharingScreenClosed()
        }
    }
    #endif
}
