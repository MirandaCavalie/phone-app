import AVFoundation
import Foundation
import Speech

/// Push-to-talk speech recognition that stays on the phone when the device supports it.
@MainActor
final class SpeechListener: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isOnDevice = false
    @Published private(set) var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func configure(for country: Country) {
        let locale = Locale(identifier: Self.localeIdentifier(for: country))
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
        isOnDevice = recognizer?.supportsOnDeviceRecognition == true
    }

    func start() async {
        problem = nil
        guard await Self.authorize() else {
            problem = "Activa el micrófono y el reconocimiento de voz en Ajustes para hablarle a Faro."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "El reconocimiento de voz no está disponible ahora."
            return
        }

        stopEngine()
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Offline is the whole point: never send audio to a server when the phone can do it locally.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            problem = "No pude usar el micrófono."
            stopEngine()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.stopEngine() }
            }
        }
    }

    /// Stops listening and returns what was understood.
    func finish() -> String {
        request?.endAudio()
        stopEngine()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    static func localeIdentifier(for country: Country) -> String {
        switch country {
        case .colombia: "es-CO"
        case .venezuela: "es-VE"
        case .mexico: "es-MX"
        case .chile: "es-CL"
        case .peru: "es-PE"
        case .ecuador: "es-EC"
        case .argentina: "es-AR"
        case .unitedStates: "es-US"
        }
    }
}

/// Reads the agent's important updates aloud, so nobody has to stare at a screen in a crisis.
@MainActor
final class Narrator {
    private let synthesizer = AVSpeechSynthesizer()
    private var spoken = Set<UUID>()
    private var primed = false

    var isEnabled = true

    /// Speaks entries that matter during an emergency and were not spoken before.
    func narrate(_ log: [ActivityEntry], country: Country) {
        // Never re-read history when the app launches; only what happens from now on.
        guard primed else {
            spoken = Set(log.map(\.id))
            primed = true
            return
        }
        let important: Set<ActivityEntry.Kind> = [.mode, .agreement, .family, .followUp]
        for entry in log.prefix(8).reversed() where !spoken.contains(entry.id) {
            spoken.insert(entry.id)
            if isEnabled, important.contains(entry.kind) {
                speak("\(entry.title). \(Self.spokenDetail(entry.detail))", country: country)
            }
        }
    }

    func speak(_ text: String, country: Country) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: SpeechListener.localeIdentifier(for: country))
            ?? AVSpeechSynthesisVoice(language: "es-MX")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Detail text written for reading, trimmed for listening.
    private static func spokenDetail(_ detail: String) -> String {
        detail
            .replacingOccurrences(of: " · ", with: ", ")
            .components(separatedBy: ". Llegó por la red").first ?? detail
    }
}
