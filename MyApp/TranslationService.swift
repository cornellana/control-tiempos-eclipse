/// TranslationService.swift — Translates announcement texts with a cloud language model.
///
/// Two interchangeable back ends, chosen in Settings:
///
///   • `.claude` — Anthropic Messages API, claude-haiku for low latency. Paid from the
///     first call.
///   • `.gemini` — Google's Gemini API through an AI Studio key, which has a free tier.
///
/// Both receive the *same* prompt, and that prompt is the reason a language model is used
/// here rather than a translation engine. Told only to translate "bracketing de 3, F8,
/// 1/500, ISO", a plain translator reads *bracket* as a sandwich — this was measured, not
/// imagined. Told that the text is a spoken cue to a photographer during a solar eclipse, a
/// language model leaves the jargon alone.
///
/// Each call is independent; the caller batches them (ExecutionViewModel.preTranslate runs
/// them in parallel).
///
/// Refs:
///   • https://docs.anthropic.com/en/api/messages
///   • https://ai.google.dev/api/generate-content

import Foundation

// MARK: - TranslationEngine

/// Which cloud model translates the cues.
enum TranslationEngine: String, CaseIterable, Identifiable {

    /// Google's Gemini API through an AI Studio key. The default, and listed first.
    ///
    /// Default because it is the one a new user can actually reach: the free tier needs no
    /// card. Google's own pricing page does mark free-tier content as used to improve their
    /// products, and paid tiers as not — announcement cues are harmless, but it is the user's
    /// call to make, so Settings says so plainly rather than choosing quietly for them.
    case gemini

    /// Anthropic's Messages API. Paid from the first call.
    case claude

    var id: String { rawValue }

    /// Page that issues this engine's key, opened from Settings.
    var keyPageURL: URL {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }

    /// Name shown in the engine picker.
    var displayName: String {
        switch self {
        case .gemini: return "Gemini API (Google AI Studio)"
        case .claude: return "Claude API"
        }
    }
}

// MARK: - TranslationService

/// Stateless service for translating a single text string.
struct TranslationService {

    // MARK: - Constants

    private static let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let claudeModel    = "claude-haiku-4-5-20251001"

