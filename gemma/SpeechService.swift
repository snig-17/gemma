//
//  SpeechService.swift
//  gemma
//

import Foundation
import Speech
import AVFoundation
import Accelerate

// MARK: - Speech State

nonisolated enum SpeechState: Equatable, Sendable {
    case idle
    case listening
    case processing
    case speaking
}

// MARK: - Speech Service

@Observable
class SpeechService: NSObject {
    
    // State
    var speechState: SpeechState = .idle
    var liveTranscript: String = ""
    var audioLevel: Float = 0.0
    var errorMessage: String?
    
    // Callbacks
    var onFinalTranscript: ((String) -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    // Google TTS API key (shared with Gemini)
    var apiKey: String = ""
    
    // Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Audio playback
    private var audioPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    
    // Shared URL session with tight timeouts for TTS
    private let ttsSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    private var hasFinished = false
    private var audioSessionReady = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
        // Pre-warm audio session so it's ready when TTS returns
        prepareAudioSession()
    }
    
    /// Prepare audio session once at startup so speak() doesn't wait
    private func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            audioSessionReady = true
        } catch {
            print("[Audio Session] Pre-warm failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Permissions
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                if status != .authorized {
                    self.errorMessage = "Speech recognition not authorized."
                }
            }
        }
        
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                if !granted {
                    self.errorMessage = "Microphone access not granted."
                }
            }
        }
    }
    
    var hasPermissions: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    // MARK: - Active Listening (Speech-to-Text)
    
    func startListening() {
        if speechState == .speaking {
            stopSpeaking()
        }
        
        // Clean up any existing audio engine state (wake word or previous listen)
        stopAudioEngine()
        
        hasFinished = false
        
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available."
            return
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            
            var rms: Float = 0
            vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameLength))
            rms = sqrtf(rms)
            let normalized = min(max(rms * 25, 0), 1.0)
            
            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Audio engine error: \(error.localizedDescription)"
            return
        }
        
        liveTranscript = ""
        speechState = .listening
        resetSilenceTimer()
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                Task { @MainActor in
                    guard self.speechState == .listening else { return }
                    self.liveTranscript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    
                    if result.isFinal {
                        self.finishListening()
                    }
                }
            }
            
            if error != nil {
                Task { @MainActor in
                    // Only handle error if we're still in listening state
                    // After finishListening, ignore stale callbacks
                    guard self.speechState == .listening else { return }
                    self.finishListening()
                }
            }
        }
    }
    
    func stopListening() {
        guard speechState == .listening else { return }
        finishListening()
    }
    
    private func finishListening() {
        guard !hasFinished else { return }
        hasFinished = true
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        recognitionRequest?.endAudio()
        stopAudioEngine()
        
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechState = .processing
        audioLevel = 0
        
        // Re-prepare audio session for playback (listening used .measurement mode)
        prepareAudioSession()
        
        if !transcript.isEmpty {
            onFinalTranscript?(transcript)
        } else {
            speechState = .idle
        }
    }
    
    private func stopAudioEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // Always remove tap — it can exist even if engine isn't running
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.speechState == .listening else { return }
                self.finishListening()
            }
        }
    }
    
    // MARK: - Speaking (Google Cloud Text-to-Speech)
    
    func speak(_ text: String) {
        speechState = .speaking
        liveTranscript = text
        
        // Ensure audio session is ready (no-op if already prepared)
        if !audioSessionReady {
            prepareAudioSession()
        }
        
        Task { @MainActor in
            let audioData = await fetchGoogleTTSAudio(text)
            
            if let audioData, let player = try? AVAudioPlayer(data: audioData) {
                audioPlayer = player
                audioPlayer?.delegate = self
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                startSpeakingAnimation()
            } else {
                // Fall back to Apple TTS
                speakWithAppleTTS(text)
            }
        }
    }
    
    /// Fetch TTS audio data from Google, returns MP3 data or nil
    private func fetchGoogleTTSAudio(_ text: String) async -> Data? {
        guard !apiKey.isEmpty else { return nil }
        
        // Truncate very long responses to keep TTS fast
        let truncated = String(text.prefix(800))
        
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "input": ["text": truncated],
            "voice": [
                "languageCode": "en-US",
                "name": "en-US-Standard-F",
                "ssmlGender": "FEMALE"
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": 1.12,
                "pitch": 1.0
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, httpResponse) = try await ttsSession.data(for: request)
            
            if let httpResp = httpResponse as? HTTPURLResponse, httpResp.statusCode != 200 {
                print("[Google TTS] Status: \(httpResp.statusCode)")
                return nil
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioContent = json["audioContent"] as? String,
                  let audioData = Data(base64Encoded: audioContent) else {
                return nil
            }
            
            return audioData
        } catch {
            print("[Google TTS] Failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func speakWithAppleTTS(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        startSpeakingAnimation()
    }
    
    private var speakingAnimationTimer: Timer?
    
    private func startSpeakingAnimation() {
        speakingAnimationTimer?.invalidate()
        speakingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.speechState == .speaking else {
                    self?.speakingAnimationTimer?.invalidate()
                    return
                }
                self.audioLevel = Float.random(in: 0.3...0.8)
            }
        }
    }
    
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        speakingAnimationTimer?.invalidate()
        speechState = .idle
        audioLevel = 0
    }
    
    // MARK: - Set Processing State
    
    func setProcessing() {
        speechState = .processing
    }
    
    // MARK: - Resume After Speaking
    
    private func resumeAfterSpeaking() {
        speechState = .idle
        audioLevel = 0
        speakingAnimationTimer?.invalidate()
        onSpeechFinished?()
    }
}

// MARK: - AVAudioPlayerDelegate & AVSpeechSynthesizerDelegate

extension SpeechService: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.resumeAfterSpeaking()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.resumeAfterSpeaking()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.audioLevel = Float.random(in: 0.3...0.8)
        }
    }
}
