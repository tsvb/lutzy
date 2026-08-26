import Foundation

struct LUTImportMatch: Identifiable, Equatable {
    let id: LUTID
    let name: String
    let similarity: Double
    let sharedTraits: [String]
}

struct LUTImportRecommendation: Identifiable, Equatable {
    let id: LUTID
    let name: String
    let inputSpace: LUTInputSpace
    let tags: [String]
    let matches: [LUTImportMatch]
}

struct LUTImportReview: Identifiable, Equatable {
    let id = UUID()
    let imported: Int
    let duplicates: Int
    let failed: Int
    let comparedAgainst: Int
    let recommendations: [LUTImportRecommendation]
}

struct LUTSimilarityCandidate: Equatable {
    let id: LUTID
    let name: String
    let fingerprint: String
    let inputSpace: LUTInputSpace
    let metrics: LUTMetrics
    let measuredTags: [String]
}

/// Rank an imported transform against records that existed before the import.
/// This layer is pure so ranking cannot accidentally mutate Catalog metadata,
/// and so exact-fingerprint exclusion and the top-three limit are testable
/// without driving an Open panel.
enum LUTImportRecommender {
    static func matches(
        for imported: LUTSimilarityCandidate,
        among existing: [LUTSimilarityCandidate],
        limit: Int = 3
    ) -> [LUTImportMatch] {
        let matches = existing.compactMap { candidate -> LUTImportMatch? in
            guard imported.fingerprint != candidate.fingerprint,
                  let similarity = LUTSimilarity.score(
                    imported.metrics, inputSpace: imported.inputSpace,
                    against: candidate.metrics, inputSpace: candidate.inputSpace
                  ),
                  similarity >= LUTSimilarity.confidenceFloor
            else { return nil }
            return LUTImportMatch(
                id: candidate.id,
                name: candidate.name,
                similarity: similarity,
                sharedTraits: LUTSimilarity.sharedTraits(
                    imported.measuredTags, candidate.measuredTags
                )
            )
        }.sorted {
            if abs($0.similarity - $1.similarity) > 0.000_001 {
                return $0.similarity > $1.similarity
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return Array(matches.prefix(max(limit, 0)))
    }
}
