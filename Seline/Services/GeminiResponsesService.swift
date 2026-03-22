import Foundation

@MainActor
final class GeminiResponsesService {
    static let shared = GeminiResponsesService()

    static let defaultChatModel = "gemini-2.5-flash-lite"
    static let escalatedChatModel = "gemini-2.5-flash"

    enum FunctionCallingMode: String {
        case auto = "AUTO"
        case any = "ANY"
    }

    private struct StoredSession {
        let contents: [[String: Any]]
        let systemInstruction: String?
        let tools: [[String: Any]]
        let functionNamesByCallId: [String: String]
    }

    private struct PreparedRequest {
        let contents: [[String: Any]]
        let systemInstruction: String?
        let tools: [[String: Any]]
        let includeServerSideToolInvocations: Bool
        let functionCallingMode: FunctionCallingMode?
    }

    private let apiKey = Config.geminiAPIKey
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let maxOutputTokens = 1400
    private let maxStoredSessions = 12

    private var sessions: [String: StoredSession] = [:]

    private init() {}

    struct FunctionCall: Hashable {
        let callId: String
        let name: String
        let argumentsJSON: String
    }

    struct CreateResult {
        let responseId: String?
        let outputText: String
        let functionCalls: [FunctionCall]
        let usedWebSearch: Bool
        let model: String?
    }

