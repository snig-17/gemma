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
class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    
    // State
    var speechState: SpeechState = .idle
    var liveTranscript: String = ""
    var audioLevel: Float = 0.0
    var errorMessage: String?
    
    // Callbacks
    var onFinalTranscript: ((String) -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    // Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    private var hasFinished = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
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
    
    // MARK: - Listening (Speech-to-Text)
    
    func startListening() {
        // If speaking, stop first
        if speechState == .speaking {
            stopSpeaking()
        }
        
        // Reset the finish guard for a new listening session
        hasFinished = false
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
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
            
            // Calculate audio level for avatar animation
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
                    self.liveTranscript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    
                    if result.isFinal {
                        self.finishListening()
                    }
                }
            }
            
            if let error {
                Task { @MainActor in
                    // Don't show error if we intentionally cancelled
                    if self.speechState == .listening {
                        self.errorMessage = error.localizedDescription
                    }
                    self.stopAudioEngine()
                }
            }
        }
    }
    
    func stopListening() {
        guard speechState == .listening else { return }
        finishListening()
    }
    
    private func finishListening() {
        // Guard against being called twice (silence timer + isFinal callback)
        guard !hasFinished else { return }
        hasFinished = true
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        recognitionRequest?.endAudio()
        stopAudioEngine()
        
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechState = .processing
        audioLevel = 0
        
        if !transcript.isEmpty {
            onFinalTranscript?(transcript)
        } else {
            speechState = .idle
        }
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
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
    
    // MARK: - Speaking (Text-to-Speech)
    
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        
        speechState = .speaking
        liveTranscript = text
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        speechState = .idle
        audioLevel = 0
    }
    
    // MARK: - Set Processing State
    
    func setProcessing() {
        speechState = .processing
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speechState = .idle
            self.audioLevel = 0
            self.onSpeechFinished?()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Animate audio level during speech
        Task { @MainActor in
            // Simulate audio level variation during TTS
            self.audioLevel = Float.random(in: 0.3...0.8)
        }
    }
}
