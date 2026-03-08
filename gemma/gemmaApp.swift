//
//  gemmaApp.swift
//  gemma
//
//  Created by Snigdha Tiwari  on 07/03/2026.
//

import SwiftUI

@main
struct gemmaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Root View (Navigation Controller)

struct RootView: View {
    @State private var profile = UserProfile()
    @State private var activeSubject: Subject?
    @State private var flashcards: [Flashcard] = []
    
    var body: some View {
        if !profile.hasCompletedOnboarding {
            OnboardingView(profile: $profile) {
                saveProfile()
            }
            .transition(.move(edge: .trailing))
        } else if let subject = activeSubject {
            ContentView(
                subject: subject,
                profile: $profile,
                flashcards: $flashcards,
                onEndSession: { updatedSubject, updatedFlashcards in
                    // Update subject stats
                    if let index = profile.subjects.firstIndex(where: { $0.id == updatedSubject.id }) {
                        profile.subjects[index] = updatedSubject
                    }
                    // Merge flashcards from session
                    flashcards = updatedFlashcards
                    saveFlashcards()
                    profile.recordActivity()
                    saveProfile()
                    activeSubject = nil
                }
            )
            .transition(.move(edge: .trailing))
        } else {
            LandingPageView(
                profile: $profile,
                flashcards: flashcards,
                onStartSession: { subject in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeSubject = subject
                    }
                },
                onSaveProfile: {
                    saveProfile()
                },
                onDeleteFlashcard: { card in
                    flashcards.removeAll { $0.id == card.id }
                    saveFlashcards()
                },
                onMarkReviewed: { card in
                    if let index = flashcards.firstIndex(where: { $0.id == card.id }) {
                        flashcards[index].reviewCount += 1
                        flashcards[index].lastReviewed = Date()
                        saveFlashcards()
                    }
                }
            )
            .transition(.move(edge: .leading))
        }
    }
    
    // MARK: - Persistence
    
    private var profileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_profile.json")
    }
    
    private func saveProfile() {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: profileURL)
        } catch {
            print("Failed to save profile: \(error)")
        }
    }
    
    private var flashcardsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("flashcards.json")
    }
    
    private func saveFlashcards() {
        do {
            let data = try JSONEncoder().encode(flashcards)
            try data.write(to: flashcardsURL)
        } catch {
            print("Failed to save flashcards: \(error)")
        }
    }
    
    init() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Load profile
        let profilePath = docsDir.appendingPathComponent("user_profile.json")
        if FileManager.default.fileExists(atPath: profilePath.path),
           let data = try? Data(contentsOf: profilePath),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            _profile = State(initialValue: decoded)
        }
        
        // Load flashcards
        let flashcardsPath = docsDir.appendingPathComponent("flashcards.json")
        if FileManager.default.fileExists(atPath: flashcardsPath.path),
           let data = try? Data(contentsOf: flashcardsPath),
           let decoded = try? JSONDecoder().decode([Flashcard].self, from: data) {
            _flashcards = State(initialValue: decoded)
        }
    }
}

