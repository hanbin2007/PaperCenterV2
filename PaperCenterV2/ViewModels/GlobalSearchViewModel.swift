import Foundation
import SwiftData

@MainActor
@Observable final class GlobalSearchViewModel {
    var query: String
    var options: GlobalSearchOptions
    var results: [GlobalSearchResult] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let preferences: GlobalSearchPreferences
    private let modelContainer: ModelContainer
    private var searchTask: Task<Void, Never>?

    init(modelContext: ModelContext, preferences: GlobalSearchPreferences? = nil) {
        self.modelContainer = modelContext.container
        self.preferences = preferences ?? GlobalSearchPreferences()
        self.query = ""
        self.options = self.preferences.options
    }

    func onQueryChanged(_ newValue: String) {
        query = newValue
        scheduleDebouncedSearch()
    }

    func applyOptions(_ newOptions: GlobalSearchOptions) {
        options = newOptions
        preferences.options = newOptions
        performSearchNow()
    }

    func resetToDefaults() {
        let defaults = GlobalSearchOptions.default
        options = defaults
        preferences.options = defaults
        performSearchNow()
    }

    func performSearchNow() {
        searchTask?.cancel()
        isLoading = true
        errorMessage = nil
        let currentQuery = query
        let currentOptions = options
        let container = modelContainer

        searchTask = Task.detached {
            let context = ModelContext(container)
            let service = GlobalSearchService(modelContext: context)
            let searchResults = service.search(query: currentQuery, options: currentOptions)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.results = searchResults
                self.isLoading = false
            }
        }
    }

    func scheduleDebouncedSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.performSearchNow() }
        }
    }

    var filterSummary: String {
        let rangePart = "Scope \(options.fieldScope.count)/\(GlobalSearchField.allCases.count)"
        let typePart = "Type \(options.resultTypes.count)/\(GlobalSearchResultKind.allCases.count)"
        let tagPart: String
        if options.tagFilter.isActive {
            let selectedCount = options.tagFilter.selectedTagIDs.count
            let keyword = options.tagFilter.nameKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts: [String] = []
            if !keyword.isEmpty { parts.append("keyword") }
            if selectedCount > 0 { parts.append("\(selectedCount) tags") }
            let mode = options.tagFilter.mode == .all ? "ALL" : "ANY"
            tagPart = "Tag \(mode) [\(parts.joined(separator: ", "))]"
        } else {
            tagPart = "Tag off"
        }
        let variablePart = options.variableRules.isEmpty ? "Variable off" : "Variable \(options.variableRulesMode.title) \(options.variableRules.count)"
        return [rangePart, typePart, tagPart, variablePart].joined(separator: " • ")
    }
}
