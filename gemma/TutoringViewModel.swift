//
//  TutoringViewModel.swift
//  gemma
//

import SwiftUI
import PencilKit
import PDFKit

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
    var flashcards: [Flashcard] = []
    
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
        loadFlashcards()
        
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
        sendMessage("Look at my whiteboard carefully. Read every word, number, equation, and symbol I've written. Tell me exactly what you see, then help me with it. If there are any errors, point out exactly where they are.", imageData: imageData)
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
        
        return image.jpegData(compressionQuality: 0.7)
    }
    
    // MARK: - Gemma API
    
    private func callGemma(prompt: String, imageData: Data? = nil, silent: Bool = false) {
        isLoading = true
        if !silent {
            speechService.setProcessing()
        }
        
        Task { @MainActor in
            do {
                let rawResponse = try await performAPICall(prompt: prompt, imageData: imageData)
                
                // Parse flashcard tags from the AI response
                let (newCards, cleanedResponse) = Flashcard.parseFlashcards(from: rawResponse, subject: subject.name)
                if !newCards.isEmpty {
                    flashcards.append(contentsOf: newCards)
                    saveFlashcards()
                }
                
                let aiMessage = ChatMessage(content: cleanedResponse, isUser: false)
                messages.append(aiMessage)
                currentSession.messages = messages
                currentSession.lastModified = Date()
                saveSessions()
                
                speechService.speak(cleanedResponse)
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
        request.timeoutInterval = 15
        
        let systemPrompt = """
        You are Gemma, a friendly and knowledgeable AI tutor in a live voice conversation. The student is currently studying \(subject.name). You help students learn by:
        - Explaining \(subject.name) concepts clearly and step-by-step
        - Asking guiding questions to help students think
        - Providing encouragement and constructive feedback
        - Using examples and analogies to make concepts accessible
        
        WHITEBOARD ANALYSIS: You can see the student's whiteboard in real-time. When an image is attached:
        - Read ALL handwritten text, numbers, equations, and symbols very carefully before responding
        - Identify each step the student has written, noting any errors in specific steps
        - When you see mathematical work, trace through the logic step by step
        - If handwriting is unclear, state what you think it says and ask for confirmation
        - Reference specific parts of their work by describing what you see (e.g. "In the second line where you wrote...")
        - Point out exactly where mistakes occur and explain why they are wrong
        
        Keep responses SHORT (2-4 sentences max). Avoid markdown formatting, bullet points, code blocks, or special characters. Speak naturally as if tutoring in person. Get straight to the point.
        
        FLASHCARDS: When the student struggles with a concept, makes repeated errors, or asks you to explain something they find confusing, create a flashcard by adding this tag at the END of your response:
        [FLASHCARD front:concept or question back:brief clear explanation]
        Only create a flashcard when the student genuinely struggles — not for every topic. Max 1 flashcard per response.
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
                    "mime_type": "image/jpeg",
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
                "maxOutputTokens": 300
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
    
    /// Export the current whiteboard as a PDF, returns the file URL
    func exportPDF() -> URL? {
        let drawing = canvasView.drawing
        let bounds = drawing.bounds
        guard !bounds.isEmpty else { return nil }
        
        let padding: CGFloat = 40
        let renderRect = bounds.insetBy(dx: -padding, dy: -padding)
        
        // Create PDF data
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: renderRect.size))
        let pdfData = pdfRenderer.pdfData { pdfContext in
            pdfContext.beginPage()
            
            // Draw white background
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: renderRect.size))
            
            // Draw the background pattern
            drawBackgroundPattern(in: CGRect(origin: .zero, size: renderRect.size), offset: renderRect.origin)
            
            // Draw the PencilKit content
            let image = drawing.image(from: renderRect, scale: 2.0)
            image.draw(in: CGRect(origin: .zero, size: renderRect.size))
        }
        
        // Save to temp file
        let fileName = "\(currentSession.title.prefix(30))_\(Date().formatted(.dateTime.year().month().day())).pdf"
        let sanitizedName = fileName.replacingOccurrences(of: "/", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(sanitizedName)
        
        do {
            try pdfData.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to write PDF: \(error)")
            return nil
        }
    }
    
    private func drawBackgroundPattern(in rect: CGRect, offset: CGPoint) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        switch whiteboardBackground {
        case .grid:
            let spacing: CGFloat = 24
            ctx.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.1).cgColor)
            ctx.setLineWidth(0.5)
            
            let startRow = Int(offset.y / spacing)
            let endRow = Int((offset.y + rect.height) / spacing) + 1
            let startCol = Int(offset.x / spacing)
            let endCol = Int((offset.x + rect.width) / spacing) + 1
            
            for row in startRow...endRow {
                let y = CGFloat(row) * spacing - offset.y
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: rect.width, y: y))
            }
            for col in startCol...endCol {
                let x = CGFloat(col) * spacing - offset.x
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: rect.height))
            }
            ctx.strokePath()
            
        case .dotted:
            let spacing: CGFloat = 24
            ctx.setFillColor(UIColor.secondaryLabel.withAlphaComponent(0.15).cgColor)
            
            let startRow = Int(offset.y / spacing)
            let endRow = Int((offset.y + rect.height) / spacing) + 1
            let startCol = Int(offset.x / spacing)
            let endCol = Int((offset.x + rect.width) / spacing) + 1
            
            for row in startRow...endRow {
                for col in startCol...endCol {
                    let x = CGFloat(col) * spacing - offset.x
                    let y = CGFloat(row) * spacing - offset.y
                    ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                }
            }
            
        case .lined:
            let spacing: CGFloat = 32
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.12).cgColor)
            ctx.setLineWidth(0.5)
            
            let startRow = max(1, Int(offset.y / spacing))
            let endRow = Int((offset.y + rect.height) / spacing) + 1
            
            for row in startRow...endRow {
                let y = CGFloat(row) * spacing - offset.y
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: rect.width, y: y))
            }
            ctx.strokePath()
            
        case .plain:
            break
        }
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
    
    // MARK: - Flashcard Management
    
    func deleteFlashcard(_ flashcard: Flashcard) {
        flashcards.removeAll { $0.id == flashcard.id }
        saveFlashcards()
    }
    
    func markReviewed(_ flashcard: Flashcard) {
        if let index = flashcards.firstIndex(where: { $0.id == flashcard.id }) {
            flashcards[index].reviewCount += 1
            flashcards[index].lastReviewed = Date()
            saveFlashcards()
        }
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
    
    // MARK: - Flashcard Persistence
    
    private var flashcardsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("flashcards.json")
    }
    
    func saveFlashcards() {
        do {
            let data = try JSONEncoder().encode(flashcards)
            try data.write(to: flashcardsURL)
        } catch {
            print("Failed to save flashcards: \(error)")
        }
    }
    
    func loadFlashcards() {
        guard FileManager.default.fileExists(atPath: flashcardsURL.path) else { return }
        do {
            let data = try Data(contentsOf: flashcardsURL)
            flashcards = try JSONDecoder().decode([Flashcard].self, from: data)
        } catch {
            print("Failed to load flashcards: \(error)")
        }
    }
}
