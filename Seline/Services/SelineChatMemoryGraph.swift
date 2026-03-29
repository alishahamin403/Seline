import Foundation

enum SelineChatMemoryNodeKind: String, Hashable {
    case email
    case note
    case visit
    case receipt
    case place
    case person
}

enum SelineChatMemoryRefKind: String, Hashable {
    case personID
    case personName
    case placeID
    case placeName
    case placeAlias
    case emailAddress
    case threadID
    case noteID
    case merchant
    case category
    case dayKey
    case queryTerm
}

struct SelineChatMemoryRef: Hashable {
    let kind: SelineChatMemoryRefKind
    let value: String
    let weight: Double
}

struct SelineChatMemoryNode: Hashable {
    let id: String
    let kind: SelineChatMemoryNodeKind
    let searchableText: String
    let dateInterval: DateInterval?
    let refs: [SelineChatMemoryRef]
    let matchedTerms: [String]
    let seedScore: Double
}

struct SelineChatMemoryEdge: Hashable {
    let fromID: String
    let toID: String
    let label: String
    let weight: Double
}

struct SelineChatMemoryCluster {
    let nodeIDs: [String]
    let edges: [SelineChatMemoryEdge]
    let score: Double
}

final class SelineChatMemoryClusterResolver {
    private let maxSeedCount = 8
    private let maxClusterSize = 12

    func resolve(
        frame: SelineChatQuestionFrame,
        nodes: [SelineChatMemoryNode],
        edges: [SelineChatMemoryEdge]
    ) -> SelineChatMemoryCluster? {
        guard !nodes.isEmpty else { return nil }

        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let adjacency = buildAdjacency(from: edges)

        let seeds = candidateSeeds(in: nodes, frame: frame)
        guard !seeds.isEmpty else { return nil }

        var bestCluster: SelineChatMemoryCluster?

        for seed in seeds.prefix(maxSeedCount) {
            let cluster = buildCluster(
                startingAt: seed.id,
                frame: frame,
                nodeByID: nodeByID,
                adjacency: adjacency
            )

            guard let cluster else { continue }
            if bestCluster == nil || cluster.score > bestCluster?.score ?? 0.0 {
                bestCluster = cluster
            }
        }

        return bestCluster
    }

    private func candidateSeeds(
        in nodes: [SelineChatMemoryNode],
        frame: SelineChatQuestionFrame
    ) -> [SelineChatMemoryNode] {
        nodes
            .filter { node in
                node.seedScore > 0
                    || frame.timeScope.map { intersects(node.dateInterval, interval: $0.interval) } == true
            }
            .sorted { lhs, rhs in
                if lhs.seedScore == rhs.seedScore {
                    return recencyDate(for: lhs) > recencyDate(for: rhs)
                }
                return lhs.seedScore > rhs.seedScore
            }
    }

    private func buildCluster(
        startingAt seedID: String,
        frame: SelineChatQuestionFrame,
        nodeByID: [String: SelineChatMemoryNode],
        adjacency: [String: [SelineChatMemoryEdge]]
    ) -> SelineChatMemoryCluster? {
        guard let seed = nodeByID[seedID] else { return nil }

        var selectedIDs: Set<String> = [seed.id]
        var frontier = adjacency[seed.id] ?? []

        while selectedIDs.count < maxClusterSize {
            let candidate = frontier
                .filter { !selectedIDs.contains($0.toID) }
                .max { lhs, rhs in
                    neighborValue(for: lhs, nodeByID: nodeByID) < neighborValue(for: rhs, nodeByID: nodeByID)
                }

            guard let candidate,
                  let neighbor = nodeByID[candidate.toID] else {
                break
            }

            let value = neighborValue(for: candidate, nodeByID: nodeByID)
            if selectedIDs.count > 1 && value < 1.1 {
                break
            }

            if neighbor.seedScore <= 0, candidate.weight < 0.9 {
                break
            }

            selectedIDs.insert(neighbor.id)
            frontier.append(contentsOf: adjacency[neighbor.id] ?? [])
        }

        let selectedNodes = selectedIDs.compactMap { nodeByID[$0] }
        guard !selectedNodes.isEmpty else { return nil }

        let selectedEdges = dedupeEdges(
            selectedIDs.flatMap { nodeID in
                (adjacency[nodeID] ?? []).filter {
                    selectedIDs.contains($0.fromID) && selectedIDs.contains($0.toID)
                }
            }
        )

        let score = clusterScore(
            frame: frame,
            nodes: selectedNodes,
            edges: selectedEdges
        )

        return SelineChatMemoryCluster(
            nodeIDs: selectedNodes
                .sorted { lhs, rhs in
                    if lhs.seedScore == rhs.seedScore {
                        return recencyDate(for: lhs) > recencyDate(for: rhs)
                    }
                    return lhs.seedScore > rhs.seedScore
                }
                .map(\.id),
            edges: selectedEdges,
            score: score
        )
    }

