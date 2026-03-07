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
                onEndSession: { updatedSubject in
                    // Update subject stats
                    if let index = profile.subjects.firstIndex(where: { $0.id == updatedSubject.id }) {
                        profile.subjects[index] = updatedSubject
                    }
                    profile.recordActivity()
                    saveProfile()
                    activeSubject = nil
                }
            )
            .transition(.move(edge: .trailing))
        } else {
            LandingPageView(
                profile: $profile,
                onStartSession: { subject in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeSubject = subject
                    }
                },
                onSaveProfile: {
                    saveProfile()
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
    
    init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_profile.json")
        
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            _profile = State(initialValue: decoded)
        }
    }
}

