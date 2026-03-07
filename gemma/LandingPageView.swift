//
//  LandingPageView.swift
//  gemma
//

import SwiftUI

struct LandingPageView: View {
    @Binding var profile: UserProfile
    let onStartSession: (Subject) -> Void
    let onSaveProfile: () -> Void
    
    @State private var showAddSubject = false
    @State private var newSubjectName = ""
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var showAvatarBuilder = false
    @State private var subjectToDelete: Subject?
    @State private var showDeleteConfirm = false
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            if isLandscape {
                HStack(spacing: 0) {
                    // Left: Main content
                    mainContent
                        .frame(maxWidth: .infinity)
                    
                    // Right: Profile card
                    profileCard
                        .frame(width: 280)
                        .padding(.trailing, 24)
                        .padding(.vertical, 24)
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        profileCard
                            .frame(maxWidth: 320)
                        
                        mainContent
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("Add Subject", isPresented: $showAddSubject) {
            TextField("Subject name", text: $newSubjectName)
            Button("Add") { addSubject() }
            Button("Cancel", role: .cancel) { newSubjectName = "" }
        }
        .alert("Edit Name", isPresented: $showEditName) {
            TextField("Your name", text: $editedName)
            Button("Save") {
                profile.name = editedName
                onSaveProfile()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAvatarBuilder) {
            NavigationStack {
                AvatarBuilderView(avatar: $profile.avatar) {
                    showAvatarBuilder = false
                    onSaveProfile()
                }
                .navigationTitle("Edit Avatar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showAvatarBuilder = false
                        }
                    }
                }
            }
        }
        .alert("Delete Subject?", isPresented: $showDeleteConfirm) {
            Button("Delete Forever", role: .destructive) {
                if let subject = subjectToDelete,
                   let index = profile.subjects.firstIndex(where: { $0.id == subject.id }) {
                    profile.subjects.remove(at: index)
                    onSaveProfile()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this subject and its stats. This cannot be undone.")
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("gemma")
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Your AI Tutor")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Streak badge
                streakBadge
            }
            .padding(.horizontal, 24)
            
            // Greeting
            Text("What shall we study, \(profile.name)?")
                .font(.title3.weight(.medium))
                .padding(.horizontal, 24)
            
            // Subject cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(profile.subjects) { subject in
                        SubjectCard(subject: subject, gemColor: profile.gemTier.color) {
                            onStartSession(subject)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                subjectToDelete = subject
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash")
                            }
                        }
                    }
                    
                    // Add subject card
                    AddSubjectCard {
                        showAddSubject = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Gem tier progress
            gemTierProgress
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
    
    // MARK: - Streak Badge
    
    private var streakBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("\(profile.streak)")
                .font(.headline.monospacedDigit())
            Text("day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
    }
    
    // MARK: - Profile Card
    
    private var profileCard: some View {
        VStack(spacing: 16) {
            // Avatar (tap to customise)
            Button {
                showAvatarBuilder = true
            } label: {
                AvatarView(config: profile.avatar, size: 90)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.purple)
                            .background(Circle().fill(.white).padding(2))
                    }
            }
            
            // Name
            Button {
                editedName = profile.name
                showEditName = true
            } label: {
                HStack(spacing: 4) {
                    Text(profile.name)
                        .font(.title3.weight(.semibold))
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            
            // Gem tier
            HStack(spacing: 8) {
                Image(systemName: profile.gemTier.icon)
                    .foregroundStyle(profile.gemTier.color)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.gemTier.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(profile.gemTier.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(profile.gemTier.color.opacity(0.1))
            .clipShape(Capsule())
            
            Divider()
                .padding(.horizontal, 24)
            
            // Stats
            HStack(spacing: 24) {
                StatItem(value: "\(profile.totalMessages)", label: "Messages")
                StatItem(value: "\(profile.subjects.reduce(0) { $0 + $1.sessionCount })", label: "Sessions")
                StatItem(value: "\(profile.streak)", label: "Streak")
            }
            
            // Subject bar chart
            if profile.subjects.contains(where: { $0.totalMessages > 0 }) {
                Divider()
                    .padding(.horizontal, 24)
                
                SubjectBarChart(subjects: profile.subjects)
            }
        }
        .padding(24)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
    
    // MARK: - Gem Tier Progress
    
    private var gemTierProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Revision Rank")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 0) {
                ForEach(GemTier.allCases, id: \.self) { tier in
                    HStack(spacing: 4) {
                        Image(systemName: tier.icon)
                            .font(.caption2)
                        Text(tier.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(tier == profile.gemTier ? tier.color : .secondary.opacity(0.5))
                    .fontWeight(tier == profile.gemTier ? .bold : .regular)
                    
                    if tier != .ruby {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.3))
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Actions
    
    private func addSubject() {
        let name = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let subject = Subject(name: name, icon: "book.fill")
        profile.subjects.append(subject)
        newSubjectName = ""
        onSaveProfile()
    }
}

// MARK: - Subject Card

struct SubjectCard: View {
    let subject: Subject
    let gemColor: Color
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: subject.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text(subject.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("\(subject.sessionCount) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack {
                    Text("Start")
                        .font(.caption.weight(.medium))
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(.purple)
            }
            .padding(16)
            .frame(width: 150, height: 180)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Subject Card

struct AddSubjectCard: View {
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.purple.opacity(0.4))
                
                Text("Add Subject")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subject Bar Chart

struct SubjectBarChart: View {
    let subjects: [Subject]
    
    private var maxMessages: Int {
        subjects.map(\.totalMessages).max() ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Study Time")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            ForEach(subjects.filter({ $0.totalMessages > 0 })) { subject in
                HStack(spacing: 8) {
                    Text(subject.name)
                        .font(.caption2)
                        .frame(width: 60, alignment: .trailing)
                    
                    GeometryReader { geo in
                        let fraction = maxMessages > 0 ? CGFloat(subject.totalMessages) / CGFloat(maxMessages) : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * fraction, 4))
                    }
                    .frame(height: 12)
                    
                    Text("\(subject.totalMessages)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
            }
        }
    }
}
