// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Shared
import SDWebImage
import Storage
import UIKit

/// The TopSite cell that appears in the ASHorizontalScrollView.
class TopSiteItemCell: UICollectionViewCell, ReusableCell {

    // MARK: - Variables

    private var homeTopSite: TopSite?
    var notificationCenter: NotificationCenter = NotificationCenter.default

    struct UX {
        static let borderColor = UIColor(white: 0, alpha: 0.1)
        static let borderWidth: CGFloat = 0.5
        static let cellCornerRadius: CGFloat = 8
        static let titleOffset: CGFloat = 4
        static let iconSize = CGSize(width: 36, height: 36)
        static let iconCornerRadius: CGFloat = 4
        static let imageBackgroundSize = CGSize(width: 60, height: 60)
        static let overlayColor = UIColor(white: 0.0, alpha: 0.25)
        static let pinAlignmentSpacing: CGFloat = 2
        static let pinIconSize: CGSize = CGSize(width: 12, height: 12)
        static let shadowRadius: CGFloat = 6
        static let topSpace: CGFloat = 8
        static let textSafeSpace: CGFloat = 4
        static let bottomSpace: CGFloat = 10
    }

    private lazy var imageView: UIImageView = .build { imageView in
        imageView.layer.cornerRadius = UX.iconCornerRadius
        imageView.layer.masksToBounds = true
    }

    // Holds the title and the pin image of the top site
    private lazy var titlePinWrapper: UIStackView = .build { stackView in
        stackView.backgroundColor = .clear
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillProportionally
    }

    // Holds the titlePinWrapper and the Sponsored text for a sponsored tile
    private lazy var descriptionWrapper: UIStackView = .build { stackView in
        stackView.backgroundColor = .clear
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fillProportionally
    }

    private lazy var pinViewHolder: UIView = .build { view in
        view.isHidden = true
    }

    private lazy var pinImageView: UIImageView = .build { imageView in
        imageView.image = UIImage.templateImageNamed(ImageIdentifiers.pinSmall)
        imageView.isHidden = true
    }

