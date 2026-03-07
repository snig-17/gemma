//
//  TutoringViewModel.swift
//  gemma
//

import SwiftUI
import PencilKit

@Observable
class TutoringViewModel {
    var sessions: [TutoringSession] = []
    var currentSession: TutoringSession
    var messages: [ChatMessage] = []
    var isLoading = false
    var showSessionHistory = false
    var canvasView = PKCanvasView()
    var toolPicker = PKToolPicker()
    var speechService = SpeechService()
    var whiteboardBackground: WhiteboardBackground = .grid
    
    // Subject context
    var subject: Subject
    
    // Gemini API configuration
    private let apiKey = Secrets.geminiAPIKey
    private let apiURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent"
    
    init(subject: Subject = Subject(name: "General")) {
        self.subject = subject
        let session = TutoringSession(subject: subject.name)
        self.currentSession = session
        self.sessions = [session]
        loadSessions()
        
        // Share API key with speech service for Google TTS
        speechService.apiKey = apiKey
        
        // Wire speech service callbacks
        speechService.onFinalTranscript = { [weak self] transcript in
            guard let self else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Include whiteboard snapshot if there's content on it
            let imageData = self.captureWhiteboardImage()
            self.sendMessage(trimmed, imageData: imageData)
        }
        
        // When wake word "Gemma" is detected, also check whiteboard
        speechService.onWakeWordDetected = { [weak self] in
            // Wake word will trigger startListening in SpeechService
            // The whiteboard will be included when the transcript comes through
        }
        
        // Start wake word listening
        speechService.startWakeWordListening()
    }
    
    // MARK: - Message Handling
    
    func sendMessage(_ text: String, imageData: Data? = nil) {
        let userMessage = ChatMessage(content: text, isUser: true)
        messages.append(userMessage)
        currentSession.messages = messages
        currentSession.lastModified = Date()
        
        // Auto-title from first message
        if messages.count == 1 {
            currentSession.title = String(text.prefix(40))
        }
        
        saveSessions()
        callGemma(prompt: text, imageData: imageData)
    }
    
    func sendWhiteboardSnapshot() {
        guard let imageData = captureWhiteboardImage() else {
            sendMessage("Please look at what I've drawn on the whiteboard and help me understand or solve it.")
            return
        }
        sendMessage("Please look at what I've drawn/written on the whiteboard and help me understand or solve it. Read any handwritten text carefully.", imageData: imageData)
    }
    
