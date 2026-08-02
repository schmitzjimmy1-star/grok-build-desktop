import Foundation
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceInputService {
    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private var recognizer: SFSpeechRecognizer?
    private var recognizerLoaded = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    // Construction must stay trivial: a fresh instance is created every time
    // ChatView's struct is initialized (its @State default expression), which
    // happens far more often than voice input is used. The engine and the
    // speech-daemon connection are created on first start() instead.
    private var loadedAudioEngine: AVAudioEngine?

    private var audioEngine: AVAudioEngine {
        if let loadedAudioEngine { return loadedAudioEngine }
        let engine = AVAudioEngine()
        loadedAudioEngine = engine
        return engine
    }

    func start(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        guard state == .idle else { return }
        if !recognizerLoaded {
            recognizerLoaded = true
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition unavailable")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.state = .unavailable("Speech permission denied")
                    return
                }
                self?.beginRecognition(onPartial: onPartial, onFinal: onFinal)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if let engine = loadedAudioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        if state == .listening || state == .transcribing {
            state = .idle
        }
    }

    private func beginRecognition(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        stop()
        state = .listening

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .unavailable(error.localizedDescription)
            return
        }

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.state = .transcribing
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                        self.stop()
                    } else {
                        onPartial(text)
                    }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }
}
