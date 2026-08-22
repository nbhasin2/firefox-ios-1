// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import UIKit
import XCTest

@testable import Client

/// Replaces `WallpaperStateTests` and `WallpaperMiddlewareTests`.
@MainActor
final class WallpaperViewModelTests: XCTestCase {
    private var wallpaperManager: WallpaperManagerMock!
    private var notificationCenter: MockNotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        wallpaperManager = WallpaperManagerMock()
        notificationCenter = MockNotificationCenter()
    }

    override func tearDown() async throws {
        wallpaperManager = nil
        notificationCenter = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Configuration

    /// What `WallpaperMiddlewareActionType.wallpaperDidInitialize` used to do.
    func test_init_readsTheCurrentWallpaper() {
        wallpaperManager.currentWallpaper = makeWallpaper(id: "beach", textColor: .red)
        let subject = createSubject()

        XCTAssertEqual(subject.state.wallpaperConfiguration.id, "beach")
        XCTAssertEqual(subject.state.wallpaperConfiguration.textColor, .red)
    }

    /// What `WallpaperMiddlewareActionType.wallpaperDidChange` used to do. The picker posts
    /// `.WallpaperDidChange` from `WallpaperManager` itself, so no action is needed.
    func test_wallpaperDidChangeNotification_rereadsTheManager() {
        let subject = createSubject()
        wallpaperManager.currentWallpaper = makeWallpaper(id: "forest", textColor: .cyan)

        subject.refreshConfiguration()

        XCTAssertEqual(subject.state.wallpaperConfiguration.id, "forest")
    }

    func test_refreshConfiguration_withAChange_publishes() {
        let subject = createSubject()
        var changes = 0
        subject.onChange = { _, _ in changes += 1 }
        wallpaperManager.currentWallpaper = makeWallpaper(id: "forest", textColor: .cyan)

        subject.refreshConfiguration()

        XCTAssertEqual(changes, 1)
    }

    func test_refreshConfiguration_withNoChange_doesNotPublish() {
        let subject = createSubject()
        var changes = 0
        subject.onChange = { _, _ in changes += 1 }

        subject.refreshConfiguration()

        XCTAssertEqual(changes, 0)
    }

    // MARK: - Available heights

    func test_updateAvailableHeights_storesBothValues() {
        let subject = createSubject()

        subject.updateAvailableHeights(content: 100, wallpaper: 300)

        XCTAssertEqual(subject.state.availableContentHeight, 100)
        XCTAssertEqual(subject.state.availableWallpaperHeight, 300)
    }

    func test_updateAvailableHeights_publishesThePreviousValue() {
        let subject = createSubject()
        subject.updateAvailableHeights(content: 100, wallpaper: 300)
        var previousContentHeight: CGFloat?
        subject.onChange = { _, previous in previousContentHeight = previous.availableContentHeight }

        subject.updateAvailableHeights(content: 200, wallpaper: 400)

        // The view controller animates the snapshot only when this is unchanged.
        XCTAssertEqual(previousContentHeight, 100)
    }

    /// BrowserViewController used to hold this guard before dispatching.
    func test_updateAvailableHeights_withTheSameValues_doesNotPublish() {
        let subject = createSubject()
        subject.updateAvailableHeights(content: 100, wallpaper: 300)
        var changes = 0
        subject.onChange = { _, _ in changes += 1 }

        subject.updateAvailableHeights(content: 100, wallpaper: 300)

        XCTAssertEqual(changes, 0)
    }

    private func makeWallpaper(id: String, textColor: UIColor) -> Wallpaper {
        return Wallpaper(id: id, textColor: textColor, cardColor: .black, logoTextColor: .white)
    }

    private func createSubject() -> WallpaperViewModel {
        let subject = WallpaperViewModel(wallpaperManager: wallpaperManager,
                                         notificationCenter: notificationCenter)
        trackForMemoryLeaks(subject)
        return subject
    }
}
