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

    /// `gemini-3.6-flash` is the current stable Flash and is on the free tier. The 2.0 models
    /// have been shut down, so pinning an older one would break without warning.
    private static let geminiEndpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
    )!

    private static let claudeMaxTokens = 512

    /// Output budget for Gemini, deliberately eight times Claude's.
    ///
    /// Gemini 3 reasons before answering, and those reasoning tokens are charged against
    /// `maxOutputTokens`. Measured on this very prompt: 312 to 1087 thinking tokens to
    /// translate one line. At 512 the model spent 491 of them thinking, had 17 left, and
    /// returned "L'eclipsi comença en 5 minuts, posar filtre," — cut off exactly where the
    /// camera settings began, with `finishReason: MAX_TOKENS`.
    ///
    /// Reasoning cannot simply be switched off: `thinkingBudget: 0` is rejected by this
    /// model, and `thinkingLevel: low` still spent 487. So the budget leaves room instead.
    private static let geminiMaxTokens = 4096

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

    /// Translates `text` from `sourceLang` to `targetLang` using `engine`.
    ///
    /// - Parameters:
    ///   - text:       Announcement text to translate (the `message` field of a `ProgramEvent`).
    ///   - sourceLang: BCP-47 code of the source text (e.g. "es-ES").
    ///   - targetLang: BCP-47 code of the desired output (e.g. "ca-ES").
    ///   - engine:     Back end chosen in Settings.
    ///   - apiKey:     Key for that engine.
    /// - Returns: Trimmed translated string.
    /// - Throws: `URLError` on network failure; `TranslationError` on a blank key or an
    ///   invalid response. The caller falls back to the original text.
    static func translate(_ text:          String,
                          from sourceLang: String,
                          to   targetLang: String,
                          engine:          TranslationEngine,
                          apiKey:          String) async throws -> String {

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TranslationError.missingKey
        }

        let prompt = prompt(for: text, from: sourceLang, to: targetLang)

        switch engine {
        case .claude: return try await translateWithClaude(prompt, apiKey: apiKey)
        case .gemini: return try await translateWithGemini(prompt, apiKey: apiKey)
        }
    }

    /// The instruction sent to whichever model is selected.
    ///
    /// Asks for the translation only, with no preamble, because the result goes straight to
    /// the speech synthesiser: any "Here is the translation:" would be read aloud.
    private static func prompt(for text: String,
                               from sourceLang: String,
                               to targetLang: String) -> String {
        """
        Translate the following short spoken announcement from \(languageName(sourceLang)) \
        to \(languageName(targetLang)). It will be read aloud by a speech synthesiser to a \
        photographer during a solar eclipse, so keep it short and natural. \
        Reply with the translation only, no quotes and no explanation.

        \(text)
        """
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

        guard let translated = parsed.content.first(where: { $0.type == "text" })?.text else {
            throw TranslationError.emptyResponse
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
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