    /// `gemini-3.5-flash-lite` and not the flagship `gemini-3.6-flash`, for two measured
    /// reasons rather than cost:
    ///
    ///   • **It does not think.** Gemini 3.6 spends 312 to 1087 reasoning tokens on a single
    ///     line, and those count against `maxOutputTokens`: at 512 it burned 491 thinking,
    ///     had 17 left, and cut the answer off right before the camera settings. Flash-Lite
    ///     returned the same batch with zero reasoning tokens.
    ///   • **Its free daily quota is not 20.** 3.6-flash allows twenty requests a day per
    ///     project on the free tier — not enough to rehearse with.
    ///
    /// Quality is not the trade-off it sounds like: on the real Raimat programme it returned
    /// «bracketing de 3, F8, 1/500, ISO 100» and «Perles de Baily» untouched.
    private static let geminiEndpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"
    )!

    private static let claudeMaxTokens = 4096
    private static let geminiMaxTokens = 8192

    // MARK: - Codable request / response

    private struct ClaudeRequest: Encodable {
        let model:      String
        let max_tokens: Int
        let messages:   [ClaudeMessage]
    }

    private struct ClaudeMessage: Encodable {
        let role:    String
        let content: String
    }

    private struct ClaudeResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    private struct GeminiRequest: Encodable {
        let contents: [Content]
        let generationConfig: GenerationConfig

        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct GenerationConfig: Encodable {
            let maxOutputTokens: Int
        }
    }

    private struct GeminiResponse: Decodable {
        let candidates: [Candidate]?

        struct Candidate: Decodable {
            let content: Content?
            let finishReason: String?

            struct Content: Decodable {
                let parts: [Part]?

                struct Part: Decodable {
                    let text: String?
                }
            }
        }
    }

    // MARK: - API call

    /// Translates `texts` from `sourceLang` to `targetLang` in a **single** request.
    ///
    /// One request for the whole programme, not one per cue. Translating every cue in
    /// parallel worked fine against a paid account and then failed completely on Gemini's
    /// free tier: 50 announcements fired 50 simultaneous calls and half came back `429 You
    /// exceeded your current quota`. The free daily allowance is counted in requests, so the
    /// batch turns a whole rehearsal into one of them.
    ///
    /// - Returns: An array the same size as `texts`, holding each translation, or nil for any
    ///   line the model did not return. Callers use the original text for those.
    /// - Throws: `URLError` on network failure; `TranslationError` on a blank key or an
    ///   invalid response.
    static func translate(_ texts:       [String],
                          from sourceLang: String,
                          to   targetLang: String,
                          engine:          TranslationEngine,
                          apiKey:          String) async throws -> [String?] {

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.missingKey }
        guard !texts.isEmpty else { return [] }

        let prompt = prompt(for: texts, from: sourceLang, to: targetLang)

        let reply: String
        switch engine {
        case .gemini: reply = try await translateWithGemini(prompt, apiKey: key)
        case .claude: reply = try await translateWithClaude(prompt, apiKey: key)
        }
        return parseNumberedLines(reply, expected: texts.count)
    }

    /// The instruction sent to whichever model is selected.
    ///
    /// Numbered in and numbered out, so the answer can be matched back to the cue it belongs
    /// to rather than trusted to arrive in order. The result goes straight to the speech
    /// synthesiser, so anything the model adds around it would be read aloud.
    static func prompt(for texts: [String],
                       from sourceLang: String,
                       to targetLang: String) -> String {
        var lines = """
        Translate each numbered line below from \(languageName(sourceLang)) to \(languageName(targetLang)).

        They are short spoken announcements that a speech synthesiser will read aloud to a \
        photographer during a solar eclipse. Keep them short and natural, and leave \
        photographic terms and camera settings exactly as they are (for example «bracketing», \
        «F8», «1/500», «ISO 100»).

        Reply with exactly \(texts.count) lines, each starting with its own number followed by \
        «) », in the same order, and nothing else — no preamble, no quotes, no blank lines.


        """
        for (index, text) in texts.enumerated() {
            lines += "\(index + 1)) \(text.replacingOccurrences(of: "\n", with: " "))\n"
        }
        return lines
    }

    /// Maps a numbered reply back onto the request, by number rather than by position.
    ///
    /// A model that drops or merges a line would otherwise shift every announcement after it
    /// onto the wrong cue — the right words at the wrong second. Anything unmatched stays nil
    /// and the caller falls back to the original text.
    static func parseNumberedLines(_ reply: String, expected: Int) -> [String?] {
        var byIndex: [Int: String] = [:]

        for rawLine in reply.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(where: { ").-:".contains($0) }) else { continue }
            let numberPart = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            guard let number = Int(numberPart), number >= 1, number <= expected else { continue }

            let text = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { byIndex[number - 1] = text }
        }

        return (0..<expected).map { byIndex[$0] }
    }

    // MARK: - Claude

    private static func translateWithClaude(_ prompt: String, apiKey: String) async throws -> String {
        let body = ClaudeRequest(
            model:      claudeModel,
            max_tokens: claudeMaxTokens,
            messages:   [ClaudeMessage(role: "user", content: prompt)]
        )

        var request = URLRequest(url: claudeEndpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await send(request)
        let parsed = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        let joined = parsed.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard !joined.isEmpty else { throw TranslationError.emptyResponse }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini

    private static func translateWithGemini(_ prompt: String, apiKey: String) async throws -> String {
        let body = GeminiRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(maxOutputTokens: geminiMaxTokens)
        )

        var request = URLRequest(url: geminiEndpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        // La clave va en cabecera y no como `?key=`, que es la otra forma que admite la API:
        // una clave en la URL acaba en registros de proxy, en historiales y en cualquier
        // traza de red, y aquí no cuesta nada evitarlo.
        request.setValue(apiKey,             forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await send(request)
        let parsed = try JSONDecoder().decode(GeminiResponse.self, from: data)

        // Una respuesta truncada trae texto válido a medias, y devolverla sería lo peor
        // posible: en vez de caer al original, el fotógrafo oiría media frase durante la
        // totalidad. Se trata como error para que el llamador use el texto original.
        if parsed.candidates?.first?.finishReason == "MAX_TOKENS" {
            throw TranslationError.truncated
        }

        // Cada parte se concatena en vez de tomar la primera: una respuesta puede venir
        // repartida en varias.
        let joined = (parsed.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !joined.isEmpty else { throw TranslationError.emptyResponse }
        return joined
    }

    // MARK: - Transport

    /// Sends `request`, failing fast on HTTP errors so the caller falls back to the original.
    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(statusCode: http.statusCode)
        }
        return data
    }

    /// Maps a BCP-47 tag to an English language name for the prompt.
    ///
    /// The tag itself ("ca-ES") is less reliable in a prompt than the name: models occasionally
    /// read a region subtag as the language.
    private static func languageName(_ tag: String) -> String {
        switch tag.lowercased().prefix(2) {
        case "es": return "Spanish"
        case "ca": return "Catalan"
        case "en": return "English"
        default:   return tag
        }
    }
}

// MARK: - TranslationError

enum TranslationError: LocalizedError {
    case emptyResponse
    case httpError(statusCode: Int)
    case missingKey
    case truncated

    var errorDescription: String? {
        switch self {
        case .emptyResponse:       return "Empty translation response."
        case .httpError(let code): return "Translation API error (HTTP \(code))."
        case .missingKey:          return "No API key configured for the selected engine."
        case .truncated:           return "Translation was cut off by the token limit."
        }
    }
}
