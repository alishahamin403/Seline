import Foundation

/// Generates specialized system prompts for different query types
/// Improves accuracy for counting, comparison, temporal, and follow-up queries
class SpecializedPromptBuilder {
    static let shared = SpecializedPromptBuilder()

    // MARK: - Counting Query Prompts

    /// Generate optimized prompt for counting queries
    /// Handles "How many times did I...", "How often did I..."
    func buildCountingQueryPrompt(subject: String, timeFrame: String?, filters: [String]) -> String {
        var prompt = """
        You are a precise counter and analyst. Your task is to count occurrences accurately.

        CRITICAL RULES FOR COUNTING:
        1. Count ONLY items matching ALL specified criteria
        2. Return the exact count, not approximations
        3. If data is missing or unclear, state it explicitly
        4. Group by category if asked ("how much on each category")
        5. Double-check your count before responding

        QUERY DETAILS:
        - Counting: \(subject)
        """

        if let timeFrame = timeFrame {
            prompt += "\n- Time Period: \(timeFrame)"
        }

        if !filters.isEmpty {
            prompt += "\n- Additional Filters: \(filters.joined(separator: ", "))"
        }

        prompt += """

        FORMAT YOUR RESPONSE:
        1. Start with the exact total count
        2. Break down by categories/groups if relevant
        3. List specific items if count is small (< 10)
        4. Include date range of data found
        5. Note any uncertainties or gaps

        Remember: Accuracy is more important than brevity.
        """

        return prompt
    }

    // MARK: - Comparison Query Prompts

    /// Generate optimized prompt for comparison queries
    /// Handles "Which was more expensive", "Compare X vs Y"
    func buildComparisonQueryPrompt(metric: String, dimensions: [String], filters: [String]) -> String {
        var prompt = """
        You are a comparative analyst. Your task is to compare entities or time periods accurately.

        CRITICAL RULES FOR COMPARISONS:
        1. Calculate the metric for each dimension separately
        2. Show all values being compared
        3. Clearly state which is higher/lower/better/worse
        4. Calculate the difference or percentage change
        5. Provide context for the comparison

        COMPARISON DETAILS:
        - Metric: \(metric)
        - Comparing: \(dimensions.joined(separator: " vs "))
        """

        if !filters.isEmpty {
            prompt += "\n- Filters: \(filters.joined(separator: ", "))"
        }

        prompt += """

        FORMAT YOUR RESPONSE:
        1. State the metric being compared
        2. Show value for each dimension:
           • [Dimension 1]: [Value]
           • [Dimension 2]: [Value]
        3. Highlight the winner/highest/lowest
        4. Calculate the difference:
           • Absolute difference: [X]
           • Percentage change: [Y]%
        5. Add interpretation/insight

        Example:
        Metric: Total Spending
        • This Month: $450.25
        • Last Month: $320.50
        Difference: $129.75 higher (40% increase)
        """

        return prompt
    }

    // MARK: - Temporal Query Prompts

    /// Generate optimized prompt for temporal queries
    /// Ensures correct date range filtering and temporal understanding
    func buildTemporalQueryPrompt(dateRange: DateRange) -> String {
        let formatter = ISO8601DateFormatter()
        let periodDescription = describePeriod(dateRange.period)

        var prompt = """
        You are a temporal analyst with precise date handling.

        CRITICAL RULES FOR TEMPORAL QUERIES:
        1. Respect the EXACT date range requested
        2. Include only data within the specified period
        3. Exclude data outside the period, even if relevant
        4. Convert relative dates (this month, last week) to absolute dates
        5. Clarify date boundaries in your response

        REQUESTED TIME PERIOD: \(periodDescription)
        - Start Date: \(formatter.string(from: dateRange.start))
        - End Date: \(formatter.string(from: dateRange.end))
        """

        let now = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        prompt += """

        TODAY'S DATE: \(formatter.string(from: now))
        CURRENT MONTH: \(currentMonth)/\(currentYear)

        TEMPORAL CONVERSIONS:
        - "this month" = from day 1 of current month to today
        - "last month" = entire previous month
        - "this week" = from Monday to today of current week
        - "last week" = entire previous week
        - "today" = current date only
        - "past 30 days" = today minus 30 days to today

        RESPONSE FORMAT:
        1. State the exact date range used
        2. Confirm data falls within this range
        3. Show count of items in this period
        4. Highlight items from the specified period
        5. Note if data extends beyond the period
        """

        return prompt
    }

    // MARK: - Follow-up Query Prompts

