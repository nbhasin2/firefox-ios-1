// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

@MainActor
protocol NativeErrorPageErrorStoring: AnyObject {
    func record(error: NSError, for windowUUID: WindowUUID)
    func helper(for windowUUID: WindowUUID) -> NativeErrorPageHelper?
}

/// Holds the error that triggered a native error page between the moment the web view fails and
/// the moment the error page view controller is created — a gap the browser cannot avoid, because
/// it must load the privileged error URL before the page exists.
///
/// This is the `nativeErrorPageHelper` that `NativeErrorPageMiddleware` used to hold. That was a
/// single property on one app-wide middleware, so on iPad two windows failing on different sites
/// shared one error and the second window rendered the first window's page. Keying by
/// `WindowUUID` fixes that.
@MainActor
final class NativeErrorPageErrorStore: NativeErrorPageErrorStoring {
    static let shared = NativeErrorPageErrorStore()

    private var helpersByWindow: [WindowUUID: NativeErrorPageHelper] = [:]

    func record(error: NSError, for windowUUID: WindowUUID) {
        helpersByWindow[windowUUID] = NativeErrorPageHelper(error: error)
    }

    func helper(for windowUUID: WindowUUID) -> NativeErrorPageHelper? {
        return helpersByWindow[windowUUID]
    }
}
