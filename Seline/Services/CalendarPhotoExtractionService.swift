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
        You are a SPECIALIZED calendar OCR analyzer. Your ONLY job is to:
        1. Measure event block HEIGHTS visually
        2. Compare blocks to determine which are 30-min vs 1-hour vs longer
        3. Extract precise start and end times

        ⚠️ BLOCK HEIGHT IS THE AUTHORITATIVE SOURCE FOR DURATION ⚠️

        You MUST:
        - Look at EVERY event block and MEASURE its height
        - Compare blocks to each other - shorter blocks = shorter events
        - If Block A is HALF the height of Block B, then Block A is 30 min and Block B is 1 hour
        - If Block A is clearly shorter but NOT half = probably 45 min
        - If blocks are roughly equal height = same duration
        - NEVER assume all events are 1 hour
        - MEASURE FIRST, then assign times

        ⚠️ HOW TO MEASURE BLOCK HEIGHT:
        - Find the hourly grid lines or time markers in the calendar
        - Count how many hour-slots each event occupies
        - A block spanning 0.5 slots = 30 min
        - A block spanning 1 slot = 60 min
        - A block spanning 1.5 slots = 90 min (1.5 hours)
        - A block spanning 2 slots = 120 min (2 hours)

        ⚠️ DURATION DETECTION LOGIC (MANDATORY):
        For EACH event:
        1. Measure block height (compare to hourly grid)
        2. If block is HALF a typical hour-block = 30 minutes
        3. If block is 3/4 of typical hour-block = 45 minutes
        4. If block is FULL hour-block = 60 minutes
        5. Calculate endTime = startTime + measured_duration

        CRITICAL: The visible block size DETERMINES the duration. Do not guess.

        OVERLAPPING EVENTS:
        - If 2+ events start at same time, extract EACH as separate event
        - Measure EACH block's height independently
        - Do NOT merge adjacent blocks

        CONFIDENCE:
        - timeConfidence = true ONLY if block height clearly shows duration
        - If block height is ambiguous, set timeConfidence = false
        - If block height is clear, set timeConfidence = true

        NEVER output a null/empty endTime if you can see a block.
        """

        let userPrompt = """
        TASK: EXTRACT ALL calendar events with PRECISE duration measurement.

        STEP 1: IDENTIFY ALL EVENT BLOCKS
        - Count every visible event block in the calendar
        - Do NOT skip any blocks, even if partially visible
        - If multiple blocks exist at same start time, extract each separately

        STEP 2: FOR EACH EVENT BLOCK, MEASURE HEIGHT
        First, identify the hourly grid:
        - Find time markers (hourly lines, labels like "9:00", "10:00", etc.)
        - Establish the standard height of 1 hour in pixels/units
        - Measure each event block against this standard

        Then measure duration:
        - Block height = ? × (1-hour height)
        - If block = 0.5 × (1-hour height) → duration = 30 minutes
        - If block = 0.75 × (1-hour height) → duration = 45 minutes
        - If block = 1.0 × (1-hour height) → duration = 60 minutes
        - If block = 1.5 × (1-hour height) → duration = 90 minutes
        - If block = 2.0 × (1-hour height) → duration = 120 minutes

        STEP 3: FOR EACH EVENT, DETERMINE START AND END TIME
        - Read the start time (use time labels on calendar or position)
        - Add the measured duration to get end time
        - Example: start=09:00, duration=30min → end=09:30
        - Example: start=09:00, duration=60min → end=10:00

        STEP 4: EXTRACT STRUCTURED DATA
        For each event block:
        - title: The event name (read exactly as shown)
        - startTime: HH:MM in 24-hour format
        - startDate: YYYY-MM-DD
        - endTime: HH:MM calculated from (startTime + measured_duration)
        - endDate: Same as startDate unless event crosses midnight
        - attendees: Any visible names
        - confidence: How certain you are (0.0-1.0)
        - timeConfidence: true if block height clearly indicates duration

        ⚠️ CRITICAL CONSTRAINTS:
        - NEVER use null/empty for endTime if you can see a block
        - NEVER assume all events are 60 minutes
        - NEVER set endTime = startTime (duration must be > 0)
        - MEASURE block height first, calculate duration second, derive endTime third
        - If two events have different block heights, they have different durations

        DATES: If the image doesn't show dates, use today's date (\(todayString)) and increment for subsequent days shown.

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
                var durationFromExtraction: Int? = nil

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

                            // Calculate extracted duration for logging
                            if let endDT = endDateTime {
                                let durationMinutes = Int(endDT.timeIntervalSince(startDateTime) / 60)
                                durationFromExtraction = durationMinutes
                                print("📊 Extracted: '\(rawEvent.title)' → \(startTimeString)-\(endTimeString) (\(durationMinutes) min)")
                            }
                        }
                    }
                }

                // FALLBACK: If no end time, or extracted duration looks suspicious, infer better
                if endDateTime == nil {
                    let titleLower = rawEvent.title.lowercased()

                    let inferredDuration: Int
                    if titleLower.contains("standup") || titleLower.contains("stand up") || titleLower.contains("daily") {
                        inferredDuration = 15
                    } else if titleLower.contains("sync") || titleLower.contains("1:1") {
                        inferredDuration = 30
                    } else if titleLower.contains("lunch") || titleLower.contains("break") {
                        inferredDuration = 60
                    } else if titleLower.contains("meeting") || titleLower.contains("call") {
                        inferredDuration = 60
                    } else if titleLower.contains("workshop") || titleLower.contains("training") {
                        inferredDuration = 120
                    } else {
                        inferredDuration = 60
                    }

                    if let inferredEndDateTime = calendar.date(byAdding: .minute, value: inferredDuration, to: startDateTime) {
                        endDateTime = inferredEndDateTime
                        print("⚠️ No endTime from API, inferring: '\(rawEvent.title)' → +\(inferredDuration) min")
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
