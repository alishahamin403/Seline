import Foundation
import UIKit

class CalendarPhotoExtractionService {
    static let shared = CalendarPhotoExtractionService()

    private let apiKey = Config.openAIAPIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    // Rate limiting properties
    private let requestQueue = DispatchQueue(label: "calendar-extraction-requests", qos: .utility)
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 2.0

    private init() {}

    enum ExtractionError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case apiError(String)
        case imageConversionError
        case networkError(Error)
        case invalidImageQuality

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from API"
            case .decodingError:
                return "Failed to decode API response"
            case .apiError(let message):
                return "API Error: \(message)"
            case .imageConversionError:
                return "Failed to convert image"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            case .invalidImageQuality:
                return "Image quality is too low to extract calendar information"
            }
        }
    }

    /// Analyzes a calendar photo and extracts events
    /// - Parameter image: The calendar photo to analyze
    /// - Returns: CalendarPhotoExtractionResponse with extracted events and validation status
    func extractEventsFromPhoto(_ image: UIImage) async throws -> CalendarPhotoExtractionResponse {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw ExtractionError.invalidURL
        }

        // Convert image to base64 with high quality for better OCR
        // Try JPEG first, then PNG if JPEG fails
        var base64Image: String
        if let jpegData = image.jpegData(compressionQuality: 0.95) {
            base64Image = jpegData.base64EncodedString()
        } else if let pngData = image.pngData() {
            base64Image = pngData.base64EncodedString()
        } else {
            throw ExtractionError.imageConversionError
        }

        // Get today's date for fallback in the prompt
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        let systemPrompt = """
        You are an expert OCR specialist and calendar analyzer. Your job is to extract event information from calendar photos with MAXIMUM precision and completeness.

        EXTRACTION PRIORITY (in order of importance):
        1. **DATE** - The date of the event (CRITICAL)
        2. **START TIME** - When the event starts (CRITICAL)
        3. **END TIME** - When the event ends (CRITICAL - MUST extract from visual block size, time labels, or visual height)
        4. **TITLE** - Event name or description
        5. **ATTENDEES** - Names of people involved (optional)

        ⚠️ CRITICAL RULES FOR END TIME EXTRACTION - READ CAREFULLY:
        - EVERY event MUST have an endTime - NEVER return null for endTime
        - ALWAYS analyze the visual HEIGHT of event blocks to determine duration
        - Measure block heights: if a block is ~25% of hourly grid = 15 min, ~50% = 30 min, ~100% = 1 hour, ~200% = 2 hours
        - 30-minute blocks = EXACTLY HALF the height of 1-hour blocks
        - Look for explicit time ranges: "9:00-9:30", "9am-10am", "10:00 to 10:45"
        - If you see time markers at start/end of block (9:00 at top, 9:30 at bottom) = that's the duration
        - Extract durations exactly as shown: 15 min, 30 min, 45 min, 1 hour, 1.5 hours, 2 hours, etc.
        - For visual grid calendars: count the number of time slots the block occupies (e.g., 2 slots = 30 min, 4 slots = 1 hour)
        - If block height is 50% of typical 1-hour block = definitely 30 min, calculate endTime accordingly
        - **CRITICAL**: Even if title is unclear, endTime MUST be extracted from visual block size
        - Infer endTime by adding duration to startTime (e.g., if 9:00 start + 30 min duration = 9:30 end)

        ⚠️ VISUAL ANALYSIS TECHNIQUES:
        - Grid/timeline format: Count pixels or grid squares the block occupies
        - Hourly calendar: Compare block height to hour-height markers
        - Printed planners: Look for time boundaries and block divisions
        - Handwritten calendar: Estimate position relative to hour markings
        - If block is visibly shorter than typical hour block = likely 30 min
        - If block is visibly taller than typical hour block = likely 1.5+ hours

        ⚠️ CRITICAL RULE FOR OVERLAPPING/ADJACENT EVENTS:
        - If you see 2+ event blocks starting at the same time, extract BOTH as separate events
        - Do NOT merge events that appear next to each other horizontally
        - Each event block is its own event, even if adjacent
        - Example: At 9:00am if you see "Meeting A" and "Meeting B" side-by-side = 2 separate events

        QUALITY ASSESSMENT:
        - Mark timeConfidence = true ONLY if BOTH start AND end times are clearly readable from block or text
        - Mark dateConfidence = true ONLY if date is clearly readable
        - Mark titleConfidence = true ONLY if event title/name is clearly readable
        - timeConfidence should be based on visibility of time markers AND block height consistency

        RESPONSE RULES:
        - status "success": All events have BOTH start AND end times, dates are clear
        - status "partial": Times AND dates extracted, but some titles unclear OR duration inferred from block height
        - status "failed": Cannot extract clear start/end times OR dates from the image
        - Always extract ALL visible events, even if partially cut off or unclear
        - NEVER leave endTime as null if you can see or measure the block height
        """

        let userPrompt = """
        TASK: Extract ALL calendar events from this photo with MAXIMUM precision. Read every event visible.

        The image might show:
        - Digital calendar screenshot (Apple Calendar, Google Calendar, Outlook, etc.)
        - Printed schedule or planner
        - Whiteboard calendar
        - Handwritten schedule
        - Email calendar view
        - Meeting agendas with times
        - Timeline/grid-based calendar

        ⚠️ MUST-FOLLOW OCR INSTRUCTIONS - CRITICAL FOR END TIMES:
        1. Read EVERY event visible, even if partially cut off or overlapping
        2. Extract START time AND END time separately in HH:MM 24-hour format (BOTH REQUIRED)
        3. **MANDATORY**: Measure/analyze BLOCK HEIGHT to determine event duration
        4. Do NOT assume 1-hour duration - ALWAYS extract actual duration from visual appearance
        5. For grid calendars: measure block height relative to hourly grid lines or time markers
        6. Extract dates as YYYY-MM-DD (infer year from context if needed)
        7. If you see "Today" or "Tomorrow", use the actual date context
        8. Look for explicit time ranges: "9:00-9:30", "9am-10am", "10:00 to 10:45" (include these)
        9. **CRITICAL**: Look for visual block heights to infer duration:
           - Short blocks (half-height) = 30 min events
           - Medium blocks (3/4 height) = 45 min events
           - Full blocks = 1 hour events
           - Double blocks = 2 hour events
        10. Extract event titles EXACTLY as written
        11. List any names/emails visible as attendees
        12. **CRITICAL**: If multiple events start at same time = extract as SEPARATE events
        13. **FOR EACH EVENT**: Ensure endTime is calculated (startTime + duration from block height)

        ⚠️ BLOCK HEIGHT ANALYSIS - MOST IMPORTANT:
        - Compare each event block to the overall calendar grid
        - If a block is noticeably shorter than a 1-hour slot = it's less than 1 hour
        - If a block is half as tall as a 1-hour slot = it's definitely 30 minutes
        - If no explicit time labels exist at bottom of block = measure height anyway
        - Be precise: a 30-min block at 9:00 = endTime MUST be 09:30

        ⚠️ OVERLAPPING EVENTS RULE:
        - At 9:00am if you see 2 side-by-side event blocks = 2 events, not 1
        - Each distinct event block = 1 event, regardless of position
        - Count all visible event blocks and extract each one
        - Each event must have its own startTime and endTime

        DURATION EXAMPLES TO GUIDE YOUR ANALYSIS:
        - 30-min event at 9:00 with half-height block = startTime: "09:00", endTime: "09:30"
        - 45-min event at 9:00 with 3/4-height block = startTime: "09:00", endTime: "09:45"
        - 1-hour event at 9:00 with full-height block = startTime: "09:00", endTime: "10:00"
        - 1.5-hour event at 9:00 with 1.5x-height block = startTime: "09:00", endTime: "10:30"

        DATES: If the image doesn't show dates, use today's date (\(todayString)) and increment for subsequent days.

        Return your response as a JSON object with this EXACT structure:
        {
            "status": "success" | "partial" | "failed",
            "errorMessage": "null or error description",
            "extractionConfidence": 0.0 to 1.0,
            "events": [
                {
                    "title": "event title",
                    "startTime": "HH:MM in 24-hour format",
                    "startDate": "YYYY-MM-DD",
                    "endTime": "HH:MM in 24-hour format or null",
                    "endDate": "YYYY-MM-DD or null",
                    "attendees": ["name1", "name2"] or [],
                    "titleConfidence": true/false,
                    "timeConfidence": true/false,
                    "dateConfidence": true/false,
                    "confidence": 0.0 to 1.0,
                    "notes": "any additional notes"
                }
            ]
        }

        VALIDATION RULES:
        - status "failed": Cannot extract clear times or dates from the image
        - status "partial": Can extract times and dates, but some event titles are unclear or hard to read
        - status "success": All events extracted with clear, readable information

        Example response for reference (including multiple events at same time):
        {
            "status": "success",
            "errorMessage": null,
            "extractionConfidence": 0.95,
            "events": [
                {
                    "title": "Team Meeting",
                    "startTime": "09:00",
                    "startDate": "\(todayString)",
                    "endTime": "10:00",
                    "endDate": "\(todayString)",
                    "attendees": ["Sarah", "Mike"],
                    "titleConfidence": true,
                    "timeConfidence": true,
                    "dateConfidence": true,
                    "confidence": 0.98,
                    "notes": ""
                },
                {
                    "title": "Project Review",
                    "startTime": "09:00",
                    "startDate": "\(todayString)",
                    "endTime": "09:30",
                    "endDate": "\(todayString)",
                    "attendees": ["John"],
                    "titleConfidence": true,
                    "timeConfidence": true,
                    "dateConfidence": true,
                    "confidence": 0.92,
                    "notes": "30-minute meeting, side-by-side with Team Meeting"
                },
                {
                    "title": "Lunch Break",
                    "startTime": "12:00",
                    "startDate": "\(todayString)",
                    "endTime": "13:00",
                    "endDate": "\(todayString)",
                    "attendees": [],
                    "titleConfidence": true,
                    "timeConfidence": true,
                    "dateConfidence": true,
                    "confidence": 0.98,
                    "notes": ""
                }
            ]
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 2000,
            "temperature": 0.1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ExtractionError.networkError(error)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtractionError.networkError(NSError(domain: "InvalidResponse", code: -1))
        }

        // Handle API errors
        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw ExtractionError.apiError(errorBody.error.message)
            }
            throw ExtractionError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let decodedResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
              let content = decodedResponse.choices.first?.message.content else {
            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 API Response: \(responseString)")
            }
            throw ExtractionError.decodingError
        }

        print("🔍 GPT-4o extracted: \(content)")

        // Parse the JSON response from GPT-4o
        return try parseExtractionResponse(content)
    }

    // MARK: - Private Methods

    private func parseExtractionResponse(_ jsonString: String) throws -> CalendarPhotoExtractionResponse {
        // Strip markdown code fence formatting if present
        var cleanedJson = jsonString

        // Remove leading ```json or ```
        if cleanedJson.starts(with: "```json") {
            cleanedJson = String(cleanedJson.dropFirst(7)) // Remove "```json"
        } else if cleanedJson.starts(with: "```") {
            cleanedJson = String(cleanedJson.dropFirst(3)) // Remove "```"
        }

        // Remove trailing ```
        if cleanedJson.hasSuffix("```") {
            cleanedJson = String(cleanedJson.dropLast(3)) // Remove trailing "```"
        }

        // Trim whitespace
        cleanedJson = cleanedJson.trimmingCharacters(in: .whitespacesAndNewlines)

        print("🔍 Cleaned JSON: \(cleanedJson.prefix(100))...") // Log first 100 chars

        guard let jsonData = cleanedJson.data(using: .utf8) else {
            throw ExtractionError.decodingError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try parsing as date string or return a default date
            return Date()
        }

        do {
            let parsedResponse = try decoder.decode(RawExtractionResponse.self, from: jsonData)

            print("🔍 Parsed status: \(parsedResponse.status), event count: \(parsedResponse.events.count)")

            // Convert raw dates and times to Date objects
            let extractedEvents = try parsedResponse.events.map { rawEvent -> ExtractedEvent in
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"

                // Parse start date and time
                let startDateString = rawEvent.startDate
                let startTimeString = rawEvent.startTime

                guard let startDate = dateFormatter.date(from: startDateString),
                      let startTime = timeFormatter.date(from: startTimeString) else {
                    throw ExtractionError.decodingError
                }

                // Combine date and time into a single Date object
                var calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
                let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)

                var combinedComponents = dateComponents
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute

                guard let startDateTime = calendar.date(from: combinedComponents) else {
                    throw ExtractionError.decodingError
                }

                // Parse end time if available
                var endDateTime: Date? = nil
                if let endTimeString = rawEvent.endTime, !endTimeString.isEmpty {
                    if let endTime = timeFormatter.date(from: endTimeString) {
                        var endDateString = rawEvent.endDate ?? rawEvent.startDate
                        if let endDate = dateFormatter.date(from: endDateString) {
                            let endDateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
                            let endTimeComponents = calendar.dateComponents([.hour, .minute], from: endTime)

                            var endCombinedComponents = endDateComponents
                            endCombinedComponents.hour = endTimeComponents.hour
                            endCombinedComponents.minute = endTimeComponents.minute

                            endDateTime = calendar.date(from: endCombinedComponents)
                        }
                    }
                } else if endDateTime == nil {
                    // FALLBACK: If no end time provided, infer a reasonable default duration
                    // Check if the title suggests a specific duration pattern
                    let titleLower = rawEvent.title.lowercased()

                    let inferredDuration: Int
                    if titleLower.contains("standup") || titleLower.contains("stand up") || titleLower.contains("daily") {
                        inferredDuration = 15  // Stand-ups are typically 15 min
                    } else if titleLower.contains("sync") || titleLower.contains("1:1") {
                        inferredDuration = 30  // 1:1 syncs are typically 30 min
                    } else if titleLower.contains("lunch") || titleLower.contains("break") {
                        inferredDuration = 60  // Lunch/break blocks are typically 1 hour
                    } else if titleLower.contains("meeting") || titleLower.contains("call") {
                        inferredDuration = 60  // Meetings/calls typically 1 hour
                    } else if titleLower.contains("workshop") || titleLower.contains("training") {
                        inferredDuration = 120  // Workshops/training typically 2+ hours
                    } else {
                        inferredDuration = 60  // Default to 1 hour
                    }

                    if let inferredEndDateTime = calendar.date(byAdding: .minute, value: inferredDuration, to: startDateTime) {
                        endDateTime = inferredEndDateTime
                        print("ℹ️ Inferred endTime for '\(rawEvent.title)': +\(inferredDuration) min (no explicit end time provided)")
                    }
                }

                return ExtractedEvent(
                    title: rawEvent.title,
                    startTime: startDateTime,
                    endTime: endDateTime,
                    attendees: rawEvent.attendees ?? [],
                    confidence: rawEvent.confidence,
                    titleConfidence: rawEvent.titleConfidence,
                    timeConfidence: rawEvent.timeConfidence,
                    dateConfidence: rawEvent.dateConfidence,
                    notes: rawEvent.notes ?? "",
                    isSelected: true
                )
            }

            return CalendarPhotoExtractionResponse(
                status: parsedResponse.status,
                events: extractedEvents,
                errorMessage: parsedResponse.errorMessage,
                confidence: parsedResponse.extractionConfidence
            )
        } catch {
            print("❌ Extraction error: \(error)")
            if let decodingError = error as? DecodingError {
                print("❌ Decoding error details: \(decodingError)")
            }
            throw ExtractionError.decodingError
        }
    }

    private func enforceRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minimumRequestInterval {
            let delayNeeded = minimumRequestInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delayNeeded * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}

// MARK: - API Response Models

// Note: OpenAIResponse, OpenAIChoice, and OpenAIMessage are defined in OpenAIService.swift
// We'll use those shared structs

struct OpenAIErrorResponse: Codable {
    let error: ErrorInfo

    struct ErrorInfo: Codable {
        let message: String
    }
}

struct RawExtractionResponse: Codable {
    let status: ExtractionValidationStatus
    let errorMessage: String?
    let extractionConfidence: Double
    let events: [RawExtractedEvent]

    enum CodingKeys: String, CodingKey {
        case status
        case errorMessage
        case extractionConfidence
        case events
    }
}

struct RawExtractedEvent: Codable {
    let title: String
    let startTime: String          // HH:MM format
    let startDate: String          // YYYY-MM-DD format
    let endTime: String?           // HH:MM format or null
    let endDate: String?           // YYYY-MM-DD format or null
    let attendees: [String]?
    let titleConfidence: Bool
    let timeConfidence: Bool
    let dateConfidence: Bool
    let confidence: Double
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startTime
        case startDate
        case endTime
        case endDate
        case attendees
        case titleConfidence
        case timeConfidence
        case dateConfidence
        case confidence
        case notes
    }
}
