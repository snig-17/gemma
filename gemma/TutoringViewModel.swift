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
    
    // Subject context
    var subject: Subject
    
    // Gemini API configuration
    private let apiKey = "AIzaSyDnJmAlqpfKUxE0Gg7iHVct-DqOdLkm_1I"
    private let apiURL = "https://generativelanguage.googleapis.com/v1beta/models/gemma-3-27b-it:generateContent"
    
    init(subject: Subject = Subject(name: "General")) {
        self.subject = subject
        let session = TutoringSession(subject: subject.name)
        self.currentSession = session
        self.sessions = [session]
        loadSessions()
        
        // Wire speech service callbacks
        speechService.onFinalTranscript = { [weak self] transcript in
            guard let self else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.sendMessage(trimmed)
        }
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
        let renderer = UIGraphicsImageRenderer(size: canvasView.bounds.size)
        let image = renderer.image { _ in
            canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
        }
        let imageData = image.jpegData(compressionQuality: 0.8)
        sendMessage("Please look at what I've drawn on the whiteboard and help me understand or solve it.", imageData: imageData)
    }
    
    // MARK: - Gemma API
    
    private func callGemma(prompt: String, imageData: Data? = nil) {
        isLoading = true
        speechService.setProcessing()
        
        Task { @MainActor in
            do {
                let response = try await performAPICall(prompt: prompt, imageData: imageData)
                let aiMessage = ChatMessage(content: response, isUser: false)
                messages.append(aiMessage)
                currentSession.messages = messages
                currentSession.lastModified = Date()
                saveSessions()
                
                // Speak the response
                speechService.speak(response)
            } catch {
                let errorText = "I'm having trouble connecting. Please check your API key and try again."
                let errorMessage = ChatMessage(
                    content: errorText + "\n\nError: \(error.localizedDescription)",
                    isUser: false
                )
                messages.append(errorMessage)
                speechService.speak(errorText)
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
        Keep responses concise. Avoid markdown formatting, bullet points, code blocks, or special characters. Speak naturally as if tutoring in person.
        """
        
        var parts: [[String: Any]] = [
            ["text": systemPrompt + "\n\nStudent: " + prompt]
        ]
        
        if let imageData {
            let base64Image = imageData.base64EncodedString()
            parts.insert([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64Image
                ]
            ], at: 0)
        }
        
        let body: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1024
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
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
    
    func clearCanvas() {
        canvasView.drawing = PKDrawing()
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
