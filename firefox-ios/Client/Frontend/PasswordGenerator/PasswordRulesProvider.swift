// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

@MainActor
protocol PasswordRulesProviding: AnyObject {
    /// The password rule for `host` as a JSON string, or nil if the site has no site-specific rule.
    func rule(for host: String) async -> String?
}

/// The JS password generator uses a default rule set, but some sites reject those passwords.
/// Site-specific rules live in the `password-rules` remote settings collection.
///
/// Replaces the middleware's `nonisolated(unsafe) static var cachedPasswordRules` (FXIOS-12590):
/// callers now await the fetch instead of racing a fire-and-forget preload `Task`, so the first
/// password generated after launch can no longer silently miss its site-specific rule.
@MainActor
final class PasswordRulesProvider: PasswordRulesProviding {
    static let shared = PasswordRulesProvider()

    private var cachedRules: [PasswordRuleRecord]?

    func rule(for host: String) async -> String? {
        let rules = await loadRules()
        guard let record = rules?.first(where: { host.hasSuffix($0.domain) }),
              let jsonData = try? JSONEncoder().encode(record),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    /// `RemoteSettingsUtils` is not `Sendable`, so it is constructed inside the async context
    /// rather than stored — a uniquely-referenced local can cross, a stored property cannot.
    /// Tests inject a `PasswordRulesProviding` mock instead of reaching through this.
    private func loadRules() async -> [PasswordRuleRecord]? {
        if let cachedRules { return cachedRules }
        let rules: [PasswordRuleRecord]? = await RemoteSettingsUtils().fetchLocalRecords(for: .passwordRules)
        cachedRules = rules
        return rules
    }
}
