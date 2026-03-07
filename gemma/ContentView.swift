//
//  ContentView.swift
//  gemma
//

import SwiftUI
import PencilKit

struct ContentView: View {
    let subject: Subject
    @Binding var profile: UserProfile
    var onEndSession: (Subject) -> Void
    
    @State private var viewModel: TutoringViewModel
    @State private var showSessionSheet = false
    @State private var selectedTab = 0
    
    init(subject: Subject, profile: Binding<UserProfile>, onEndSession: @escaping (Subject) -> Void) {
        self.subject = subject
        self._profile = profile
        self.onEndSession = onEndSession
        self._viewModel = State(initialValue: TutoringViewModel(subject: subject))
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isWide = geometry.size.width >= 600
            
            if isWide && isLandscape {
                landscapeLayout
            } else if isWide {
                portraitLayout
            } else {
                compactLayout
            }
        }
        .onAppear {
            viewModel.speechService.requestPermissions()
        }
        .sheet(isPresented: $showSessionSheet) {
            NavigationStack {
                SessionHistoryView(
                    sessions: viewModel.sessions,
                    currentSessionId: viewModel.currentSession.id,
                    onSelect: { session in
                        viewModel.selectSession(session)
                        showSessionSheet = false
                    },
                    onNew: {
                        viewModel.createNewSession()
                        showSessionSheet = false
                    },
                    onDelete: { offsets in
                        viewModel.deleteSession(at: offsets)
                    }
                )
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showSessionSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - iPad Landscape (Side-by-Side)
    
    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            callPanel
                .frame(maxWidth: .infinity)
            
            Divider()
            
            whiteboardPanel
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            historyButton
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
    }
    
    // MARK: - iPad Portrait (Stacked)
    
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            whiteboardPanel
                .frame(maxHeight: .infinity)
            
            Divider()
            
            callPanel
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            historyButton
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Compact (Tab-based)
    
    private var compactLayout: some View {
        TabView(selection: $selectedTab) {
            callPanel
                .tabItem {
                    Label("Call", systemImage: "phone.fill")
                }
                .tag(0)
            
            whiteboardPanel
                .tabItem {
                    Label("Whiteboard", systemImage: "pencil.tip.crop.circle")
                }
                .tag(1)
        }
        .tint(.purple)
        .overlay(alignment: .topLeading) {
            backButton
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            historyButton
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Panels
    
    private var callPanel: some View {
        GemmaCallView(
            messages: $viewModel.messages,
            isLoading: $viewModel.isLoading,
            speechService: viewModel.speechService,
            onSendText: { text, imageData in
                viewModel.sendMessage(text, imageData: imageData)
            },
            onShareWhiteboard: {
                viewModel.sendWhiteboardSnapshot()
            },
            onNewSession: {
                viewModel.createNewSession()
            }
        )
    }
    
    private var whiteboardPanel: some View {
        WhiteboardView(
            canvasView: $viewModel.canvasView,
            toolPicker: $viewModel.toolPicker,
            onClear: {
                viewModel.clearCanvas()
            },
            onSnapshot: {}
        )
    }
    
    // MARK: - Toolbar Buttons
    
    private var backButton: some View {
        Button {
            viewModel.speechService.stopSpeaking()
            viewModel.speechService.stopListening()
            onEndSession(viewModel.updatedSubject)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("End")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
    
    private var historyButton: some View {
        Button {
            showSessionSheet = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.body)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

#Preview {
    ContentView(
        subject: Subject(name: "Algebra", icon: "function"),
        profile: .constant(UserProfile()),
        onEndSession: { _ in }
    )
}
