//
//  GemmaAvatarView.swift
//  gemma
//

import SwiftUI

struct GemmaAvatarView: View {
    let speechState: SpeechState
    let audioLevel: Float
    
    @State private var breatheScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                // Ambient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [stateColor.opacity(0.2), stateColor.opacity(0.0)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.15)
                    .animation(.easeOut(duration: 0.15), value: audioLevel)
                
                // Outer ring 3
                Circle()
                    .stroke(stateColor.opacity(0.1), lineWidth: 1)
                    .frame(width: 240, height: 240)
                    .scaleEffect(breatheScale * (1.0 + CGFloat(audioLevel) * 0.2))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
                
                // Outer ring 2
                Circle()
                    .stroke(stateColor.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 200, height: 200)
                    .scaleEffect(breatheScale * (1.0 + CGFloat(audioLevel) * 0.15))
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
                
                // Inner ring
                Circle()
                    .stroke(stateColor.opacity(0.25), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(breatheScale)
                
                // Core orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                stateColor.opacity(0.9),
                                stateColor.opacity(0.6),
                                stateColor.opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: stateColor.opacity(0.6), radius: 30 + CGFloat(audioLevel) * 20)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.12)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
                
                // Glass overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.12)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
                
                // Sparkle icon
                Image(systemName: stateIcon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: speechState == .processing)
            }
            
            // Status label
            VStack(spacing: 8) {
                Text("Gemma")
                    .font(.title.bold())
                
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: speechState)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var stateColor: Color {
        switch speechState {
        case .idle: .purple
        case .listening: .blue
        case .processing: .orange
        case .speaking: .green
        }
    }
    
    private var stateIcon: String {
        switch speechState {
        case .idle: "sparkle"
        case .listening: "waveform"
        case .processing: "ellipsis"
        case .speaking: "sparkle"
        }
    }
    
    private var statusText: String {
        switch speechState {
        case .idle: "Tap the mic to talk"
        case .listening: "Listening..."
        case .processing: "Thinking..."
        case .speaking: "Speaking..."
        }
    }
    
    // MARK: - Animations
    
    private func startBreathing() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breatheScale = 1.06
        }
    }
}

// MARK: - Preview

#Preview {
    GemmaAvatarView(speechState: .idle, audioLevel: 0.0)
        .background(Color.black.opacity(0.05))
}
