//
//  AutocompleteEngine.swift
//  PostgresGUI
//
//  Ranking and filtering engine for SQL autocomplete suggestions.
//

import Foundation

enum AutocompleteEngine {
    private nonisolated static var baseKeywords: [String] {
        [
            "SELECT",
            "FROM",
            "WHERE",
            "JOIN",
            "LEFT JOIN",
            "RIGHT JOIN",
            "INNER JOIN",
            "ORDER BY",
            "GROUP BY",
            "HAVING",
            "INSERT INTO",
            "VALUES",
            "UPDATE",
            "SET",
            "DELETE FROM",
            "RETURNING",
            "LIMIT",
            "OFFSET",
            "WITH",
            "UNION",
            "EXISTS",
            "AND",
            "OR",
            "NOT",
            "NULL"
        ]
    }

    private nonisolated static var postRelationKeywords: [String] {
        [
            "JOIN",
            "LEFT JOIN",
            "RIGHT JOIN",
            "INNER JOIN",
            "ON",
            "WHERE",
            "GROUP BY",
            "ORDER BY",
            "HAVING",
            "LIMIT",
            "OFFSET"
        ]
    }

    private struct SuggestionCandidate {
        let item: SuggestionItem
        let searchText: String
    }

    private struct MatchScore: Comparable {
        let tier: Int
        let position: Int
        let gapPenalty: Int
        let textLength: Int
        let searchText: String

        nonisolated static func == (lhs: MatchScore, rhs: MatchScore) -> Bool {
            lhs.tier == rhs.tier
                && lhs.position == rhs.position
                && lhs.gapPenalty == rhs.gapPenalty
                && lhs.textLength == rhs.textLength
                && lhs.searchText == rhs.searchText
        }

        nonisolated static func < (lhs: MatchScore, rhs: MatchScore) -> Bool {
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }

            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }

            if lhs.gapPenalty != rhs.gapPenalty {
                return lhs.gapPenalty < rhs.gapPenalty
            }

            if lhs.textLength != rhs.textLength {
                return lhs.textLength < rhs.textLength
            }

