// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import MozillaAppServices

@testable import Client

final class MockMerinoManager: MerinoManagerProvider, @unchecked Sendable {
    var getMerinoItemsCalled = 0
    var prefetchStoriesCalled = 0
    /// Set to an empty response to exercise the no-content path.
    var responseToReturn: MerinoStoryResponse?

    func getMerinoItems(source: StorySource) async -> MerinoStoryResponse {
        getMerinoItemsCalled += 1
        if let responseToReturn { return responseToReturn }
        let stories: [MerinoStoryConfiguration] = [
            .makeItem("feed1"),
            .makeItem("feed2"),
            .makeItem("feed3"),
        ].compactMap { MerinoStoryConfiguration(story: MerinoStory(from: $0)) }

        return MerinoStoryResponse(stories: stories)
    }

    func prefetchStories() async {
        prefetchStoriesCalled += 1
    }
}
