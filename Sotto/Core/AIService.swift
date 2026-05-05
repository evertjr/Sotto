import Foundation
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct PolishedTranscription {
    @Guide(description: "The language of the user's input transcription. Examples: 'Portuguese', 'English', 'Spanish', 'French'. Identify this FIRST before writing the polished text.")
    let detectedLanguage: String
    @Guide(description: "The polished text written in detectedLanguage. NEVER translate. Use markdown: numbered lists for steps, bullet points for items.")
    let text: String
}

@available(macOS 26.0, *)
@Generable
struct TranslatedTranscription {
    @Guide(description: "The full transcription translated into the target language. Preserve the tone and intent of the original.")
    let text: String
}

@available(macOS 26.0, *)
@MainActor
final class AIService {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    var unavailableReason: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            return "The language model is still downloading."
        case .unavailable(_):
            return "The language model is currently unavailable."
        }
    }

    func polish(_ transcription: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Rewrite spoken text into clean written text. Keep the same language. Never translate.
            Remove filler words. Fix punctuation and grammar.
            When items are listed or steps are enumerated, format as a numbered or bulleted list.
            Only use words from the input. Never add new content.
            """)

        let response = try await session.respond(
            to: transcription,
            generating: PolishedTranscription.self
        )
        return response.content.text
    }

    func translate(_ transcription: String, to targetLanguage: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            <instructions>
            You are a translation tool. Translate the user's transcription into \(targetLanguage).
            Preserve the tone, intent, and meaning of the original.
            Return ONLY the translated text.
            </instructions>
            """)

        let response = try await session.respond(
            to: """
            <user_audio_transcription>
            \(transcription)
            </user_audio_transcription>
            <reminders>
            - Translate into \(targetLanguage).
            - Preserve the original tone and meaning.
            - Return only the translation, no explanations.
            </reminders>
            """,
            generating: TranslatedTranscription.self
        )
        return response.content.text
    }
}

func withAITimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    let task = Task { try await operation() }
    let timeoutTask = Task {
        try await Task.sleep(for: .seconds(seconds))
        task.cancel()
    }
    do {
        let result = try await task.value
        timeoutTask.cancel()
        return result
    } catch is CancellationError {
        timeoutTask.cancel()
        throw AITimeoutError()
    } catch {
        timeoutTask.cancel()
        throw error
    }
}

struct AITimeoutError: LocalizedError {
    var errorDescription: String? { "AI processing timed out" }
}
