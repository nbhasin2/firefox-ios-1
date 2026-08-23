// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/
import Common
import ModifiedCopy
import UIKit

@Copyable
struct WallpaperState: Equatable {
    let wallpaperConfiguration: WallpaperConfiguration

    /// `availableContentHeight` represents the height available for the homepage content to occupy when the address is not
    /// being edited. This is used to keep the homepage layout constant, such that it doesn't shift when the homepage's
    /// view size changes eg when the address bar is tapped and the keyboard is presented. This value is kept in state
    /// because it is determined by BVC
    let availableContentHeight: CGFloat

    /// `availableWallpaperHeight` is the height to apply to the homepage wallpaper background so it can remain pinned to
    /// the top of the window while still extending to the same visual bottom as the homepage content.
    let availableWallpaperHeight: CGFloat

    init(wallpaperConfiguration: WallpaperConfiguration = WallpaperConfiguration()) {
        self.init(
            wallpaperConfiguration: wallpaperConfiguration,
            availableContentHeight: 0,
            availableWallpaperHeight: 0
        )
    }

    private init(
        wallpaperConfiguration: WallpaperConfiguration,
        availableContentHeight: CGFloat,
        availableWallpaperHeight: CGFloat
    ) {
        self.wallpaperConfiguration = wallpaperConfiguration
        self.availableContentHeight = availableContentHeight
        self.availableWallpaperHeight = availableWallpaperHeight
    }
}

struct WallpaperConfiguration: Equatable {
    var id: String?
    var landscapeImage: UIImage?
    var portraitImage: UIImage?
    var textColor: UIColor?
    var cardColor: UIColor?
    var logoTextColor: UIColor?
    var hasImage: Bool

    init(
        id: String? = nil,
        landscapeImage: UIImage? = nil,
        portraitImage: UIImage? = nil,
        textColor: UIColor? = nil,
        cardColor: UIColor? = nil,
        logoTextColor: UIColor? = nil,
        hasImage: Bool = false
    ) {
        self.id = id
        self.landscapeImage = landscapeImage
        self.portraitImage = portraitImage
        self.textColor = textColor
        self.cardColor = cardColor
        self.logoTextColor = logoTextColor
        self.hasImage = hasImage
    }

    init(wallpaper: Wallpaper) {
        self.init(
            id: wallpaper.id,
            landscapeImage: wallpaper.landscape,
            portraitImage: wallpaper.portrait,
            textColor: wallpaper.textColor,
            cardColor: wallpaper.cardColor,
            logoTextColor: wallpaper.logoTextColor,
            hasImage: wallpaper.hasImage
        )
    }
 }
