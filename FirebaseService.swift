//
//  FirebaseService.swift
//  gemma
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AuthenticationServices
import CryptoKit

@Observable
class FirebaseService {
    static let shared = FirebaseService()
    
    var currentUser: FirebaseAuth.User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = true
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var authListener: AuthStateDidChangeListenerHandle?
    
    // For Sign in with Apple nonce
    var currentNonce: String?
    
    private init() {}
    
    // MARK: - Auth
    
    func listenToAuthState() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isLoading = false
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
        } catch {
            print("[Firebase] Sign out error: \(error.localizedDescription)")
        }
    }
    
    /// Handle the Apple ID credential and sign in with Firebase
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No nonce available"])
        }
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
        }
        
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        self.currentUser = result.user
    }
    
    /// Generate a random nonce for Sign in with Apple
    func generateNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Helper
    
    private var uid: String {
        guard let uid = currentUser?.uid else {
            fatalError("No authenticated user")
        }
        return uid
    }
    
    private var userDoc: DocumentReference {
        db.collection("users").document(uid)
    }
    
    // MARK: - Profile
    
    func saveProfile(_ profile: UserProfile) async throws {
        try userDoc.setData(from: profile, merge: true)
    }
    
    func loadProfile() async throws -> UserProfile? {
        let doc = try await userDoc.getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: UserProfile.self)
    }
    
    // MARK: - Subjects
    
    func saveSubjects(_ subjects: [Subject]) async throws {
        let batch = db.batch()
        let subjectsRef = userDoc.collection("subjects")
        
        // Write each subject
        for subject in subjects {
            let docRef = subjectsRef.document(subject.id.uuidString)
            try batch.setData(from: subject, forDocument: docRef, merge: true)
        }
        try await batch.commit()
    }
    
    func loadSubjects() async throws -> [Subject] {
        let snapshot = try await userDoc.collection("subjects").getDocuments()
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Subject.self)
        }
    }
    
    func deleteSubject(_ subject: Subject) async throws {
        try await userDoc.collection("subjects").document(subject.id.uuidString).delete()
    }
    
    // MARK: - Sessions
    
    func saveSession(_ session: TutoringSession) async throws {
        let docRef = userDoc.collection("sessions").document(session.id.uuidString)
        // Save session metadata (without messages — those go in subcollection)
        var sessionData = session
        sessionData.messages = [] // Don't embed messages in session doc
        try docRef.setData(from: sessionData, merge: true)
        
        // Save messages as subcollection
        if !session.messages.isEmpty {
            let batch = db.batch()
            let messagesRef = docRef.collection("messages")
            for message in session.messages {
                let msgDoc = messagesRef.document(message.id.uuidString)
                try batch.setData(from: message, forDocument: msgDoc, merge: true)
            }
            try await batch.commit()
        }
    }
    
    func loadSessions(forSubject subject: String) async throws -> [TutoringSession] {
        let snapshot = try await userDoc.collection("sessions")
            .whereField("subject", isEqualTo: subject)
            .order(by: "lastModified", descending: true)
            .getDocuments()
        
        var sessions: [TutoringSession] = []
        for doc in snapshot.documents {
            var session = try doc.data(as: TutoringSession.self)
            // Load messages subcollection
            let msgSnapshot = try await doc.reference.collection("messages")
                .order(by: "timestamp")
                .getDocuments()
            session.messages = msgSnapshot.documents.compactMap { try? $0.data(as: ChatMessage.self) }
            sessions.append(session)
        }
        return sessions
    }
    
    func deleteSession(_ session: TutoringSession) async throws {
        let docRef = userDoc.collection("sessions").document(session.id.uuidString)
        
        // Delete messages subcollection first
        let messages = try await docRef.collection("messages").getDocuments()
        let batch = db.batch()
        for msg in messages.documents {
            batch.deleteDocument(msg.reference)
        }
        try await batch.commit()
        
        // Delete session document
        try await docRef.delete()
        
        // Delete drawing from storage if exists
        if session.hasDrawing {
            try? await deleteDrawing(sessionId: session.id.uuidString)
        }
    }
    
    // MARK: - Flashcards
    
    func saveFlashcard(_ card: Flashcard) async throws {
        let docRef = userDoc.collection("flashcards").document(card.id.uuidString)
        try docRef.setData(from: card, merge: true)
    }
    
    func saveFlashcards(_ cards: [Flashcard]) async throws {
        let batch = db.batch()
        for card in cards {
            let docRef = userDoc.collection("flashcards").document(card.id.uuidString)
            try batch.setData(from: card, forDocument: docRef, merge: true)
        }
        try await batch.commit()
    }
    
    func loadFlashcards() async throws -> [Flashcard] {
        let snapshot = try await userDoc.collection("flashcards")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Flashcard.self) }
    }
    
    func deleteFlashcard(_ card: Flashcard) async throws {
        try await userDoc.collection("flashcards").document(card.id.uuidString).delete()
    }
    
    func updateFlashcard(_ card: Flashcard) async throws {
        let docRef = userDoc.collection("flashcards").document(card.id.uuidString)
        try docRef.setData(from: card, merge: true)
    }
    
    // MARK: - Drawing Storage
    
    func uploadDrawing(_ data: Data, sessionId: String) async throws {
        let ref = storage.reference().child("users/\(uid)/drawings/\(sessionId).pkdrawing")
        _ = try await ref.putDataAsync(data)
    }
    
    func downloadDrawing(sessionId: String) async throws -> Data? {
        let ref = storage.reference().child("users/\(uid)/drawings/\(sessionId).pkdrawing")
        let maxSize: Int64 = 10 * 1024 * 1024 // 10MB
        return try await ref.data(maxSize: maxSize)
    }
    
    func deleteDrawing(sessionId: String) async throws {
        let ref = storage.reference().child("users/\(uid)/drawings/\(sessionId).pkdrawing")
        try await ref.delete()
    }
}
