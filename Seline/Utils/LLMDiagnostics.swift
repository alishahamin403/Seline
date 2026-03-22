import Foundation

enum LLMDiagnostics {
    private static let llmDefaultsKey = "trace_llm_payloads"
    private static let embeddingDefaultsKey = "trace_embedding_payloads"

    static var isLLMTracingEnabled: Bool {
        flagEnabled(envKeys: ["TRACE_LLM_PAYLOADS", "DEBUG_LLM_PAYLOADS"], defaultsKey: llmDefaultsKey)
    }

    static var isEmbeddingTracingEnabled: Bool {
        isLLMTracingEnabled || flagEnabled(
            envKeys: ["TRACE_EMBEDDING_PAYLOADS", "DEBUG_EMBEDDING_PAYLOADS"],
            defaultsKey: embeddingDefaultsKey
        )
    }

    static func logPromptAssembly(
        operation: String,
        query: String,
        systemPrompt: String,
        messages: [[String: String]]
    ) {
        guard isLLMTracingEnabled else { return }

        print("=== LLM PROMPT ASSEMBLY [\(operation)] ===")
        print("Query: \(query)")
        print("System prompt chars: \(systemPrompt.count)")
        print("Conversation messages: \(messages.count)")

        for (index, message) in messages.enumerated() {
            let role = message["role"] ?? "unknown"
            let content = message["content"] ?? ""
            print("  [\(index + 1)] \(role): \(content.count) chars")
        }

        print("--- System Prompt Preview ---")
        print(truncated(systemPrompt, maxLength: 8000))
        print("=== END LLM PROMPT ASSEMBLY ===")
    }

    static func logLLMRequest(
        operation: String?,
        model: String,
        payload: [String: Any]
    ) {
        guard isLLMTracingEnabled else { return }

        print("=== LLM REQUEST [\(operation ?? "unknown")] model=\(model) ===")
        if let prettyJSON = prettyPrintedJSON(payload, maxLength: 12000) {
            print(prettyJSON)
        } else {
            print("Unable to render request payload as JSON.")
        }
        print("=== END LLM REQUEST ===")
    }

    static func logEmbeddingRequest(_ payload: [String: Any]) {
        guard isEmbeddingTracingEnabled else { return }

        let action = payload["action"] as? String ?? "unknown"
        print("=== EMBEDDINGS REQUEST [\(action)] ===")

        if action == "batch_embed",
           let documents = payload["documents"] as? [[String: Any]] {
            let documentTypes = documents.compactMap { $0["document_type"] as? String }
            let summary = Dictionary(grouping: documentTypes, by: { $0 }).mapValues(\.count)
            print("Documents: \(documents.count)")
            print("Type breakdown: \(summary)")
            let sampleTitles = documents.compactMap { $0["title"] as? String }.prefix(5)
            if !sampleTitles.isEmpty {
                print("Sample titles: \(Array(sampleTitles))")
            }
        }

        if let prettyJSON = prettyPrintedJSON(payload, maxLength: 12000) {
            print(prettyJSON)
        } else {
            print("Unable to render embeddings payload as JSON.")
        }

        print("=== END EMBEDDINGS REQUEST ===")
    }

    private static func flagEnabled(envKeys: [String], defaultsKey: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        for key in envKeys {
            if let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               ["1", "true", "yes", "on"].contains(rawValue) {
                return true
            }
        }

        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private static func prettyPrintedJSON(_ payload: [String: Any], maxLength: Int) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return truncated(string, maxLength: maxLength)
    }

    private static func truncated(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        return String(string.prefix(maxLength)) + "\n...[truncated \(string.count - maxLength) chars]"
    }
}