    private func captureWhiteboardImage() -> Data? {
        let drawing = canvasView.drawing
        let bounds = drawing.bounds
        guard !bounds.isEmpty else { return nil }
        
        let padding: CGFloat = 40
        let renderRect = bounds.insetBy(dx: -padding, dy: -padding)
        let scale: CGFloat = 2.0
        
        let renderer = UIGraphicsImageRenderer(size: renderRect.size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: renderRect.size))
            let drawImage = drawing.image(from: renderRect, scale: scale)
            drawImage.draw(in: CGRect(origin: .zero, size: renderRect.size))
        }
        
        return image.pngData()
    }
    
    // MARK: - Gemma API
    
    private func callGemma(prompt: String, imageData: Data? = nil, silent: Bool = false) {
        isLoading = true
        if !silent {
            speechService.setProcessing()
        }
        
        Task { @MainActor in
            do {
                let response = try await performAPICall(prompt: prompt, imageData: imageData)
                let aiMessage = ChatMessage(content: response, isUser: false)
                messages.append(aiMessage)
                currentSession.messages = messages
                currentSession.lastModified = Date()
                saveSessions()
                
                speechService.speak(response)
            } catch {
                if !silent {
                    let errorText = "I'm having trouble connecting. Please check your API key and try again."
                    let errorMessage = ChatMessage(
                        content: errorText + "\n\nError: \(error.localizedDescription)",
                        isUser: false
                    )
                    messages.append(errorMessage)
                    speechService.speak(errorText)
                } else {
                    print("[Gemma API] Silent whiteboard check failed: \(error.localizedDescription)")
                }
            }
            isLoading = false
        }
    }
    
    private func performAPICall(prompt: String, imageData: Data?) async throws -> String {
        let url = URL(string: "\(apiURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are Gemma, a friendly and knowledgeable AI tutor in a live voice conversation. The student is currently studying \(subject.name). You help students learn by:
        - Explaining \(subject.name) concepts clearly and step-by-step
        - Asking guiding questions to help students think
        - Providing encouragement and constructive feedback
        - Using examples and analogies to make concepts accessible
        - When reviewing handwritten work, carefully analyze what's written and provide helpful feedback
        - You can see the student's whiteboard at all times, so reference their work when relevant
        Keep responses concise. Avoid markdown formatting, bullet points, code blocks, or special characters. Speak naturally as if tutoring in person.
        """
        
        // Build multi-turn conversation history for context
        var contents: [[String: Any]] = []
        
        // System instruction as first user turn
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": "Hello! I'm Gemma, your \(subject.name) tutor. I can see your whiteboard and I'm here to help. What would you like to work on?"]]
        ])
        
        // Add conversation history (keep last 20 messages to avoid token limits)
        let recentMessages = messages.suffix(20)
        for msg in recentMessages {
            contents.append([
                "role": msg.isUser ? "user" : "model",
                "parts": [["text": msg.content]]
            ])
        }
        
        // Add the current prompt with optional image
        var currentParts: [[String: Any]] = [["text": prompt]]
        if let imageData {
            let base64Image = imageData.base64EncodedString()
            currentParts.insert([
                "inline_data": [
                    "mime_type": "image/png",
                    "data": base64Image
                ]
            ], at: 0)
        }
        contents.append([
            "role": "user",
            "parts": currentParts
        ])
        
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1024
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResp = httpResponse as? HTTPURLResponse {
            print("[Gemma API] Status: \(httpResp.statusCode)")
        }
        if let rawBody = String(data: data, encoding: .utf8) {
            print("[Gemma API] Response: \(rawBody.prefix(500))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let text = responseParts.first?["text"] as? String else {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "GemmaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "GemmaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }
        
        return text
    }
    
    /// Returns an updated subject with current session/message stats
    var updatedSubject: Subject {
        var s = subject
        s.sessionCount = sessions.count
        s.totalMessages = sessions.reduce(0) { $0 + $1.messages.count }
        return s
    }
    
    // MARK: - Canvas Management
    
    var canvasHasStrokes: Bool {
        !canvasView.drawing.strokes.isEmpty
    }
    
    func clearCanvas() {
        canvasView.drawing = PKDrawing()
    }
    
    func finishNote(save: Bool) {
        if save {
            saveDrawingToSession()
        }
        clearCanvas()
    }
    
    func saveDrawingToSession() {
        currentSession.drawingData = canvasView.drawing.dataRepresentation()
        saveSessions()
    }
    
    func loadDrawingFromSession() {
        if let data = currentSession.drawingData,
           let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        } else {
            canvasView.drawing = PKDrawing()
        }
    }
    
    // MARK: - Session Management
    
    func createNewSession() {
        saveDrawingToSession()
        speechService.stopSpeaking()
        let newSession = TutoringSession(subject: subject.name)
        sessions.insert(newSession, at: 0)
        currentSession = newSession
        messages = []
        clearCanvas()
        saveSessions()
    }
    
    func selectSession(_ session: TutoringSession) {
        saveDrawingToSession()
        speechService.stopSpeaking()
        currentSession = session
        messages = session.messages
        loadDrawingFromSession()
        showSessionHistory = false
    }
    
    func deleteSession(at offsets: IndexSet) {
        let deletingCurrent = offsets.contains(where: { sessions[$0].id == currentSession.id })
        sessions.remove(atOffsets: offsets)
        
        if deletingCurrent {
            if sessions.isEmpty {
                createNewSession()
            } else {
                selectSession(sessions[0])
            }
        }
        saveSessions()
    }
    
    // MARK: - Persistence
    
    private var sessionsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tutoring_sessions.json")
    }
    
    func saveSessions() {
        if let index = sessions.firstIndex(where: { $0.id == currentSession.id }) {
            sessions[index] = currentSession
        }
        
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: sessionsURL)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
    
    func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return }
        do {
            let data = try Data(contentsOf: sessionsURL)
            let decoded = try JSONDecoder().decode([TutoringSession].self, from: data)
            if !decoded.isEmpty {
                sessions = decoded
                currentSession = decoded[0]
                messages = currentSession.messages
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
}