    /// Generate optimized prompt for follow-up questions
    /// Maintains conversation context and references
    func buildFollowUpQueryPrompt(previousTopic: String?, previousTimeframe: String?, relatedQueries: [String]?) -> String {
        var prompt = """
        You are continuing a conversation. Maintain context from previous messages.

        CONTEXT FROM PREVIOUS CONVERSATION:
        """

        if let topic = previousTopic {
            prompt += "\n- Previous Topic: \(topic)"
        }

        if let timeframe = previousTimeframe {
            prompt += "\n- Previous Timeframe: \(timeframe)"
        }

        if let queries = relatedQueries, !queries.isEmpty {
            prompt += "\n- Previous Queries:\n"
            for (index, query) in queries.enumerated() {
                prompt += "  \(index + 1). \(query)\n"
            }
        }

        prompt += """

        FOLLOW-UP RULES:
        1. Reference previous context when relevant
        2. Use the same time period unless explicitly changed
        3. Maintain topic consistency unless user shifts topics
        4. Build on previous data/findings
        5. Don't repeat information already provided

        When answering this follow-up:
        1. Acknowledge the previous context
        2. Show how this question relates to the previous one
        3. Use consistent metrics and categories
        4. Reference previous findings if applicable
        5. Provide additional insights beyond the previous answer

        If the user is asking about a different topic or time period,
        explicitly note the shift: "Shifting from [previous] to [new]..."
        """

        return prompt
    }

    // MARK: - Composite Prompts

    /// Build specialized prompt combining multiple aspects
    func buildCompositePrompt(
        queryType: SpecializedQueryType,
        countingParams: CountingQueryParameters? = nil,
        comparisonParams: ComparisonQueryParameters? = nil,
        temporalParams: TemporalQueryParameters? = nil,
        followUpContext: (previousTopic: String?, previousTimeframe: String?, relatedQueries: [String]?)? = nil
    ) -> String {
        var finalPrompt = baseSystemPrompt()

        // Add specialized prompts based on query type
        switch queryType {
        case .counting:
            if let params = countingParams {
                finalPrompt += "\n\n" + buildCountingQueryPrompt(
                    subject: params.subject,
                    timeFrame: params.timeFrame,
                    filters: params.filterTerms
                )
            }

        case .comparison:
            if let params = comparisonParams {
                finalPrompt += "\n\n" + buildComparisonQueryPrompt(
                    metric: params.metric,
                    dimensions: params.dimensions,
                    filters: params.filterTerms
                )
            }

        case .temporal:
            if let params = temporalParams, let dateRange = params.dateRange {
                finalPrompt += "\n\n" + buildTemporalQueryPrompt(dateRange: dateRange)
            }

        case .followUp:
            if let context = followUpContext {
                finalPrompt += "\n\n" + buildFollowUpQueryPrompt(
                    previousTopic: context.previousTopic,
                    previousTimeframe: context.previousTimeframe,
                    relatedQueries: context.relatedQueries
                )
            }

        case .general:
            finalPrompt += "\n\n" + buildGeneralQueryPrompt()
        }

        return finalPrompt
    }

    // MARK: - Base Prompts

    private func baseSystemPrompt() -> String {
        return """
        You are a helpful personal assistant with access to the user's calendar, notes, emails, and financial data.

        CORE PRINCIPLES:
        1. Be accurate and specific - avoid vague responses
        2. When in doubt, ask for clarification
        3. Use data directly from the provided context
        4. Highlight important details with clear formatting
        5. Maintain context across the conversation

        DATA AVAILABLE:
        - Calendar events and tasks
        - Personal notes
        - Email messages
        - Financial transactions/receipts
        - Locations and places
        - Weather information

        RESPONSE GUIDELINES:
        - Use bold for key numbers: **$100** or **5 times**
        - Use bullet points for lists
        - Format dates consistently: Month Day, Year
        - Group related information
        - Keep responses concise but complete
        """
    }

    private func buildGeneralQueryPrompt() -> String {
        return """
        GENERAL QUERY GUIDELINES:
        1. Answer the user's question directly
        2. Provide relevant context from available data
        3. If multiple interpretations exist, ask for clarification
        4. Suggest related insights if helpful
        5. Be conversational but informative
        """
    }

    // MARK: - Helper Methods

    /// Convert TimePeriod enum to human-readable description
    private func describePeriod(_ period: DateRange.TimePeriod) -> String {
        switch period {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .thisWeek:
            return "This Week"
        case .nextWeek:
            return "Next Week"
        case .thisMonth:
            return "This Month"
        case .lastMonth:
            return "Last Month"
        case .thisYear:
            return "This Year"
        case .custom:
            return "Custom Period"
        }
    }
}

// MARK: - Query Type Enum

enum SpecializedQueryType {
    case counting
    case comparison
    case temporal
    case followUp
    case general
}
