//
//  gemmaApp.swift
//  gemma
//
//  Created by Snigdha Tiwari  on 07/03/2026.
//

import SwiftUI
import Firebase

@main
struct gemmaApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Root View (Navigation Controller)

struct RootView: View {
    @State private var firebaseService = FirebaseService.shared
    @State private var profile = UserProfile()
    @State private var activeSubject: Subject?
    @State private var flashcards: [Flashcard] = []
    @State private var hasLoadedData = false
    
    var body: some View {
        Group {
            if firebaseService.isLoading {
                // Splash / loading screen
                VStack(spacing: 16) {
                    Image("GemmaLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            } else if !firebaseService.isAuthenticated {
                AuthView()
            } else if !profile.hasCompletedOnboarding {
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
                        Task { try? await firebaseService.deleteFlashcard(card) }
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
        .task {
            firebaseService.listenToAuthState()
        }
        .onChange(of: firebaseService.isAuthenticated) { _, isAuth in
            if isAuth {
                Task { await loadUserData() }
            } else {
                // Reset state on sign out
                profile = UserProfile()
                flashcards = []
                activeSubject = nil
                hasLoadedData = false
            }
        }
    }
    
    // MARK: - Firebase Persistence
    
    private func loadUserData() async {
        guard !hasLoadedData else { return }
        do {
            if let loadedProfile = try await firebaseService.loadProfile() {
                await MainActor.run { profile = loadedProfile }
            }
            let loadedFlashcards = try await firebaseService.loadFlashcards()
            await MainActor.run {
                flashcards = loadedFlashcards
                hasLoadedData = true
            }
        } catch {
            print("[Firebase] Failed to load user data: \(error.localizedDescription)")
            await MainActor.run { hasLoadedData = true }
        }
    }
    
    private func saveProfile() {
        Task { try? await firebaseService.saveProfile(profile) }
    }
    
    private func saveFlashcards() {
        Task { try? await firebaseService.saveFlashcards(flashcards) }
    }
}

