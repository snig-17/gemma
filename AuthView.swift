//
//  AuthView.swift
//  gemma
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Logo
            Image("GemmaLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            
            Spacer()
                .frame(height: 32)
            
            // Tagline
            Text("Your AI Tutor")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Sign in button
            VStack(spacing: 16) {
                if isSigningIn {
                    ProgressView("Signing in...")
                        .padding()
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        let hashedNonce = FirebaseService.shared.generateNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = hashedNonce
                    } onCompletion: { result in
                        handleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .frame(maxWidth: 320)
                    .cornerRadius(12)
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 60)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    private func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid credential type"
                return
            }
            isSigningIn = true
            errorMessage = nil
            
            Task {
                do {
                    try await FirebaseService.shared.signInWithApple(credential: appleCredential)
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isSigningIn = false
                    }
                }
            }
            
        case .failure(let error):
            // Don't show error for user cancellation
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AuthView()
}
