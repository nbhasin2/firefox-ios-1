// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

@testable import Client

@MainActor
final class MockNativeErrorPageErrorStore: NativeErrorPageErrorStoring {
    private(set) var recordedErrors: [(error: NSError, windowUUID: WindowUUID)] = []
    var helperToReturn: NativeErrorPageHelper?

    func record(error: NSError, for windowUUID: WindowUUID) {
        recordedErrors.append((error, windowUUID))
    }

    func helper(for windowUUID: WindowUUID) -> NativeErrorPageHelper? {
        return helperToReturn
    }
}