    enum ResponsesError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case unknownConversation
        case apiError(String)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Gemini API key is missing."
            case .invalidURL:
                return "Gemini API URL is invalid."
            case .invalidResponse:
                return "Gemini API returned an invalid response."
            case .unknownConversation:
                return "Gemini tool conversation state could not be restored."
            case .apiError(let message):
                return message
            case .network(let error):
                return error.localizedDescription
            }
        }
    }

    func createResponse(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        previousResponseId: String? = nil,
        functionCallingMode: FunctionCallingMode? = nil
    ) async throws -> CreateResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResponsesError.missingAPIKey
        }

        let preparedRequest: PreparedRequest
        let inheritedFunctionNames: [String: String]

        if let previousResponseId, !previousResponseId.isEmpty {
            guard let session = sessions[previousResponseId] else {
                throw ResponsesError.unknownConversation
            }
            let appendedContents = try appendFunctionOutputs(
                input,
                to: session.contents,
                functionNamesByCallId: session.functionNamesByCallId
            )
            preparedRequest = PreparedRequest(
                contents: appendedContents,
                systemInstruction: session.systemInstruction,
                tools: session.tools,
                includeServerSideToolInvocations: session.tools.contains(where: isWebSearchTool),
                functionCallingMode: functionCallingMode
            )
            inheritedFunctionNames = session.functionNamesByCallId
        } else {
            preparedRequest = try prepareInitialRequest(
                input: input,
                tools: tools,
                functionCallingMode: functionCallingMode
            )
            inheritedFunctionNames = [:]
        }

        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            throw ResponsesError.invalidURL
        }

        var requestBody: [String: Any] = [
            "contents": preparedRequest.contents,
            "generationConfig": [
                "temperature": 0.25,
                "maxOutputTokens": maxOutputTokens
            ]
        ]

        if let systemInstruction = preparedRequest.systemInstruction, !systemInstruction.isEmpty {
            requestBody["systemInstruction"] = [
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        let convertedTools = convertTools(preparedRequest.tools)
        if !convertedTools.isEmpty {
            requestBody["tools"] = convertedTools
        }
        var toolConfig: [String: Any] = [:]
        if preparedRequest.includeServerSideToolInvocations {
            toolConfig["includeServerSideToolInvocations"] = true
        }
        if let functionCallingMode = preparedRequest.functionCallingMode,
           convertedTools.contains(where: { $0["functionDeclarations"] != nil }) {
            toolConfig["functionCallingConfig"] = [
                "mode": functionCallingMode.rawValue
            ]
        }
        if !toolConfig.isEmpty {
            requestBody["toolConfig"] = toolConfig
        }

        LLMDiagnostics.logLLMRequest(
            operation: "chat_agent",
            model: model,
            payload: requestBody
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ResponsesError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let error = json["error"] as? [String: Any],
                    let message = error["message"] as? String {
                    throw ResponsesError.apiError(message)
                }
                throw ResponsesError.apiError("HTTP \(httpResponse.statusCode)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ResponsesError.invalidResponse
            }

            let result = try parseCreateResponse(json)
            let responseId = UUID().uuidString
            var functionNamesByCallId = inheritedFunctionNames
            for functionCall in result.functionCalls {
                functionNamesByCallId[functionCall.callId] = functionCall.name
            }

            if let modelContent = result.modelContent {
                let storedSession = StoredSession(
                    contents: preparedRequest.contents + [modelContent],
                    systemInstruction: preparedRequest.systemInstruction,
                    tools: preparedRequest.tools,
                    functionNamesByCallId: functionNamesByCallId
                )
                sessions[responseId] = storedSession
                trimStoredSessions(keepingNewest: responseId)
            }

            if let previousResponseId, previousResponseId != responseId {
                sessions.removeValue(forKey: previousResponseId)
            }

            return CreateResult(
                responseId: responseId,
                outputText: result.outputText,
                functionCalls: result.functionCalls,
                usedWebSearch: result.usedWebSearch,
                model: result.model
            )
        } catch let error as ResponsesError {
            throw error
        } catch {
            throw ResponsesError.network(error)
        }
    }

    private struct ParsedCreateResponse {
        let outputText: String
        let functionCalls: [FunctionCall]
        let usedWebSearch: Bool
        let model: String?
        let modelContent: [String: Any]?
    }

    private func parseCreateResponse(_ json: [String: Any]) throws -> ParsedCreateResponse {
        let model = json["modelVersion"] as? String ?? json["model"] as? String
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first
        else {
            throw ResponsesError.invalidResponse
        }

        guard let content = firstCandidate["content"] as? [String: Any] else {
            throw ResponsesError.invalidResponse
        }

        let parts = content["parts"] as? [[String: Any]] ?? []
        var outputSegments: [String] = []
        var functionCalls: [FunctionCall] = []

        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty {
                outputSegments.append(text)
            }

            let rawFunctionCall =
                (part["functionCall"] as? [String: Any]) ??
                (part["function_call"] as? [String: Any])

            guard let functionCall = rawFunctionCall else { continue }
            guard let name = functionCall["name"] as? String else { continue }

            let callId = (functionCall["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCallId = ((callId?.isEmpty == false) ? callId : nil) ?? UUID().uuidString
            let args = functionCall["args"] ?? functionCall["arguments"] ?? [:]
            let argumentsJSON = jsonString(from: args)

            functionCalls.append(
                FunctionCall(
                    callId: resolvedCallId,
                    name: name,
                    argumentsJSON: argumentsJSON
                )
            )
        }

        let usedWebSearch =
            firstCandidate["groundingMetadata"] != nil ||
            firstCandidate["grounding_metadata"] != nil

        return ParsedCreateResponse(
            outputText: outputSegments.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            functionCalls: functionCalls,
            usedWebSearch: usedWebSearch,
            model: model,
            modelContent: content
        )
    }

    private func prepareInitialRequest(
        input: [[String: Any]],
        tools: [[String: Any]],
        functionCallingMode: FunctionCallingMode?
    ) throws -> PreparedRequest {
        var contents: [[String: Any]] = []
        var systemSegments: [String] = []

        for item in input {
            if let type = item["type"] as? String, type == "function_call_output" {
                throw ResponsesError.invalidResponse
            }

            let role = (item["role"] as? String)?.lowercased() ?? "user"
            let text = extractText(from: item).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if role == "developer" || role == "system" {
                systemSegments.append(text)
                continue
            }

            contents.append([
                "role": role == "assistant" ? "model" : "user",
                "parts": [["text": text]]
            ])
        }

        return PreparedRequest(
            contents: contents,
            systemInstruction: systemSegments.isEmpty ? nil : systemSegments.joined(separator: "\n\n"),
            tools: tools,
            includeServerSideToolInvocations: tools.contains(where: isWebSearchTool),
            functionCallingMode: functionCallingMode
        )
    }

    private func appendFunctionOutputs(
        _ input: [[String: Any]],
        to contents: [[String: Any]],
        functionNamesByCallId: [String: String]
    ) throws -> [[String: Any]] {
        var updatedContents = contents

        for item in input {
            let itemType = item["type"] as? String ?? ""
            if itemType == "function_call_output" {
                guard let callId = item["call_id"] as? String, !callId.isEmpty else {
                    throw ResponsesError.invalidResponse
                }
                let outputString = item["output"] as? String ?? "{}"
                let responsePayload = decodedJSONObject(from: outputString) ?? ["raw": outputString]
                let functionName = functionNamesByCallId[callId] ?? "tool_result"

                updatedContents.append([
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "id": callId,
                            "name": functionName,
                            "response": [
                                "result": responsePayload
                            ]
                        ]
                    ]]
                ])
                continue
            }

            let role = (item["role"] as? String)?.lowercased() ?? "user"
            let text = extractText(from: item).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            updatedContents.append([
                "role": role == "assistant" ? "model" : "user",
                "parts": [["text": text]]
            ])
        }

        return updatedContents
    }

    private func extractText(from item: [String: Any]) -> String {
        if let text = item["text"] as? String {
            return text
        }

        guard let content = item["content"] as? [[String: Any]] else {
            return ""
        }

        return content.compactMap { entry in
            if let text = entry["text"] as? String {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func convertTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        let functionDeclarations = tools.compactMap { tool -> [String: Any]? in
            guard (tool["type"] as? String) == "function" else { return nil }
            guard let name = tool["name"] as? String else { return nil }

            var declaration: [String: Any] = ["name": name]
            if let description = tool["description"] as? String, !description.isEmpty {
                declaration["description"] = description
            }
            if let parameters = tool["parameters"] as? [String: Any] {
                declaration["parameters"] = parameters
            }
            return declaration
        }

        var converted: [[String: Any]] = []
        if !functionDeclarations.isEmpty {
            converted.append(["functionDeclarations": functionDeclarations])
        }
        if tools.contains(where: isWebSearchTool) {
            converted.append(["googleSearch": [:]])
        }
        return converted
    }

    private func isWebSearchTool(_ tool: [String: Any]) -> Bool {
        let type = (tool["type"] as? String)?.lowercased()
        return type == "web_search" || tool["googleSearch"] != nil || tool["google_search"] != nil
    }

    private func decodedJSONObject(from string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private func jsonString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func trimStoredSessions(keepingNewest newestId: String) {
        guard sessions.count > maxStoredSessions else { return }

        let overflow = sessions.keys.filter { $0 != newestId }.prefix(sessions.count - maxStoredSessions)
        for key in overflow {
            sessions.removeValue(forKey: key)
        }
    }
}
