// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Covers the draft's own rules. The transitions that used to live in the reducer are
/// now `WebCompatReporterViewModel` intents and are covered in `WebCompatReporterViewModelTests`.
@MainActor
final class WebCompatReporterStateTests: XCTestCase {
    // MARK: - Initialization

    func test_init_returnsDefaultDraft() {
        let subject = createSubject()

        XCTAssertEqual(subject.url, "")
        XCTAssertNil(subject.selectedCategory)
        XCTAssertNil(subject.selectedSubOptionID)
        XCTAssertEqual(subject.additionalDetails, "")
        XCTAssertTrue(subject.includeScreenshot)
        XCTAssertTrue(subject.includeBlockedList)
    }

    func test_canPreview_falseUntilCategorySelected() {
        XCTAssertFalse(createSubject().canPreview)

        let withCategory = WebCompatReporterState()
            .copy(url: "https://example.com")
            .copy(selectedCategory: .siteNotUsable)
        XCTAssertTrue(withCategory.canPreview)
    }

    func test_canSubmit_needsASubOptionUnlessTheCategoryHasNone() {
        XCTAssertFalse(createSubject().canSubmit)
        XCTAssertFalse(makeState(category: .siteNotUsable).canSubmit)
        XCTAssertTrue(
            makeState(category: .siteNotUsable, subOption: .pageNotLoading).canSubmit
        )
        XCTAssertTrue(makeState(category: .other).canSubmit)
    }

    func test_canSubmit_falseWhenTheURLHasBeenClearedOrIsBlank() {
        XCTAssertFalse(makeState(category: .other, url: "").canSubmit)
        XCTAssertFalse(makeState(category: .other, url: "   ").canSubmit)
    }

    func test_isURLValid_rejectsLookalikesAndBlocksSendAndPreview() {
        for url in ["https://example.com", "example.com", "ebay.com/deals?a=1", "https://sub.example.co.uk"] {
            XCTAssertTrue(makeState(category: .other, url: url).isURLValid, "Expected \(url) to be reportable")
        }
        for url in [" .com", ".com", "example..com", "example.com.", "https://exa mple.com", "https://", "foo"] {
            XCTAssertFalse(makeState(category: .other, url: url).isURLValid, "Expected \(url) to be rejected")
        }

        let subject = makeState(category: .other, url: ".com")
        XCTAssertFalse(subject.canSubmit)
        XCTAssertFalse(subject.canPreview)
    }

    func test_showsAdditionalDetails_onlyOnceACategoryIsPicked() {
        XCTAssertFalse(createSubject().showsAdditionalDetails)
        XCTAssertTrue(makeState(category: .other).showsAdditionalDetails)
    }

    func test_showsURLError_onlyForNonEmptyUnreportableInput() {
        XCTAssertFalse(makeState(category: .other, url: "").showsURLError)
        XCTAssertFalse(makeState(category: .other, url: "https://example.com").showsURLError)
        XCTAssertTrue(makeState(category: .other, url: ".com").showsURLError)
    }

    // MARK: - Equality

    func test_equality_sameValues_returnsTrue() {
        XCTAssertEqual(makeState(category: .other), makeState(category: .other))
    }

    func test_equality_differentURL_returnsFalse() {
        XCTAssertNotEqual(
            makeState(category: .other, url: "https://example.com"),
            makeState(category: .other, url: "https://mozilla.org")
        )
    }

    // MARK: - WebCompatIssueCategory

    func test_category_idMatchesRawValue() {
        for category in WebCompatIssueCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func test_category_subOptionIDs_matchGleanReasonKeys() {
        XCTAssertEqual(
            WebCompatIssueCategory.siteNotUsable.subOptions.map(\.rawValue),
            ["browser_blocked", "page_not_loading", "missing_items", "buttons_not_working"]
        )
        XCTAssertEqual(
            WebCompatIssueCategory.designBroken.subOptions.map(\.rawValue),
            ["images_not_loaded", "items_overlapped", "items_misaligned", "items_not_visible"]
        )
        XCTAssertEqual(
            WebCompatIssueCategory.videoOrAudio.subOptions.map(\.rawValue),
            ["no_video", "no_audio", "media_controls_broken", "playback_fails", "captions_missing"]
        )
    }

    func test_category_other_hasNoSubOptions() {
        XCTAssertTrue(WebCompatIssueCategory.other.subOptions.isEmpty)
    }

    // MARK: - Private Helpers

    private func makeState(
        category: WebCompatIssueCategory,
        subOption: WebCompatSubOption? = nil,
        url: String = "https://example.com"
    ) -> WebCompatReporterState {
        return WebCompatReporterState()
            .copy(url: url)
            .copy(selectedCategory: category)
            .copy(selectedSubOptionID: subOption?.rawValue)
    }

    private func createSubject() -> WebCompatReporterState {
        return WebCompatReporterState()
    }
}
