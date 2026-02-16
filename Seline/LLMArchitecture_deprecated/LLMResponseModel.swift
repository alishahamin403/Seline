import Foundation

/// Structured response format returned by LLM
struct LLMResponse: Decodable {
    let thinking: String?         // Chain-of-thought reasoning (why did you choose this data?)
    let response: String          // Natural language answer
    let dataUsed: [String]        // IDs or types of data referenced
    let confidence: Double        // 0.0 - 1.0, how certain is the LLM?
    let needsClarification: Bool  // Does the LLM need more info?
    let clarifyingQuestions: [String]  // Questions for user if not clear
    let dataReferences: DataReferences?  // Optional: specific IDs referenced

    struct DataReferences: Decodable {
        let noteIds: [String]?
        let locationIds: [String]?
        let taskIds: [String]?
        let emailIds: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case thinking
        case response
        case dataUsed = "data_used"
        case confidence
        case needsClarification = "needs_clarification"
        case clarifyingQuestions = "clarifying_questions"
        case dataReferences = "data_references"
    }
}

/// Validation result from validator
enum ValidationResult {
    case valid(LLMResponse)                    // Response is accurate
    case lowConfidence(LLMResponse)            // Valid but LLM is unsure
    case hallucination(reason: String)         // LLM made something up
    case partiallyValid(LLMResponse, issues: [String])  // Some refs missing
    case needsClarification(clarifyingQuestions: [String])  // Ask user to clarify
}

/// Validation issue found
struct ValidationIssue {
    let severity: Severity  // Critical, warning, info
    let message: String
    let suggestion: String?

    enum Severity: String {
        case critical   // Response is wrong/hallucinated
        case warning    // Some data missing but response still useful
        case info       // Minor issue, response is fine
    }
}

/// Extended response with validation metadata
struct ValidatedLLMResponse {
    let response: LLMResponse
    let validationResult: ValidationResult
    let issues: [ValidationIssue]
    let isAccurate: Bool  // confidence > 0.75 && no critical issues
}