    private func buildAdjacency(from edges: [SelineChatMemoryEdge]) -> [String: [SelineChatMemoryEdge]] {
        var adjacency: [String: [SelineChatMemoryEdge]] = [:]

        for edge in dedupeEdges(edges) {
            adjacency[edge.fromID, default: []].append(edge)
            adjacency[edge.toID, default: []].append(
                SelineChatMemoryEdge(
                    fromID: edge.toID,
                    toID: edge.fromID,
                    label: edge.label,
                    weight: edge.weight
                )
            )
        }

        return adjacency
    }

    private func dedupeEdges(_ edges: [SelineChatMemoryEdge]) -> [SelineChatMemoryEdge] {
        var bestByKey: [String: SelineChatMemoryEdge] = [:]

        for edge in edges {
            let ordered = [edge.fromID, edge.toID].sorted()
            let key = "\(ordered[0])|\(ordered[1])|\(edge.label)"
            if let existing = bestByKey[key] {
                if edge.weight > existing.weight {
                    bestByKey[key] = edge
                }
            } else {
                bestByKey[key] = edge
            }
        }

        return Array(bestByKey.values)
    }

    private func neighborValue(
        for edge: SelineChatMemoryEdge,
        nodeByID: [String: SelineChatMemoryNode]
    ) -> Double {
        guard let node = nodeByID[edge.toID] else { return edge.weight }
        return edge.weight + (node.seedScore * 0.85)
    }

    private func clusterScore(
        frame: SelineChatQuestionFrame,
        nodes: [SelineChatMemoryNode],
        edges: [SelineChatMemoryEdge]
    ) -> Double {
        let totalSeedScore = nodes
            .map(\.seedScore)
            .sorted(by: >)
            .prefix(4)
            .reduce(0, +)

        let edgeBonus = min(edges.reduce(0) { $0 + $1.weight }, 8) * 0.45
        let matchedTerms = Set(nodes.flatMap(\.matchedTerms))
        let coverageBonus = Double(matchedTerms.count) * 1.2
        let domainBonus = min(Double(Set(nodes.map(\.kind)).count) * 0.25, 1.25)
        let explicitEntityCoverage = coveredEntityMentions(frame: frame, nodes: nodes)
        let explicitEntityBonus = Double(explicitEntityCoverage.count) * 2.1
        let explicitEntityPenalty: Double = {
            let missing = max(frame.entityMentions.count - explicitEntityCoverage.count, 0)
            guard frame.entityMentions.count > 1 else { return 0.0 }
            return Double(missing) * 2.4
        }()
        let timeScopeBonus = frame.timeScope == nil
            ? 0.0
            : Double(nodes.filter { intersects($0.dateInterval, interval: frame.timeScope!.interval) }.count) * 0.35

        var recencyBonus = 0.0
        if frame.prefersMostRecent, let mostRecent = nodes.map({ recencyDate(for: $0) }).max() {
            let daysAgo = max(Date().timeIntervalSince(mostRecent) / 86_400, 0)
            switch daysAgo {
            case ..<14:
                recencyBonus = 1.5
            case ..<90:
                recencyBonus = 0.9
            default:
                recencyBonus = 0.3
            }
        }

        return totalSeedScore + edgeBonus + coverageBonus + domainBonus + explicitEntityBonus + timeScopeBonus + recencyBonus - explicitEntityPenalty
    }

    private func recencyDate(for node: SelineChatMemoryNode) -> Date {
        node.dateInterval?.start ?? .distantPast
    }

    private func coveredEntityMentions(
        frame: SelineChatQuestionFrame,
        nodes: [SelineChatMemoryNode]
    ) -> Set<String> {
        var covered = Set<String>()

        for mention in frame.entityMentions {
            if nodes.contains(where: { $0.searchableText.contains(mention.normalizedValue) || $0.matchedTerms.contains(mention.normalizedValue) }) {
                covered.insert(mention.normalizedValue)
            }
        }

        return covered
    }

    private func intersects(_ lhs: DateInterval?, interval rhs: DateInterval) -> Bool {
        guard let lhs else { return false }
        return lhs.intersects(rhs)
    }
}
