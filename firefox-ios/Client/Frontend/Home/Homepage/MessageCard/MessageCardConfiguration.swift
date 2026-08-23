// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// What the homepage message card renders. Was declared in `MessageCardMiddleware`.
struct MessageCardConfiguration: Hashable {
    let title: String?
    let description: String?
    let buttonLabel: String?
}
