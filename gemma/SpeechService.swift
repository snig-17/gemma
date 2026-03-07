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
        
        Task { @MainActor in
            // Configure audio session for playback immediately (no delay)
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try audioSession.setActive(true)
            } catch {
                print("[Audio Session] Setup error: \(error.localizedDescription)")
            }
            
            // Try Google TTS first, fall back to Apple TTS
            let success = await speakWithGoogleTTS(text)
            if !success {
                speakWithAppleTTS(text)
            }
        }
    }
    
    private func speakWithGoogleTTS(_ text: String) async -> Bool {
        guard !apiKey.isEmpty else { return false }
        
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Try MP3 first (much smaller payload = faster download), fall back to LINEAR16
        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "en-US",
                "name": "en-US-Journey-F",
                "ssmlGender": "FEMALE"
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": 1.0,
                "pitch": 0.0
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            
            if let httpResp = httpResponse as? HTTPURLResponse {
                print("[Google TTS] Status: \(httpResp.statusCode)")
                guard httpResp.statusCode == 200 else {
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[Google TTS] API Error: \(raw.prefix(500))")
                    }
                    return false
                }
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioContent = json["audioContent"] as? String,
                  let audioData = Data(base64Encoded: audioContent) else {
                if let raw = String(data: data, encoding: .utf8) {
                    print("[Google TTS] Parse error: \(raw.prefix(300))")
                }
                return false
            }
            
            // Try playing MP3 directly
            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
            } catch {
                print("[Google TTS] MP3 decode failed, retrying with LINEAR16...")
                return await speakWithGoogleTTSLinear16(text)
            }
            
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            startSpeakingAnimation()
            
            print("[Google TTS] Playing \(audioData.count) bytes of MP3 audio")
            return true
        } catch {
            print("[Google TTS] Failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Fallback: Use LINEAR16 encoding if MP3 fails
    private func speakWithGoogleTTSLinear16(_ text: String) async -> Bool {
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "en-US",
                "name": "en-US-Journey-F",
                "ssmlGender": "FEMALE"
            ],
            "audioConfig": [
                "audioEncoding": "LINEAR16",
                "sampleRateHertz": 24000,
                "speakingRate": 1.0,
                "pitch": 0.0
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioContent = json["audioContent"] as? String,
                  let rawPCM = Data(base64Encoded: audioContent) else {
                return false
            }
            
            let wavData = createWAVData(from: rawPCM, sampleRate: 24000, channels: 1, bitsPerSample: 16)
            
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            startSpeakingAnimation()
            
            print("[Google TTS] Playing \(wavData.count) bytes of LINEAR16 audio (fallback)")
            return true
        } catch {
            print("[Google TTS LINEAR16] Failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Wraps raw PCM data in a WAV header so AVAudioPlayer can play it
    private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize
        
        var header = Data()
        
        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt subchunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // subchunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        
        // data subchunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        
        // Combine header + PCM data
        header.append(pcmData)
        return header
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
        speakingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
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
    
    // MARK: - Resume Wake Word After Speaking
    
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
