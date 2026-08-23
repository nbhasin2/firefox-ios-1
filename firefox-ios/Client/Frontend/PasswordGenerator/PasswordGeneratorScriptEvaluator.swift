// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

/// Identifies the frame a generated password is destined for, and how to reach it.
struct PasswordGeneratorFrameContext: Equatable {
    let origin: String?
    let host: String
    let scriptEvaluator: PasswordGeneratorScriptEvaluator
    let frameInfo: WKFrameInfo?

    static func == (lhs: PasswordGeneratorFrameContext, rhs: PasswordGeneratorFrameContext) -> Bool {
        lhs.origin == rhs.origin &&
        lhs.host == rhs.host &&
        lhs.frameInfo === rhs.frameInfo
    }
}

protocol PasswordGeneratorScriptEvaluator: Sendable {
    @MainActor
    func evaluateJavascriptInDefaultContentWorld(_ javascript: String,
                                                 _ frame: WKFrameInfo?,
                                                 _ completion: @MainActor @escaping (Any?, Error?) -> Void)
}

@MainActor
final class WebKitPasswordGeneratorScriptEvaluator: PasswordGeneratorScriptEvaluator {
    private weak var webView: WKWebView?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func evaluateJavascriptInDefaultContentWorld(_ javascript: String,
                                                 _ frame: WKFrameInfo?,
                                                 _ completion: @MainActor @escaping (Any?, Error?) -> Void) {
        webView?.evaluateJavascriptInDefaultContentWorld(javascript, frame, completion)
    }
}

extension PasswordGeneratorScriptEvaluator {
    /// `async` bridge over the completion-handler API, so the view model can await a generated
    /// password instead of re-entering through a dispatched action.
    ///
    /// Narrowed to `String?` rather than the callback's `Any?`, which is not `Sendable` and so
    /// cannot cross the continuation. Every caller here wants a string anyway.
    @MainActor
    func evaluateStringInDefaultContentWorld(
        _ javascript: String,
        in frame: WKFrameInfo?
    ) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            evaluateJavascriptInDefaultContentWorld(javascript, frame) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }
    }
}
