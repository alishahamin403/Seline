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

        print("📸 Processing image - Size: \(image.size), Scale: \(image.scale)")

        // Convert image to base64 with adaptive quality based on image size
        // For large images (from gallery), use lower compression to avoid memory issues
        var base64Image: String

        // Determine compression quality based on image size
        let imagePixels = image.size.width * image.size.height * image.scale * image.scale
        let compressionQuality: CGFloat = imagePixels > 1_000_000 ? 0.7 : 0.95

        print("📸 Image pixels: \(Int(imagePixels)), Compression quality: \(compressionQuality)")

        // Try JPEG first with adaptive quality, then PNG if JPEG fails
        if let jpegData = image.jpegData(compressionQuality: compressionQuality) {
            base64Image = jpegData.base64EncodedString()
            print("📸 JPEG size: \(String(format: "%.2f", Double(jpegData.count) / 1024 / 1024))MB")
        } else if let pngData = image.pngData() {
            base64Image = pngData.base64EncodedString()
            print("📸 PNG size: \(String(format: "%.2f", Double(pngData.count) / 1024 / 1024))MB")
        } else {
            throw ExtractionError.imageConversionError
        }

        // Validate base64 size isn't too large for API (max reasonable size)
        if base64Image.count > 20_000_000 { // 20MB base64 is ~15MB binary
            print("🔴 Image too large after encoding: \(String(format: "%.2f", Double(base64Image.count) / 1024 / 1024))MB")
            throw ExtractionError.apiError("Image is too large. Please select a smaller image.")
        }

        // Get today's date for fallback in the prompt
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        let systemPrompt = """
        You are a SPECIALIZED calendar analyzer for extracting event times from photos.

        ⚠️ YOUR PRIMARY TASK: Compare blocks by HEIGHT to determine duration ⚠️

        STEP 1: BLOCK COMPARISON (Do this FIRST)
        1. Look at EVERY event block in the image
        2. Identify which blocks are the SAME height (same duration)
        3. Identify which blocks are SHORTER (shorter duration)
        4. Identify which blocks are TALLER (longer duration)
        5. Measure relative heights: if Block A is half as tall as Block B, Block A is 30 min and Block B is 60 min

        STEP 2: LOOK FOR TIME LABELS
        1. Search for visible time text/numbers (9:00, 09:30, 2:15 PM, etc.)
        2. Look at TOP of blocks (usually start time)
        3. Look at BOTTOM of blocks (usually end time)
        4. Look for time ranges like "9-10", "9:00-9:30", "10:00 AM - 10:30 AM"
        5. Extract exactly as shown

        STEP 3: COMBINE OBSERVATIONS
        - If you see time labels → use those to get precise start/end times
        - If you see block heights → infer duration from relative heights
        - If you see both → use time labels and verify with block heights

        TIME LABEL PARSING:
        - "9:30" or "930" or "09:30" → parse as HH:MM
        - "9:30 AM" → convert to 24-hour (09:30)
        - "2:15 PM" → convert to 24-hour (14:15)
        - "9-10" = "9:00-10:00" (60 minutes)
        - "9-9:30" = "09:00-09:30" (30 minutes)

        DURATION RULES (use these if no explicit times visible):
        - If block is HALF height of another → 30 minutes
        - If block is 3/4 height of another → 45 minutes
        - If block is SAME height as another → same duration
        - If block is DOUBLE height → 120 minutes
        - Shortest visible block is typically 15-30 min
        - Standard meeting block is typically 60 min

        OUTPUT REQUIREMENTS:
        - ALWAYS provide both startTime and endTime (NEVER null)
        - timeConfidence = true ONLY if times are from visible text/labels
        - timeConfidence = false if duration inferred from block comparison
        - If inferring: pick realistic duration (30, 45, 60, 90, 120 minutes)
        - Extract EVERY block visible in the image
        """

        let userPrompt = """
        TASK: Extract ALL calendar events with ACCURATE durations.

        ⚠️ ANALYSIS SEQUENCE - FOLLOW IN ORDER:

        STEP 1: ANALYZE BLOCK HEIGHTS (PRIMARY)
        For every visible event block:
        1. Compare it to other blocks - is it SHORTER, SAME, or TALLER?
        2. If you see a very short block (half height of a normal block) → 30 minutes
        3. If you see a medium block (3/4 height) → 45 minutes
        4. If you see a standard block (full hour-height) → 60 minutes
        5. If you see a tall block (double height) → 120+ minutes
        6. Document these observations FIRST before assigning times

        STEP 2: SEARCH FOR TIME LABELS (SECONDARY)
        Scan the entire image for visible time text:
        - Time at TOP of block (usually start time)
        - Time at BOTTOM of block (usually end time)
        - Time INSIDE block near title
        - Time LABELS on calendar grid/axis (9:00, 10:00, etc.)
        - Time RANGES written out ("9-10", "9:00-9:30", "10 AM - 10:30 AM")

        STEP 3: EXTRACT START AND END TIMES
        For EACH event block:
        1. Find the block's start position on the calendar (use grid labels or position)
        2. Determine duration from: (visible time label) OR (block height comparison)
        3. Calculate: endTime = startTime + duration

        Example: If block at 9:00 position is half-height of 1-hour block:
        - startTime: 09:00
        - duration: 30 minutes (from half-height observation)
        - endTime: 09:30

        STEP 4: EXTRACT STRUCTURED DATA
        For each event:
        - title: Exact text of event name
        - startTime: HH:MM (24-hour format) from time label or position
        - endTime: HH:MM calculated from startTime + duration
        - startDate/endDate: YYYY-MM-DD from calendar
        - attendees: Any visible names
        - timeConfidence: true if explicit time labels visible, false if inferred from blocks
        - confidence: How sure you are (0.0-1.0)

        CRITICAL RULES:
        ⚠️ DO NOT default everything to 60 minutes
        ⚠️ If blocks have different heights → they have different durations
        ⚠️ If you see a short block, call it 30-45 min, NOT 60 min
        ⚠️ ALWAYS provide endTime (never null)
        ⚠️ Use visible times when available, block heights as backup

        DATES: If image doesn't show dates, use today's date (\(todayString)).

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

        // Validate API key before making request
        if apiKey.isEmpty || apiKey.contains("YOUR_") || apiKey == "sk-" {
            throw ExtractionError.apiError("Invalid OpenAI API key. Please check Config.swift")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Increase timeout for larger images - base64 encoding and upload can take time
        let timeoutInterval: TimeInterval = base64Image.count > 10_000_000 ? 60 : 45
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        print("📡 Sending request to OpenAI API...")
        print("📡 URL: \(baseURL)")
        print("📡 Image size: \(String(format: "%.2f", Double(base64Image.count) / 1024))KB")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw ExtractionError.networkError(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            print("📡 Request timeout interval: \(request.timeoutInterval)s")
            print("📡 Base64 image size: \(base64Image.count / 1024)KB")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            print("🔴 URLError: \(error.localizedDescription)")
            print("🔴 Error code: \(error.code.rawValue)")

            // Provide helpful error messages for common network issues
            switch error.code {
            case .notConnectedToInternet:
                throw ExtractionError.apiError("No internet connection. Check WiFi/cellular.")
            case .timedOut:
                let sizeWarning = base64Image.count > 10_000_000 ? " Your image may be too large - try a smaller one." : ""
                throw ExtractionError.apiError("Request timed out. Check your connection speed.\(sizeWarning)")
            case .networkConnectionLost:
                throw ExtractionError.apiError("Network connection lost. Try again.")
            case .dnsLookupFailed:
                throw ExtractionError.apiError("Cannot reach OpenAI servers. Check your DNS.")
            case .badServerResponse:
                throw ExtractionError.apiError("Server returned an invalid response. Try again.")
            case .cannotConnectToHost:
                throw ExtractionError.apiError("Cannot connect to OpenAI servers. Check your internet and DNS.")
            default:
                throw ExtractionError.networkError(error)
            }
        } catch {
            print("🔴 Network error: \(error.localizedDescription)")
            throw ExtractionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtractionError.networkError(NSError(domain: "InvalidResponse", code: -1))
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        // Handle API errors
        if httpResponse.statusCode != 200 {
            print("🔴 HTTP Error \(httpResponse.statusCode)")
            print("🔴 Response: \(String(data: data, encoding: .utf8) ?? "No data")")

            if let errorBody = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                print("🔴 API Error: \(errorBody.error.message)")
                throw ExtractionError.apiError(errorBody.error.message)
            }

            let statusDescription = {
                switch httpResponse.statusCode {
                case 400: return "Bad Request - Invalid image or parameters"
                case 401: return "Unauthorized - Invalid API key"
                case 429: return "Rate limited - Too many requests"
                case 500...599: return "Server error - OpenAI servers have issues"
                default: return "HTTP \(httpResponse.statusCode)"
                }
            }()

            throw ExtractionError.apiError(statusDescription)
        }

        print("✅ API request successful")

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
            let _ = try container.decode(String.self)
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
                let calendar = Calendar.current
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
                        let endDateString = rawEvent.endDate ?? rawEvent.startDate
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
