//
//  OnboardingView.swift
//  gemma
//

import SwiftUI

struct OnboardingView: View {
    @Binding var profile: UserProfile
    var onComplete: () -> Void
    
    @State private var currentPage = 0
    @State private var selectedRole: UserRole?
    @State private var userName = ""
    @State private var selectedSubjects: Set<String> = []
    @State private var customSubjectName = ""
    @State private var showAddCustom = false
    
    private let defaultSubjectOptions = [
        ("Algebra", "function"),
        ("Geometry", "triangle"),
        ("Physics", "atom"),
        ("Chemistry", "flask"),
        ("Biology", "leaf"),
        ("English", "text.book.closed"),
        ("History", "clock"),
        ("Computer Science", "desktopcomputer"),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentPage) {
                rolePage.tag(0)
                avatarPage.tag(1)
                subjectsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            
            // Bottom bar
            bottomBar
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Page 1: Role Selection
    
    private var rolePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Welcome to gemma")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("What best describes you?")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(UserRole.allCases, id: \.self) { role in
                    Button {
                        selectedRole = role
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: role.icon)
                                .font(.title2)
                            Text(role.displayName)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            selectedRole == role
                            ? Color.purple.opacity(0.15)
                            : Color(uiColor: .systemBackground)
                        )
                        .foregroundStyle(selectedRole == role ? .purple : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedRole == role ? Color.purple : Color.secondary.opacity(0.2), lineWidth: selectedRole == role ? 2 : 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Page 2: Name & Avatar
    
    private var avatarPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Create Your Avatar")
                    .font(.title2.bold())
                    .padding(.top, 24)
                
                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    TextField("Enter your name", text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                .padding(.horizontal, 40)
                
                // Avatar builder
                AvatarBuilderView(avatar: $profile.avatar) {
                    // Done handled by next button
                }
            }
        }
    }
    
    // MARK: - Page 3: Subject Selection
    
    private var subjectsPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Pick Your Subjects")
                    .font(.title2.bold())
                    .padding(.top, 24)
                
                Text("Choose what you'd like to study")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(defaultSubjectOptions, id: \.0) { name, icon in
                        Button {
                            if selectedSubjects.contains(name) {
                                selectedSubjects.remove(name)
                            } else {
                                selectedSubjects.insert(name)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon)
                                    .font(.body)
                                    .frame(width: 32)
                                
                                Text(name)
                                    .font(.subheadline.weight(.medium))
                                
                                Spacer()
                                
                                if selectedSubjects.contains(name) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                selectedSubjects.contains(name)
                                ? Color.purple.opacity(0.1)
                                : Color(uiColor: .systemBackground)
                            )
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        selectedSubjects.contains(name) ? Color.purple.opacity(0.4) : Color.secondary.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Add custom subject
                Button {
                    showAddCustom = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Custom Subject")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                }
                .padding(.top, 8)
            }
            .padding(.bottom, 80)
        }
        .alert("Add Subject", isPresented: $showAddCustom) {
            TextField("Subject name", text: $customSubjectName)
            Button("Add") {
                let name = customSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    selectedSubjects.insert(name)
                }
                customSubjectName = ""
            }
            Button("Cancel", role: .cancel) {
                customSubjectName = ""
            }
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.purple : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button {
                        withAnimation {
                            currentPage -= 1
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                }
                
                Spacer()
                
                if currentPage < 2 {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        finishOnboarding()
                    } label: {
                        HStack {
                            Text("Get Started")
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Finish
    
    private func finishOnboarding() {
        // Save role
        profile.role = selectedRole
        
        // Save name
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            profile.name = name
        }
        
        // Save subjects
        if !selectedSubjects.isEmpty {
            profile.subjects = selectedSubjects.map { name in
                let icon = defaultSubjectOptions.first(where: { $0.0 == name })?.1 ?? "book.fill"
                return Subject(name: name, icon: icon)
            }
        }
        
        profile.hasCompletedOnboarding = true
        onComplete()
    }
}

#Preview {
    OnboardingView(profile: .constant(UserProfile())) {
        // complete
    }
}