            return lhs.searchText < rhs.searchText
        }
    }

    private nonisolated static var defaultSuggestionLimit: Int { 100 }

    nonisolated static func suggestions(
        for analysis: SQLContextAnalysis,
        provider: DatabaseMetadataProvider,
        maximumResults: Int = defaultSuggestionLimit
    ) async -> [SuggestionItem] {
        guard maximumResults > 0 else {
            return []
        }

        let candidates = await candidates(for: analysis, provider: provider)

        guard !candidates.isEmpty else {
            return []
        }

        let normalizedQuery = normalize(analysis.currentWord)
        if normalizedQuery.isEmpty {
            return Array(candidates.prefix(maximumResults)).map(\.item)
        }

        let rankedItems = candidates
            .compactMap { candidate -> (item: SuggestionItem, score: MatchScore)? in
                guard let score = matchScore(query: normalizedQuery, searchText: candidate.searchText) else {
                    return nil
                }

                return (candidate.item, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }

                return lhs.item.id < rhs.item.id
            }
            .prefix(maximumResults)
            .map(\.item)

        return Array(rankedItems)
    }

    private nonisolated static func candidates(
        for analysis: SQLContextAnalysis,
        provider: DatabaseMetadataProvider
    ) async -> [SuggestionCandidate] {
        switch analysis.context {
        case .tablesAndSchemas(let schemaQualifier):
            return await tableAndSchemaCandidates(
                analysis: analysis,
                schemaQualifier: schemaQualifier,
                provider: provider
            )
        case .columnsGlobal:
            return await globalColumnCandidates(
                aliasMap: analysis.aliasMap,
                provider: provider
            )
        case .columnsSpecific(let alias):
            return await specificColumnCandidates(
                alias: alias,
                aliasMap: analysis.aliasMap,
                provider: provider
            )
        case .keywords:
            return keywordCandidates(
                matching: analysis.currentWord,
                keywords: baseKeywords
            )
        case .none:
            return []
        }
    }

    private nonisolated static func tableAndSchemaCandidates(
        analysis: SQLContextAnalysis,
        schemaQualifier: String?,
        provider: DatabaseMetadataProvider
    ) async -> [SuggestionCandidate] {
        if let schemaQualifier {
            await ensureSchemaLoaded(named: schemaQualifier, provider: provider)
            let relations = await provider.relations(in: schemaQualifier)
            return deduplicatedCandidates(relations.map {
                relationCandidate($0, replacementText: $0.name)
            })
        }

        let lookupSchemas = await provider.schemaLookupOrder()
        guard !lookupSchemas.isEmpty else {
            return []
        }

        let searchPathSchemas = await provider.currentSearchPathSchemas()
        let searchPathSchemaSet = Set(searchPathSchemas)

        var candidates: [SuggestionCandidate] = []
        let clauseCandidates = keywordCandidates(
            matching: analysis.currentWord,
            keywords: postRelationKeywords
        )

        if shouldPrioritizePostRelationKeywords(in: analysis) {
            candidates.append(contentsOf: clauseCandidates)
        }

        for schemaName in searchPathSchemas {
            let relations = await provider.relations(in: schemaName)
            candidates.append(contentsOf: relations.map(defaultRelationCandidate))
        }

        candidates.append(contentsOf: lookupSchemas.map(schemaCandidate))

        if !shouldPrioritizePostRelationKeywords(in: analysis), !analysis.aliasMap.isEmpty {
            candidates.append(contentsOf: clauseCandidates)
        }

        for schemaName in lookupSchemas where !searchPathSchemaSet.contains(schemaName) {
            let relations = await provider.relations(in: schemaName)
            candidates.append(contentsOf: relations.map(defaultRelationCandidate))
        }

        return deduplicatedCandidates(candidates)
    }

    private nonisolated static func specificColumnCandidates(
        alias: String,
        aliasMap: [String: SQLRelationReference],
        provider: DatabaseMetadataProvider
    ) async -> [SuggestionCandidate] {
        guard let reference = aliasMap[alias.lowercased()] else {
            return []
        }

        if let schemaName = reference.schemaName {
            await ensureSchemaLoaded(named: schemaName, provider: provider)
        }

        let columns = await provider.columns(for: reference)
        return deduplicatedCandidates(columns.map(specificColumnCandidate))
    }

    private nonisolated static func globalColumnCandidates(
        aliasMap: [String: SQLRelationReference],
        provider: DatabaseMetadataProvider
    ) async -> [SuggestionCandidate] {
        let schemaLookupOrder = await provider.schemaLookupOrder()
        let schemaRanks = Dictionary(
            uniqueKeysWithValues: schemaLookupOrder.enumerated().map { ($1, $0) }
        )

        let references = Set(aliasMap.values)
        var relations: [DBRelationSummary] = []
        var seenRelationOids = Set<Int64>()

        for reference in references {
            if let schemaName = reference.schemaName {
                await ensureSchemaLoaded(named: schemaName, provider: provider)
            }

            guard let relation = await provider.relation(for: reference),
                  seenRelationOids.insert(relation.oid).inserted else {
                continue
            }

            relations.append(relation)
        }

        relations.sort { lhs, rhs in
            let lhsRank = schemaRanks[lhs.schema] ?? Int.max
            let rhsRank = schemaRanks[rhs.schema] ?? Int.max

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            if lhs.schema != rhs.schema {
                return lhs.schema < rhs.schema
            }

            return lhs.name < rhs.name
        }

        var candidates: [SuggestionCandidate] = []

        for relation in relations {
            let columns = await provider.columns(forRelationOid: relation.oid)
            candidates.append(
                contentsOf: columns.map { column in
                    globalColumnCandidate(column, relation: relation)
                }
            )
        }

        return deduplicatedCandidates(candidates)
    }

    private nonisolated static func schemaCandidate(_ schemaName: String) -> SuggestionCandidate {
        SuggestionCandidate(
            item: SuggestionItem(
                title: schemaName,
                subtitle: "schema",
                replacementText: "\(schemaName).",
                iconType: .schema
            ),
            searchText: schemaName
        )
    }

    private nonisolated static func defaultRelationCandidate(
        _ relation: DBRelationSummary
    ) -> SuggestionCandidate {
        let replacementText = relation.schema == "public"
            ? relation.name
            : relation.qualifiedName

        return relationCandidate(relation, replacementText: replacementText)
    }

    private nonisolated static func relationCandidate(
        _ relation: DBRelationSummary,
        replacementText: String
    ) -> SuggestionCandidate {
        SuggestionCandidate(
            item: SuggestionItem(
                title: relation.name,
                subtitle: "\(relation.kind.displayName) • \(relation.schema)",
                replacementText: replacementText,
                iconType: SuggestionIconType(relationKind: relation.kind)
            ),
            searchText: relation.name
        )
    }

    private nonisolated static func specificColumnCandidate(
        _ column: DBColumnSummary
    ) -> SuggestionCandidate {
        SuggestionCandidate(
            item: SuggestionItem(
                title: column.name,
                subtitle: column.dataType,
                iconType: .column
            ),
            searchText: column.name
        )
    }

    private nonisolated static func globalColumnCandidate(
        _ column: DBColumnSummary,
        relation: DBRelationSummary
    ) -> SuggestionCandidate {
        SuggestionCandidate(
            item: SuggestionItem(
                title: column.name,
                subtitle: "\(column.dataType) • \(relation.schema).\(relation.name)",
                iconType: .column
            ),
            searchText: column.name
        )
    }

    private nonisolated static func keywordCandidates(
        matching currentWord: String,
        keywords: [String]
    ) -> [SuggestionCandidate] {
        keywords.map { keywordCandidate($0, currentWord: currentWord) }
    }

    private nonisolated static func keywordCandidate(
        _ keyword: String,
        currentWord: String
    ) -> SuggestionCandidate {
        let renderedKeyword = renderKeyword(keyword, matching: currentWord)

        return SuggestionCandidate(
            item: SuggestionItem(
                title: renderedKeyword,
                subtitle: "keyword",
                replacementText: renderedKeyword,
                iconType: .keyword
            ),
            searchText: keyword
        )
    }

    private nonisolated static func deduplicatedCandidates(
        _ candidates: [SuggestionCandidate]
    ) -> [SuggestionCandidate] {
        var deduplicated: [SuggestionCandidate] = []
        var seenIds = Set<String>()

        for candidate in candidates where seenIds.insert(candidate.item.id).inserted {
            deduplicated.append(candidate)
        }

        return deduplicated
    }

    private nonisolated static func matchScore(
        query: String,
        searchText: String
    ) -> MatchScore? {
        let normalizedText = normalize(searchText)
        guard !normalizedText.isEmpty else {
            return nil
        }

        if normalizedText.hasPrefix(query) {
            return MatchScore(
                tier: 0,
                position: 0,
                gapPenalty: 0,
                textLength: normalizedText.count,
                searchText: normalizedText
            )
        }

        if let range = normalizedText.range(of: query) {
            let position = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
            return MatchScore(
                tier: 1,
                position: position,
                gapPenalty: 0,
                textLength: normalizedText.count,
                searchText: normalizedText
            )
        }

        guard let fuzzyMatch = subsequenceMatch(query: query, text: normalizedText) else {
            return nil
        }

        return MatchScore(
            tier: 2,
            position: fuzzyMatch.firstMatchIndex,
            gapPenalty: fuzzyMatch.gapPenalty,
            textLength: normalizedText.count,
            searchText: normalizedText
        )
    }

    private nonisolated static func subsequenceMatch(
        query: String,
        text: String
    ) -> (firstMatchIndex: Int, gapPenalty: Int)? {
        var searchIndex = text.startIndex
        var previousOffset: Int?
        var firstOffset: Int?
        var gapPenalty = 0

        for queryCharacter in query {
            guard let matchIndex = text[searchIndex...].firstIndex(of: queryCharacter) else {
                return nil
            }

            let offset = text.distance(from: text.startIndex, to: matchIndex)
            if let previousOffset {
                gapPenalty += max(0, offset - previousOffset - 1)
            } else {
                firstOffset = offset
            }

            previousOffset = offset
            searchIndex = text.index(after: matchIndex)
        }

        guard let firstOffset else {
            return nil
        }

        return (firstOffset, gapPenalty)
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.lowercased()
    }

    private nonisolated static func renderKeyword(
        _ keyword: String,
        matching currentWord: String
    ) -> String {
        let lettersOnly = currentWord.filter(\.isLetter)
        guard !lettersOnly.isEmpty else {
            return keyword
        }

        if lettersOnly == lettersOnly.lowercased() {
            return keyword.lowercased()
        }

        if lettersOnly == lettersOnly.uppercased() {
            return keyword.uppercased()
        }

        return keyword
    }

    private nonisolated static func shouldPrioritizePostRelationKeywords(
        in analysis: SQLContextAnalysis
    ) -> Bool {
        guard analysis.currentWord.isEmpty,
              !analysis.aliasMap.isEmpty else {
            return false
        }

        guard case .tablesAndSchemas(schemaQualifier: nil) = analysis.context else {
            return false
        }

        guard let trailingCharacter = analysis.activeStatement
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .last else {
            return false
        }

        return trailingCharacter != ","
    }

    private nonisolated static func ensureSchemaLoaded(
        named schemaName: String,
        provider: DatabaseMetadataProvider
    ) async {
        if await provider.hasLoadedSchema(schemaName) {
            return
        }

        var targetSchemas = Set([schemaName])
        let lowercaseSchemaName = schemaName.lowercased()
        targetSchemas.insert(lowercaseSchemaName)

        do {
            try await provider.refresh(targetSchemas: targetSchemas)
        } catch {
            return
        }
    }
}