    private lazy var titleLabel: UILabel = .build { titleLabel in
        titleLabel.textAlignment = .center
        titleLabel.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .caption1,
                                                                        maxSize: 26)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.preferredMaxLayoutWidth = UX.imageBackgroundSize.width + TopSiteItemCell.UX.shadowRadius
        titleLabel.numberOfLines = 1
        titleLabel.backgroundColor = UIColor.clear
        titleLabel.setContentHuggingPriority(UILayoutPriority(1000), for: .vertical)
    }

    private lazy var sponsoredLabel: UILabel = .build { sponsoredLabel in
        sponsoredLabel.textAlignment = .center
        sponsoredLabel.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .caption1,
                                                                            maxSize: 26)
        sponsoredLabel.adjustsFontForContentSizeCategory = true
        sponsoredLabel.preferredMaxLayoutWidth = UX.imageBackgroundSize.width + TopSiteItemCell.UX.shadowRadius
        sponsoredLabel.numberOfLines = 1
    }

    private lazy var faviconBG: UIView = .build { view in
        view.layer.cornerRadius = UX.cellCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = UX.borderColor.cgColor

        view.layer.shadowColor = UIColor.theme.homePanel.shortcutShadowColor
        view.layer.shadowOpacity = UIColor.theme.homePanel.shortcutShadowOpacity
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.cornerRadius = UX.cellCornerRadius
        let shadowRect = CGRect(width: UX.imageBackgroundSize.width, height: UX.imageBackgroundSize.height)
        view.layer.shadowPath = UIBezierPath(rect: shadowRect).cgPath
        view.layer.shadowRadius = UX.shadowRadius
    }

    private lazy var selectedOverlay: UIView = .build { selectedOverlay in
        selectedOverlay.isHidden = true
        selectedOverlay.layer.cornerRadius = UX.cellCornerRadius
        selectedOverlay.backgroundColor = UX.overlayColor
    }

    override var isSelected: Bool {
        didSet {
            selectedOverlay.isHidden = !isSelected
        }
    }

    override var isHighlighted: Bool {
        didSet {
            selectedOverlay.isHidden = !isHighlighted
        }
    }

    // MARK: - Inits

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = AccessibilityIdentifiers.FirefoxHomepage.TopSites.itemCell

        applyTheme()
        setupLayout()

        setupNotifications(forObserver: self, observing: [.DisplayThemeChanged])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.backgroundColor = UIColor.clear

        titleLabel.text = nil
        sponsoredLabel.text = nil
        pinViewHolder.isHidden = true
        pinImageView.isHidden = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        selectedOverlay.isHidden = true
    }

    // MARK: - Public methods

    func configure(_ topSite: TopSite, position: Int) {
        homeTopSite = topSite
        titleLabel.text = topSite.title
        accessibilityLabel = topSite.accessibilityLabel

        imageView.setFaviconOrDefaultIcon(forSite: topSite.site) {}

        configurePinnedSite(topSite)
        configureSponsoredSite(topSite)

        applyTheme()
    }

    // MARK: - Setup Helper methods

    private func setupLayout() {
        titlePinWrapper.addArrangedSubview(pinViewHolder)
        titlePinWrapper.addArrangedSubview(titleLabel)
        pinViewHolder.addSubview(pinImageView)

        descriptionWrapper.addArrangedSubview(titlePinWrapper)
        descriptionWrapper.addArrangedSubview(sponsoredLabel)
        contentView.addSubview(descriptionWrapper)

        faviconBG.addSubview(imageView)
        contentView.addSubview(faviconBG)
        contentView.addSubview(selectedOverlay)

        NSLayoutConstraint.activate([
            descriptionWrapper.topAnchor.constraint(equalTo: faviconBG.bottomAnchor, constant: UX.topSpace),
            descriptionWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.bottomSpace),
            descriptionWrapper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.textSafeSpace),
            descriptionWrapper.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.textSafeSpace),

            faviconBG.topAnchor.constraint(equalTo: contentView.topAnchor),
            faviconBG.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            faviconBG.widthAnchor.constraint(equalToConstant: UX.imageBackgroundSize.width),
            faviconBG.heightAnchor.constraint(equalToConstant: UX.imageBackgroundSize.height),

            imageView.widthAnchor.constraint(equalToConstant: UX.iconSize.width),
            imageView.heightAnchor.constraint(equalToConstant: UX.iconSize.height),
            imageView.centerXAnchor.constraint(equalTo: faviconBG.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: faviconBG.centerYAnchor),

            selectedOverlay.topAnchor.constraint(equalTo: faviconBG.topAnchor),
            selectedOverlay.leadingAnchor.constraint(equalTo: faviconBG.leadingAnchor),
            selectedOverlay.trailingAnchor.constraint(equalTo: faviconBG.trailingAnchor),
            selectedOverlay.bottomAnchor.constraint(equalTo: faviconBG.bottomAnchor),

            pinViewHolder.bottomAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: UX.pinAlignmentSpacing),

            pinViewHolder.leadingAnchor.constraint(equalTo: pinImageView.leadingAnchor),
            pinViewHolder.trailingAnchor.constraint(equalTo: pinImageView.trailingAnchor, constant: UX.titleOffset),
            pinViewHolder.topAnchor.constraint(equalTo: pinImageView.topAnchor),
            pinViewHolder.bottomAnchor.constraint(equalTo: pinImageView.bottomAnchor),

            pinImageView.widthAnchor.constraint(equalToConstant: UX.pinIconSize.width),
            pinImageView.heightAnchor.constraint(equalToConstant: UX.pinIconSize.height),
        ])
    }

    private func configurePinnedSite(_ topSite: TopSite) {
        guard topSite.isPinned else { return }
        pinViewHolder.isHidden = false
        pinImageView.isHidden = false
    }

    private func configureSponsoredSite(_ topSite: TopSite) {
        guard topSite.isSponsoredTile else { return }

        sponsoredLabel.text = topSite.sponsoredText
    }
}

// MARK: NotificationThemeable
extension TopSiteItemCell: NotificationThemeable {
    func applyTheme() {
        pinImageView.tintColor = UIColor.theme.homePanel.topSitePin
        titleLabel.textColor = UIColor.theme.homePanel.topSiteDomain
        faviconBG.backgroundColor = UIColor.theme.homePanel.shortcutBackground
        faviconBG.layer.shadowColor = UIColor.theme.homePanel.shortcutShadowColor

        let theme = BuiltinThemeName(rawValue: LegacyThemeManager.instance.current.name) ?? .normal
        sponsoredLabel.textColor = theme == .dark ? UIColor.Photon.LightGrey40 : UIColor.Photon.DarkGrey05
    }
}

// MARK: - Notifiable
extension TopSiteItemCell: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .DisplayThemeChanged:
            applyTheme()
        default: break
        }
    }
}
