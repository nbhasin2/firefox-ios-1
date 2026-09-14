// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import ModifiedCopy

/// The in-progress "Report a Website Issue" report. Mutated only by
/// `WebCompatReporterViewModel`, which is what publishes it to the view.
@Copyable
struct WebCompatReporterState: Equatable {
    var url: String
    var selectedCategory: WebCompatIssueCategory?
    var selectedSubOptionID: String?
    var additionalDetails: String
    var includeScreenshot: Bool
    var includeBlockedList: Bool

    var showsAdditionalDetails: Bool { selectedCategory != nil }
    var isURLValid: Bool { WebCompatURLValidator.isReportable(url) }

    var canPreview: Bool { selectedCategory != nil && isURLValid }

    var showsURLError: Bool {
        return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isURLValid
    }

    /// Send needs a reportable address and a sub-option, except for "Other", which has none.
    var canSubmit: Bool {
        guard let selectedCategory, isURLValid else { return false }
        return selectedCategory.subOptions.isEmpty || selectedSubOptionID != nil
    }

    init(url: String = "",
         selectedCategory: WebCompatIssueCategory? = nil,
         selectedSubOptionID: String? = nil,
         additionalDetails: String = "",
         includeScreenshot: Bool = true,
         includeBlockedList: Bool = true) {
        self.url = url
        self.selectedCategory = selectedCategory
        self.selectedSubOptionID = selectedSubOptionID
        self.additionalDetails = additionalDetails
        self.includeScreenshot = includeScreenshot
        self.includeBlockedList = includeBlockedList
    }
}
