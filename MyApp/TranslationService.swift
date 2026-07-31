/// TranslationService.swift — Translates announcement texts via the Anthropic Claude API.
///
/// Uses the claude-haiku model for low latency. Each call is independent; the caller
/// is responsible for batching (ExecutionViewModel.preTranslate runs them in parallel).
///
/// Ref: https://docs.anthropic.com/en/api/messages

import Foundation

// MARK: - TranslationService

/// Stateless service for translating a single text string using the Claude API.
struct TranslationService {

    // MARK: - Constants

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model    = "claude-haiku-4-5-20251001"

    // MARK: - Codable request / response

    private struct RequestBody: Encodable {
        let model:      String
        let max_tokens: Int
        let messages:   [RequestMessage]
    }

    private struct RequestMessage: Encodable {
        let role:    String
        let content: String
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    // MARK: - API call

    /// Translates `text` from `sourceLang` to `targetLang`.
    ///
    /// The model is prompted to return only the translated text, keeping it natural for
    /// speech synthesis (short, no explanations, no surrounding punctuation artifacts).
    ///
    /// - Parameters:
    ///   - text:       Announcement text to translate (the `message` field of a `ProgramEvent`).
    ///   - sourceLang: BCP-47 code of the source text (e.g. "es-ES").
    ///   - targetLang: BCP-47 code of the desired output (e.g. "ca-ES").
    ///   - apiKey:     Anthropic API key stored in `AppSettings.claudeApiKey`.
    /// - Returns: Trimmed translated string.
    /// - Throws: `URLError` on network failure; `TranslationError` on invalid response.
    static func translate(_ text:       String,
                          from sourceLang: String,
                          to   targetLang: String,
                          apiKey: String) async throws -> String {

        let prompt = """
        Translate the following short announcement text from \(sourceLang) to \(targetLang). \
        Keep it concise and natural for speech synthesis. \
        Return only the translated text, nothing else.

        \(text)
        """

        let body = RequestBody(
            model:      model,
            max_tokens: 256,
            messages:   [RequestMessage(role: "user", content: prompt)]
        )

        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(apiKey,          forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",    forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Fail fast on HTTP errors so the caller falls back to the original text.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(statusCode: http.statusCode)
        }

        let parsed = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let translated = parsed.content.first(where: { $0.type == "text" })?.text else {
            throw TranslationError.emptyResponse
        }

        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - TranslationError

enum TranslationError: LocalizedError {
    case emptyResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:             return "Empty translation response."
        case .httpError(let code):       return "Translation API error (HTTP \(code))."
        }
    }
}
