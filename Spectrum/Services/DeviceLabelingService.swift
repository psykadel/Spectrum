import Foundation

protocol DeviceLabelingService {
    func generateLabel(
        for macAddress: String,
        model: String,
        apiKey: String,
        maxOutputTokens: Int
    ) async throws -> String
}

enum DeviceLabelingServiceError: LocalizedError, Equatable {
    case missingConfiguration
    case requestFailed(String)
    case invalidResponse(String?)
    case invalidLabel(String?)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Add your OpenAI API key and model in Settings first."
        case let .requestFailed(message):
            return message
        case .invalidResponse:
            return "OpenAI returned an unreadable response."
        case .invalidLabel:
            return "OpenAI did not return a short device label."
        }
    }

    var debugDetails: String? {
        switch self {
        case .invalidResponse(let details), .invalidLabel(let details):
            return details?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .missingConfiguration, .requestFailed:
            return nil
        }
    }
}

struct OpenAIResponsesDeviceLabelingService: DeviceLabelingService {
    static let promptTemplate = """
    You are a MAC address identification formatter.

    The user will provide exactly one MAC address. Think silently and do not show your reasoning.

    Your job is to return only a very short Title Case device label in a single copy-pasteable text fence. The label must be 30 characters or fewer.

    Rules:
    - If the MAC is locally administered, randomized, private, not globally vendor-identifiable, or you cannot determine a reliable device identity, return: Private Device
    - Otherwise, identify the most likely device category from the MAC/vendor information and return a short, clean Title Case label
    - Prefer practical labels like Eero Mesh Node, Netgear Router, Apple iPhone, Roku Streamer, Security Camera, Dell Laptop
    - When the vendor is strongly associated with a common device family, prefer the plain category over an obscure vendor label, for example Security Camera instead of a niche OEM name
    - Prefer common end-user device categories like Security Camera, Doorbell Camera, Robot Vacuum, Smart Plug, Printer, Router, Laptop, TV, or Phone when the evidence supports them
    - If you know only the vendor but not the exact category, return a safe generic label like Vendor Device
    - Do not use model numbers unless you are highly confident
    - Do not include explanations, confidence, vendor details, punctuation, or extra words
    - Do not output anything except the single fenced label

    Output format exactly:
    ```text
    Device Label
    ```
    """

    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func generateLabel(
        for macAddress: String,
        model: String,
        apiKey: String,
        maxOutputTokens: Int
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty, !trimmedAPIKey.isEmpty, maxOutputTokens > 0 else {
            throw DeviceLabelingServiceError.missingConfiguration
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: trimmedModel,
                instructions: Self.promptTemplate,
                input: macAddress,
                maxOutputTokens: maxOutputTokens,
                reasoning: .init(effort: "medium"),
                tools: [.init(type: "web_search")]
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceLabelingServiceError.invalidResponse(Self.debugString(from: data))
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(ResponsesErrorEnvelope.self, from: data)
            let message = apiError?.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DeviceLabelingServiceError.requestFailed(
                message?.isEmpty == false ? message! : "OpenAI request failed."
            )
        }

        let payload: ResponsesResponse
        do {
            payload = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        } catch {
            throw DeviceLabelingServiceError.invalidResponse(Self.debugString(from: data))
        }

        let rawText = payload.outputText ?? payload.firstTextBlock
        guard let rawText else {
            throw DeviceLabelingServiceError.invalidResponse(Self.debugString(from: data))
        }

        return try Self.parseLabel(from: rawText)
    }

    static func parseLabel(from rawText: String) throws -> String {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = extractFencedBody(from: cleaned) ?? cleaned
        let normalized = candidate
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty, normalized.count <= 30 else {
            throw DeviceLabelingServiceError.invalidLabel(cleaned)
        }

        return normalized
    }

    private static func extractFencedBody(from text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        var body = String(text.dropFirst(3))

        if let firstNewline = body.firstIndex(of: "\n") {
            let header = body[..<firstNewline]
            if !header.isEmpty {
                body = String(body[body.index(after: firstNewline)...])
            }
        }

        if let closingRange = body.range(of: "```") {
            body = String(body[..<closingRange.lowerBound])
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func debugString(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct ResponsesRequest: Encodable {
    struct Reasoning: Encodable {
        let effort: String
    }

    struct Tool: Encodable {
        let type: String
    }

    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let reasoning: Reasoning
    let tools: [Tool]

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case reasoning
        case tools
    }
}

private struct ResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String?
            let text: String?
        }

        let content: [ContentItem]?
    }

    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var firstTextBlock: String? {
        output?
            .flatMap { $0.content ?? [] }
            .first(where: { item in
                guard let type = item.type else { return false }
                return type == "output_text" || type == "text"
            })?
            .text
    }
}

private struct ResponsesErrorEnvelope: Decodable {
    struct ResponseError: Decodable {
        let message: String
    }

    let error: ResponseError
}
