// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Shared
import Account
import SiteImageView
import SummarizeKit

import enum MozillaAppServices.BookmarkRoots
import protocol Storage.BookmarksHandler
import struct Storage.ShareItem
import struct Storage.Site

@MainActor
final class TabManagerMiddleware: FeatureFlaggable, CanRemoveQuickActionBookmark {
    private let profile: Profile
    private let logger: Logger
    private let windowManager: WindowManager
    private let bookmarksSaver: BookmarksSaver
    private let summarizerNimbusUtils: SummarizerNimbusUtils
    private let summarizerConfigFactory: SummarizerConfigFactory
    private let tabsPanelTelemetry: TabsPanelTelemetry
    var bookmarksHandler: BookmarksHandler

    private var isTabTrayUIExperimentsEnabled: Bool {
        return featureFlagsProvider.isEnabled(.tabTrayUIExperiments)
        && UIDevice.current.userInterfaceIdiom != .pad
    }
    private var isSummarizerEnabled: Bool {
        return summarizerNimbusUtils.isSummarizeFeatureToggledOn
    }
    private var isAppleSummarizerEnabled: Bool {
        return summarizerNimbusUtils.isAppleSummarizerEnabled()
    }
    private var isHostedSummaryEnabled: Bool {
        return summarizerNimbusUtils.isHostedSummarizerEnabled()
    }

    init(profile: Profile = AppContainer.shared.resolve(),
         logger: Logger = DefaultLogger.shared,
         windowManager: WindowManager = AppContainer.shared.resolve(),
         summarizerNimbusUtility: SummarizerNimbusUtils = DefaultSummarizerNimbusUtils(),
         summarizerConfigFactory: SummarizerConfigFactory = SummarizerMiddleware(),
         bookmarksSaver: BookmarksSaver? = nil,
         gleanWrapper: GleanWrapper = DefaultGleanWrapper()
    ) {
        self.summarizerNimbusUtils = summarizerNimbusUtility
        self.summarizerConfigFactory = summarizerConfigFactory
        self.profile = profile
        self.bookmarksHandler = profile.places
        self.logger = logger
        self.windowManager = windowManager
        self.bookmarksSaver = bookmarksSaver ?? DefaultBookmarksSaver(profile: profile)
        self.tabsPanelTelemetry = TabsPanelTelemetry(gleanWrapper: gleanWrapper, logger: logger)
    }

    lazy var tabsPanelProvider: Middleware<AppState> = (legacyProvider, modernProvider)

    lazy var modernProvider: MiddlewareClosure<AppState> = { [self] state, action, windowUUID in
        // Does not test any modern actions
    }

    lazy var legacyProvider: LegacyMiddlewareClosure<AppState> = { [self] state, action in
        if let action = action as? ScreenshotAction {
            self.resolveScreenshotActions(action: action, state: state)
        } else if let action = action as? ShortcutsLibraryAction {
            self.resolveShortcutsLibraryActions(action: action, state: state)
        } else {
            self.resolveHomepageActions(with: action)
        }
    }

    private func resolveShortcutsLibraryActions(action: ShortcutsLibraryAction, state: AppState) {
        switch action.actionType {
        case ShortcutsLibraryActionType.switchTabToastButtonTapped:
            tabManager(for: action.windowUUID)?.selectTab(action.tab)
        default:
            break
        }
    }

    private func resolveScreenshotActions(action: ScreenshotAction, state: AppState) {
        // TODO: FXIOS-12101 this should be removed once we figure out screenshots
        guard windowManager.windows[action.windowUUID]?.tabManager != nil else {
            logger.log("Tab manager does not exist for this window, bailing from taking a screenshot.", level: .fatal, category: .tabs, extra: ["windowUUID": "\(action.windowUUID)"])
            return
        }

        switch action.actionType {
        case ScreenshotActionType.screenshotTaken:
            tabManager(for: action.windowUUID)?.tabDidSetScreenshot(action.tab)
        case ScreenshotActionType.screenshotRestored:
            // The screenshot was just loaded from disk, so we only need to refresh the tab tray
            break
        default:
            return
        }

        // TabsPanelViewModel observes the same action on the bus so the tray rebinds with the
        // new `tab.screenshot`.
    }

    private func tabManager(for uuid: WindowUUID) -> TabManager? {
        guard uuid != .unavailable, let tabManager = windowManager.tabManager(for: uuid)  else {
            assertionFailure()
            logger.log("Unexpected or unavailable window UUID for requested TabManager.", level: .fatal, category: .tabs)
            return nil
        }

        return tabManager
    }

    // MARK: - Tab Peek

    // MARK: - Homepage Related Actions
    private func resolveHomepageActions(with action: Action) {
        switch action.actionType {
        case JumpBackInActionType.tapOnCell:
            guard let jumpBackInAction = action as? JumpBackInAction,
                  let tab = jumpBackInAction.tab else { return }
            tabManager(for: action.windowUUID)?.selectTab(tab)
        default:
            break
        }
    }
}
