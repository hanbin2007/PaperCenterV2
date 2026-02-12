//
//  GlobalSearchPreferences.swift
//  PaperCenterV2
//
//  UserDefaults-backed persistence for global search options.
//

import Foundation

@MainActor
final class GlobalSearchPreferences {
    private enum Keys {
        static let options = "globalSearch.options.v2"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var options: GlobalSearchOptions {
        get { loadOptions() }
        set { saveOptions(newValue) }
    }

    func resetToDefaults() {
        saveOptions(.default)
    }

    private func loadOptions() -> GlobalSearchOptions {
        guard let data = defaults.data(forKey: Keys.options) else {
            return .default
        }

        if let decoded = try? JSONDecoder().decode(GlobalSearchOptions.self, from: data) {
            return decoded
        }

        if let legacy = try? JSONDecoder().decode(LegacyGlobalSearchOptionsV1.self, from: data) {
            return GlobalSearchOptions(
                fieldScope: legacy.fieldScope,
                resultTypes: legacy.resultTypes,
                includeHistoricalVersions: legacy.includeHistoricalVersions,
                maxResults: legacy.maxResults,
                tagFilter: TagFilter(),
                variableRules: [],
                variableRulesMode: .and
            )
        }

        return .default
    }

    private func saveOptions(_ options: GlobalSearchOptions) {
        guard let data = try? JSONEncoder().encode(options) else {
            return
        }
        defaults.set(data, forKey: Keys.options)
    }
}

private struct LegacyGlobalSearchOptionsV1: Codable {
    let fieldScope: Set<GlobalSearchField>
    let resultTypes: Set<GlobalSearchResultKind>
    let includeHistoricalVersions: Bool
    let maxResults: Int
}
