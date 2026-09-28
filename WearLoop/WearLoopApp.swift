import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

@main
struct WearLoopApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegateApp
    @StateObject private var dependencies = AppDependencies.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environmentObject(dependencies)
                .environmentObject(dependencies.store)
                .tint(Palette.anchor)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                // Write any pending change before the app is suspended.
                dependencies.store.flush()
                dependencies.rescheduleNotifications()
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}

struct FireBoot: Boot {
    func run(_ application: UIApplication, _ host: AppDelegate, _ next: () -> Void) {
        FirebaseApp.configure()
        next()
    }
}

struct FlyBoot: Boot {
    func run(_ application: UIApplication, _ host: AppDelegate, _ next: () -> Void) {
        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Swatch.relayKey
        sdk.appleAppID = Swatch.appCode
        sdk.delegate = host
        sdk.deepLinkDelegate = host
        sdk.isDebug = false
        next()
    }
}

struct NoticeBoot: Boot {
    func run(_ application: UIApplication, _ host: AppDelegate, _ next: () -> Void) {
        Messaging.messaging().delegate = host
        UNUserNotificationCenter.current().delegate = host
        application.registerForRemoteNotifications()
        next()
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var knot = Knot { payload in
        NotificationCenter.default.post(name: .stitch, object: nil, userInfo: ["conversionData": payload])
    }

    private let boots: [Boot] = [FireBoot(), FlyBoot(), NoticeBoot()]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let chain = boots.reversed().reduce({} as () -> Void) { acc, boot in
            { boot.run(application, self, acc) }
        }
        chain()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            harvest(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(stirred), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func stirred() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Tags.att)
            }
        }
    }

    private func harvest(_ payload: [AnyHashable: Any]) {
        var found: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            found = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            found = url
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: Tags.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .tug, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Tags.fcm)
            UserDefaults.standard.set(token, forKey: Tags.push)
            UserDefaults(suiteName: Swatch.suite)?.set(token, forKey: Tags.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        harvest(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        harvest(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        harvest(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        knot.warp(conversionInfo)
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Tags.primed) == false else { return }
        NotificationCenter.default.post(name: .hem, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        knot.weft(deepLink.clickEvent)
    }
}
