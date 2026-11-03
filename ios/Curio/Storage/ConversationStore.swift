import Foundation

/// Saved assistant conversations, one JSON file each, plus an index.
final class ConversationStore {
    private let index = JSONFile<[ConversationSummary]>("conversations.json")
    private var summaries: [ConversationSummary]

    init() {
        summaries = index.load() ?? []
    }

    private func file(_ id: UUID) -> JSONFile<Conversation> {
        JSONFile(url: StoragePaths.dataDirectory.appending(path: "conversations/\(id.uuidString).json"))
    }

    /// Most recently updated first.
    func list(limit: Int) -> [ConversationSummary] {
        Array(summaries.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    func load(_ id: UUID) -> Conversation? { file(id).load() }

    func save(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else { return }
        file(conversation.id).save(conversation)
        summaries.removeAll { $0.id == conversation.id }
        summaries.append(conversation.summary)
        index.save(summaries)
    }

    func delete(_ id: UUID) {
        summaries.removeAll { $0.id == id }
        index.save(summaries)
        let url = file(id).url
        Task { await DiskWriter.shared.remove(url) }
    }

    func deleteAll() {
        for summary in summaries { delete(summary.id) }
    }
}
