//
//  GemmaCallView.swift
//  gemma
//

import SwiftUI

struct GemmaCallView: View {
    @Binding var messages: [ChatMessage]
    @Binding var isLoading: Bool
    let speechService: SpeechService
    let onSendText: (String, Data?) -> Void
    let onShareWhiteboard: () -> Void
    let onNewSession: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            callHeader
            
            Divider()
            
            // Main content
            ZStack {
                // Background
                Color(uiColor: .systemBackground)
                
                VStack(spacing: 0) {
                    // Avatar area
                    GemmaAvatarView(
                        speechState: speechService.speechState,
                        audioLevel: speechService.audioLevel
                    )
                    .frame(maxHeight: .infinity)
                    
                    // Live transcript overlay
                    transcriptOverlay
                    
                    // Compact conversation log
                    conversationLog
                    
                    // Control bar
                    controlBar
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var callHeader: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Gemma")
                    .font(.headline)
                Text("AI Tutor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            
            // Call duration / session indicator
            Text(callDurationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    private var statusDotColor: Color {
        switch speechService.speechState {
        case .idle: .gray
        case .listening: .blue
        case .processing: AppTheme.primaryDark
        case .speaking: .green
        }
    }
    
    private var callDurationText: String {
        "\(messages.count) exchanges"
    }
    
    // MARK: - Transcript Overlay
    
    private var transcriptOverlay: some View {
        Group {
            if !speechService.liveTranscript.isEmpty || speechService.speechState == .listening {
                HStack(spacing: 8) {
                    // Indicator
                    Circle()
                        .fill(transcriptIndicatorColor)
                        .frame(width: 6, height: 6)
                    
                    Text(transcriptDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .animation(.easeInOut(duration: 0.2), value: speechService.liveTranscript)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
    
    private var transcriptIndicatorColor: Color {
        switch speechService.speechState {
        case .listening: .blue
        case .speaking: .green
        default: .secondary
        }
    }
    
    private var transcriptDisplayText: String {
        if speechService.liveTranscript.isEmpty && speechService.speechState == .listening {
            return "Listening..."
        }
        return speechService.liveTranscript
    }
    
    // MARK: - Conversation Log
    
    private var conversationLog: some View {
        Group {
            if !messages.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Conversation")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(messages) { message in
                                    ConversationLogEntry(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 120)
                        .onChange(of: messages.count) {
                            if let last = messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
            }
        }
    }
    
    // MARK: - Control Bar
    
    private var controlBar: some View {
        HStack(spacing: 40) {
            // Share whiteboard
            ControlButton(
                icon: "rectangle.and.pencil.and.ellipsis",
                label: "Board",
                color: AppTheme.primary
            ) {
                onShareWhiteboard()
            }
            
            // Mic button (large, center)
            micButton
            
            // New session
            ControlButton(
                icon: "plus.circle",
                label: "New",
                color: .secondary
            ) {
                onNewSession()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial)
    }
    
    private var micButton: some View {
        Button {
            handleMicTap()
        } label: {
            ZStack {
                Circle()
                    .fill(micButtonColor)
                    .frame(width: 72, height: 72)
                    .shadow(color: micButtonColor.opacity(0.4), radius: 8)
                
                // Pulse ring when listening
                if speechService.speechState == .listening {
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 2)
                        .frame(width: 86, height: 86)
                        .scaleEffect(1.0 + CGFloat(speechService.audioLevel) * 0.2)
                        .animation(.easeOut(duration: 0.1), value: speechService.audioLevel)
                }
                
                Image(systemName: micIcon)
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
        .disabled(speechService.speechState == .processing)
    }
    
    private var micButtonColor: Color {
        switch speechService.speechState {
        case .idle: AppTheme.primary
        case .listening: .red
        case .processing: .gray
        case .speaking: AppTheme.primaryDark
        }
    }
    
    private var micIcon: String {
        switch speechService.speechState {
        case .idle: "mic.fill"
        case .listening: "mic.fill"
        case .processing: "ellipsis"
        case .speaking: "speaker.wave.2.fill"
        }
    }
    
    private func handleMicTap() {
        switch speechService.speechState {
        case .idle:
            speechService.startListening()
        case .listening:
            speechService.stopListening()
        case .processing:
            break
        case .speaking:
            speechService.stopSpeaking()
            speechService.startListening()
        }
    }
    
    // MARK: - Error Display
    
    private var errorOverlay: some View {
        Group {
            if let error = speechService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

// MARK: - Conversation Log Entry

struct ConversationLogEntry: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.isUser ? "person.fill" : "sparkle")
                .font(.caption2)
                .foregroundStyle(message.isUser ? .blue : AppTheme.primary)
                .frame(width: 16)
            
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
            
            Spacer()
            
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.15))
                    .clipShape(Circle())
                
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
    }
}
