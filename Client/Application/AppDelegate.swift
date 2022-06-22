// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Shared
import Storage
import AVFoundation
import XCGLogger
import MessageUI
import SDWebImage
import SyncTelemetry
import LocalAuthentication
import Sync
import CoreSpotlight
import UserNotifications
import Account
import BackgroundTasks

private let log = Logger.browserLogger

let LatestAppVersionProfileKey = "latestAppVersion"

class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var browserViewController: BrowserViewController!
    var rootViewController: UIViewController!
    var tabManager: TabManager!
    var receivedURLs = [URL]()
    var orientationLock = UIInterfaceOrientationMask.all
    weak var profile: Profile?
    private var shutdownWebServer: DispatchSourceTimer?
    private var telemetry: TelemetryWrapper?
    private var adjustHelper: AdjustHelper?
    private var webServerUtil: WebServerUtil?
    private var appLaunchUtil: AppLaunchUtil?

    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions
                     launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        log.info("startApplication begin")

        appLaunchUtil = AppLaunchUtil()
        appLaunchUtil?.setUpAppLaunchDependencies()

        self.window = UIWindow(frame: UIScreen.main.bounds)

        let profile = getProfile(application)
        telemetry = TelemetryWrapper(profile: profile)

        // Initialize the feature flag subsytem.
        // Among other things, it toggles on and off Nimbus, Contile, Adjust.
        // i.e. this must be run before initializing those systems.
        FeatureFlagsManager.shared.initializeDeveloperFeatures(with: profile)
        FeatureFlagUserPrefsMigrationUtility(with: profile).attemptMigration()

        // Migrate wallpaper folder
        WallpaperMigrationUtility(with: profile).attemptMigration()

        // Start intialzing the Nimbus SDK. This should be done after Glean
        // has been started.
        initializeExperiments()

        ThemeManager.shared.updateProfile(with: profile)

        // Set up a web server that serves us static content. Do this early so that it is ready when the UI is presented.
        webServerUtil = WebServerUtil(profile: profile)
        webServerUtil?.setUpWebServer()

        let imageStore = DiskImageStore(files: profile.files, namespace: "TabManagerScreenshots", quality: UIConstants.ScreenshotQuality)

        // Temporary fix for Bug 1390871 - NSInvalidArgumentException: -[WKContentView menuHelperFindInPage]: unrecognized selector
        if let clazz = NSClassFromString("WKCont" + "ent" + "View"), let swizzledMethod = class_getInstanceMethod(TabWebViewMenuHelper.self, #selector(TabWebViewMenuHelper.swizzledMenuHelperFindInPage)) {
            class_addMethod(clazz, MenuHelper.SelectorFindInPage, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        }

        self.tabManager = TabManager(profile: profile, imageStore: imageStore)

        setupRootViewController()

        NotificationCenter.default.addObserver(forName: .FSReadingListAddReadingListItem, object: nil, queue: nil) { (notification) -> Void in
            if let userInfo = notification.userInfo, let url = userInfo["URL"] as? URL {
                let title = (userInfo["Title"] as? String) ?? ""
                profile.readingList.createRecordWithURL(url.absoluteString, title: title, addedBy: UIDevice.current.name)
            }
        }

        startListeningForThemeUpdates()

        adjustHelper = AdjustHelper(profile: profile)
        SystemUtils.onFirstRun()

        RustFirefoxAccounts.startup(prefs: profile.prefs).uponQueue(.main) { _ in
            print("RustFirefoxAccounts started")
        }

        log.info("startApplication end")

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // We have only five seconds here, so let's hope this doesn't take too long.
        profile?._shutdown()

        // Allow deinitializers to close our database connections.
        profile = nil
        tabManager = nil
        browserViewController = nil
        rootViewController = nil
    }

    /**
     * We maintain a weak reference to the profile so that we can pause timed
     * syncs when we're backgrounded.
     *
     * The long-lasting ref to the profile lives in BrowserViewController,
     * which we set in application:willFinishLaunchingWithOptions:.
     *
     * If that ever disappears, we won't be able to grab the profile to stop
     * syncing... but in that case the profile's deinit will take care of things.
     */
    func getProfile(_ application: UIApplication) -> Profile {
        if let profile = self.profile {
            return profile
        }
        let p = BrowserProfile(localName: "profile", syncDelegate: application.syncDelegate)
        self.profile = p
        return p
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIScrollView.doBadSwizzleStuff()

        window!.makeKeyAndVisible()

        // Now roll logs.
        DispatchQueue.global(qos: DispatchQoS.background.qosClass).async {
            Logger.syncLogger.deleteOldLogsDownToSizeLimit()
            Logger.browserLogger.deleteOldLogsDownToSizeLimit()
        }

        pushNotificationSetup()

        if let profile = self.profile {
            let persistedCurrentVersion = InstallType.persistedCurrentVersion()
            let introScreen = profile.prefs.intForKey(PrefsKeys.IntroSeen)
            // upgrade install - Intro screen shown & persisted current version does not match
            if introScreen != nil && persistedCurrentVersion != AppInfo.appVersion {
                InstallType.set(type: .upgrade)
                InstallType.updateCurrentVersion(version: AppInfo.appVersion)
            }

            // We need to check if the app is a clean install to use for
            // preventing the What's New URL from appearing.
            if introScreen == nil {
                // fresh install - Intro screen not yet shown
                InstallType.set(type: .fresh)
                InstallType.updateCurrentVersion(version: AppInfo.appVersion)
                // Profile setup
                profile.prefs.setString(AppInfo.appVersion, forKey: LatestAppVersionProfileKey)

            } else if profile.prefs.boolForKey(PrefsKeys.KeySecondRun) == nil {
                profile.prefs.setBool(true, forKey: PrefsKeys.KeySecondRun)
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "org.mozilla.ios.sync.part1", using: DispatchQueue.global()) { task in
            guard self.profile?.hasSyncableAccount() ?? false else {
                self.shutdownProfileWhenNotActive(application)
                return
            }

            NSLog("background sync part 1") // NSLog to see in device console
            let collection = ["bookmarks", "history"]
            self.profile?.syncManager.syncNamedCollections(why: .backgrounded, names: collection).uponQueue(.main) { _ in
                task.setTaskCompleted(success: true)
                let request = BGProcessingTaskRequest(identifier: "org.mozilla.ios.sync.part2")
                request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
                request.requiresNetworkConnectivity = true
                do {
                    try BGTaskScheduler.shared.submit(request)
                } catch {
                    NSLog(error.localizedDescription)
                }
            }
        }

        // Split up the sync tasks so each can get maximal time for a bg task.
        // This task runs after the bookmarks+history sync.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "org.mozilla.ios.sync.part2", using: DispatchQueue.global()) { task in
            NSLog("background sync part 2") // NSLog to see in device console
            let collection = ["tabs", "logins", "clients"]
            self.profile?.syncManager.syncNamedCollections(why: .backgrounded, names: collection).uponQueue(.main) { _ in
                self.shutdownProfileWhenNotActive(application)
                task.setTaskCompleted(success: true)
            }
        }
        updateSessionCount()
        adjustHelper?.setupAdjust()

        return true
    }

    private func updateSessionCount() {
        var sessionCount: Int32 = 0

        // Get the session count from preferences
        if let currentSessionCount = profile?.prefs.intForKey(PrefsKeys.SessionCount) {
            sessionCount = currentSessionCount
        }
        // increase session count value
        profile?.prefs.setInt(sessionCount + 1, forKey: PrefsKeys.SessionCount)
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let routerpath = NavigationPath(url: url) else {
            return false
        }

        if let profile = profile, let _ = profile.prefs.boolForKey(PrefsKeys.AppExtensionTelemetryOpenUrl) {
            profile.prefs.removeObjectForKey(PrefsKeys.AppExtensionTelemetryOpenUrl)
            var object = TelemetryWrapper.EventObject.url
            if case .text = routerpath {
                object = .searchText
            }
            TelemetryWrapper.recordEvent(category: .appExtensionAction, method: .applicationOpenUrl, object: object)
        }

        DispatchQueue.main.async {
            NavigationPath.handle(nav: routerpath, with: self.browserViewController)
        }
        return true
    }

    // We sync in the foreground only, to avoid the possibility of runaway resource usage.
    // Eventually we'll sync in response to notifications.
    func applicationDidBecomeActive(_ application: UIApplication) {
        shutdownWebServer?.cancel()
        shutdownWebServer = nil

        if let profile = self.profile {
            profile._reopen()

            if profile.prefs.boolForKey(PendingAccountDisconnectedKey) ?? false {
                profile.removeAccount()
            }

            profile.syncManager.applicationDidBecomeActive()
            webServerUtil?.setUpWebServer()
        }

        browserViewController.firefoxHomeViewController?.reloadAll()

        /// When transitioning to scenes, each scene's BVC needs to resume its file download queue.
        browserViewController.downloadQueue.resumeAll()

        TelemetryWrapper.recordEvent(category: .action, method: .foreground, object: .app)

        // Delay these operations until after UIKit/UIApp init is complete
        // - loadQueuedTabs accesses the DB and shows up as a hot path in profiling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // We could load these here, but then we have to futz with the tab counter
            // and making NSURLRequests.
            self.browserViewController.loadQueuedTabs(receivedURLs: self.receivedURLs)
            self.receivedURLs.removeAll()
            application.applicationIconBadgeNumber = 0
        }
        // Create fx favicon cache directory
        FaviconFetcher.createWebImageCacheDirectory()
        // update top sites widget
        updateTopSitesWidget()

        // Cleanup can be a heavy operation, take it out of the startup path. Instead check after a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.profile?.cleanupHistoryIfNeeded()
            self.browserViewController.ratingPromptManager.updateData()
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        updateTopSitesWidget()
        UserDefaults.standard.setValue(Date(), forKey: "LastActiveTimestamp")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Pause file downloads.
        // TODO: iOS 13 needs to iterate all the BVCs.
        browserViewController.downloadQueue.pauseAll()

        TelemetryWrapper.recordEvent(category: .action, method: .background, object: .app)
        TabsQuantityTelemetry.trackTabsQuantity(tabManager: tabManager)

        let singleShotTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        // 2 seconds is ample for a localhost request to be completed by GCDWebServer. <500ms is expected on newer devices.
        singleShotTimer.schedule(deadline: .now() + 2.0, repeating: .never)
        singleShotTimer.setEventHandler {
            WebServer.sharedInstance.server.stop()
            self.shutdownWebServer = nil
        }
        singleShotTimer.resume()
        shutdownWebServer = singleShotTimer

        scheduleBGSync(application: application)

        tabManager.preserveTabs()
    }

    private func updateTopSitesWidget() {
        // Since we only need the topSites data in the archiver, let's write it
        // only if iOS 14 is available.
        if #available(iOS 14.0, *) {
            guard let profile = profile else { return }
            TopSitesHelper.writeWidgetKitTopSites(profile: profile)
        }
    }

    fileprivate func shutdownProfileWhenNotActive(_ application: UIApplication) {
        // Only shutdown the profile if we are not in the foreground
        guard application.applicationState != .active else {
            return
        }

        profile?._shutdown()
    }

    /// When a user presses and holds the app icon from the Home Screen, we present quick actions / shortcut items (see QuickActions).
    ///
    /// This method can handle a quick action from both app launch and when the app becomes active. However, the system calls launch methods first if the app `launches`
    /// and gives you a chance to handle the shortcut there. If it's not handled there, this method is called in the activation process with the shortcut item.
    ///
    /// Quick actions / shortcut items are handled here as long as our two launch methods return `true`. If either of them return `false`, this method
    /// won't be called to handle shortcut items.
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let handledShortCutItem = QuickActions.sharedInstance.handleShortCutItem(shortcutItem, withBrowserViewController: browserViewController)

        completionHandler(handledShortCutItem)
    }

    private func scheduleBGSync(application: UIApplication) {
        if profile?.syncManager.isSyncing ?? false {
            // If syncing, create a bg task because _shutdown() is blocking and might take a few seconds to complete
            var taskId = UIBackgroundTaskIdentifier(rawValue: 0)
            taskId = application.beginBackgroundTask(expirationHandler: {
                self.shutdownProfileWhenNotActive(application)
                application.endBackgroundTask(taskId)
            })

            DispatchQueue.main.async {
                self.shutdownProfileWhenNotActive(application)
                application.endBackgroundTask(taskId)
            }
        } else {
            // Blocking call, however without sync running it should be instantaneous
            profile?._shutdown()

            let request = BGProcessingTaskRequest(identifier: "org.mozilla.ios.sync.part1")
            request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
            request.requiresNetworkConnectivity = true
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                NSLog(error.localizedDescription)
            }
        }
    }
}

