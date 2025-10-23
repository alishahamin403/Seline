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
        You are a SPECIALIZED calendar OCR analyzer. Your ONLY job is TEXT EXTRACTION:

        ⚠️ VISIBLE TIME TEXT IS THE AUTHORITATIVE SOURCE ⚠️

        You MUST look for and extract VISIBLE TIME LABELS/TEXT:
        1. Time ranges written in/on event blocks (e.g., "9:00-9:30", "9am-10am")
        2. Start time labels (at top of block or beside event name)
        3. End time labels (at bottom of block or after event name)
        4. Time markers within the calendar grid or on event blocks
        5. Any visible numbers/text showing hours and minutes

        PRIORITIZE EXTRACTION IN THIS ORDER:
        1. Look for explicit time ranges: "9:00-9:30", "9:00 AM - 9:30 AM", "9-9:30"
        2. Look for start time + end time separately shown: "START 9:00" "END 9:30"
        3. Look for time on top of block (start) and bottom of block (end)
        4. Look for time labels within the event block itself
        5. Look for time indicators on the calendar grid/axis

        TEXT EXTRACTION RULES:
        - READ EVERY PIXEL OF TEXT visible in the image
        - Do NOT skip time text even if small or faint
        - Extract times exactly as written (preserve format)
        - If you see "930" interpret as 9:30
        - If you see "9.30" interpret as 9:30
        - If you see "0930" interpret as 09:30 (24-hour)
        - If you see "9-10" with AM/PM context = 9:00-10:00

        CONVERT EXTRACTED TEXT TO STANDARD FORMAT:
        - Parse extracted text into HH:MM format (24-hour)
        - If 12-hour format with AM/PM shown = convert to 24-hour
        - "9:30 AM" → "09:30"
        - "2:15 PM" → "14:15"
        - "9-10" with AM shown → "09:00-10:00"
        - "9-10" with PM shown → "21:00-22:00"

        HANDLE AMBIGUOUS CASES:
        - If time range shows "9-10", that's 9:00-10:00 (60 minutes)
        - If time shows "9:30", that's just the start or end (need to find the other)
        - If time shows "9" and "9:30" = 9:00-9:30 (30 minutes)
        - Always try to find BOTH start and end times from visible text

        QUALITY ASSESSMENT:
        - timeConfidence = true if BOTH start and end times are clearly visible as text
        - timeConfidence = false if you had to infer one from context
        - NEVER set endTime to null if visible time text exists

        CRITICAL CONSTRAINTS:
        - Do NOT guess or assume durations
        - Only use visible, readable time text
        - If time text is ambiguous, set timeConfidence = false but still extract
        - Extract EVERY visible event and time label, no exceptions
        """

        let userPrompt = """
        TASK: EXTRACT ALL calendar events by OCR'ing visible time text/labels.

        STEP 1: SCAN FOR ALL VISIBLE TIME TEXT
        Look at the entire image and find EVERY piece of visible text that contains:
        - Time ranges (e.g., "9:00-9:30", "9-10", "9 AM - 9:30 AM")
        - Individual times (e.g., "9:00", "09:30", "9am")
        - Time labels on/near event blocks
        - Hour/minute numbers anywhere in the calendar

        STEP 2: EXTRACT TIME RANGES FROM VISIBLE TEXT
        For each visible time text/label:
        - If it shows a range ("9:00-9:30") → startTime=09:00, endTime=09:30
        - If it shows start and end separately → combine them
        - If it's ambiguous format ("9-10") → interpret as 9:00-10:00
        - Parse into HH:MM 24-hour format

        STEP 3: MATCH TIMES TO EVENTS
        For each event block:
        1. Look for time text INSIDE the event block
        2. Look for time text at the TOP of the event block (start time)
        3. Look for time text at the BOTTOM of the event block (end time)
        4. Look for time text immediately BEFORE the event name (start)
        5. Look for time text immediately AFTER the event name (end)
        6. Read the event title from the block

        STEP 4: BUILD EXTRACTED DATA
        For each event with visible time text:
        - title: Event name (read exactly)
        - startTime: HH:MM from visible text
        - endTime: HH:MM from visible text
        - startDate: YYYY-MM-DD (from calendar context)
        - endDate: YYYY-MM-DD (same as start unless crosses midnight)
        - attendees: Any visible names
        - timeConfidence: true if BOTH times are clearly visible as text
        - confidence: 0.0-1.0 based on text clarity

        SPECIAL CASES:
        - If event shows "9:00" but no end time visible → look harder for end time text
        - If event shows "9" and "30" separately → combine as "9:00" and "9:30"
        - If event shows only start time in text → set timeConfidence = false but extract
        - If time format is "930" → interpret as "09:30"
        - If time format is "9.30" → interpret as "09:30"

        ⚠️ CRITICAL REQUIREMENTS:
        - EXTRACT EVERY visible time label, no exceptions
        - Do NOT infer times - only use VISIBLE text
        - Do NOT assume 60-minute durations
        - Extract exact times shown in the image
        - timeConfidence = true ONLY if both start and end times are readable

        DATES: If not shown, use today's date (\(todayString)).

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