// This functionality will need to be moved to the SceneDelegate when the time comes
extension AppDelegate {

    func startListeningForThemeUpdates() {
        NotificationCenter.default.addObserver(forName: .DisplayThemeChanged, object: nil, queue: .main) { (notification) -> Void in
            if !LegacyThemeManager.instance.systemThemeIsOn {
                self.window?.overrideUserInterfaceStyle = LegacyThemeManager.instance.userInterfaceStyle
            } else {
                self.window?.overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    // Orientation lock for views that use new modal presenter
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == SiriShortcuts.activityType.openURL.rawValue {
            browserViewController.openBlankNewTab(focusLocationField: false)
            return true
        }

        // If the `NSUserActivity` has a `webpageURL`, it is either a deep link or an old history item
        // reached via a "Spotlight" search before we began indexing visited pages via CoreSpotlight.
        if let url = userActivity.webpageURL {
            let query = url.getQuery()

            // Check for fxa sign-in code and launch the login screen directly
            if query["signin"] != nil {
                // bvc.launchFxAFromDeeplinkURL(url) // Was using Adjust. Consider hooking up again when replacement system in-place.
                return true
            }

            // Per Adjust documenation, https://docs.adjust.com/en/universal-links/#running-campaigns-through-universal-links,
            // it is recommended that links contain the `deep_link` query parameter. This link will also
            // be url encoded.
            if let deepLink = query["deep_link"]?.removingPercentEncoding, let url = URL(string: deepLink) {
                browserViewController.switchToTabForURLOrOpen(url)
                return true
            }

            browserViewController.switchToTabForURLOrOpen(url)
            return true
        }

        // Otherwise, check if the `NSUserActivity` is a CoreSpotlight item and switch to its tab or
        // open a new one.
        if userActivity.activityType == CSSearchableItemActionType {
            if let userInfo = userActivity.userInfo,
                let urlString = userInfo[CSSearchableItemActivityIdentifier] as? String,
                let url = URL(string: urlString) {
                browserViewController.switchToTabForURLOrOpen(url)
                return true
            }
        }

        return false
    }

    private func setupRootViewController() {
        if !LegacyThemeManager.instance.systemThemeIsOn {
            window?.overrideUserInterfaceStyle = LegacyThemeManager.instance.userInterfaceStyle
        }

        browserViewController = BrowserViewController(profile: profile!, tabManager: tabManager)
        browserViewController.edgesForExtendedLayout = []

        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.isNavigationBarHidden = true
        navigationController.edgesForExtendedLayout = UIRectEdge(rawValue: 0)
        rootViewController = navigationController

        window!.rootViewController = rootViewController
    }
}
