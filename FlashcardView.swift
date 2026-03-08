//
//  FlashcardView.swift
//  gemma
//

import SwiftUI

struct FlashcardView: View {
    let flashcards: [Flashcard]
    let onDelete: (Flashcard) -> Void
    let onMarkReviewed: (Flashcard) -> Void
    
    @State private var selectedSubject: String? = nil
    @State private var currentIndex = 0
    @Environment(\.dismiss) private var dismiss
    
    private var filteredCards: [Flashcard] {
        if let subject = selectedSubject {
            return flashcards.filter { $0.subject == subject }
        }
        return flashcards
    }
    
    private var subjects: [String] {
        Array(Set(flashcards.map(\.subject))).sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            if filteredCards.isEmpty {
                emptyState
            } else {
                // Subject filter chips
                if subjects.count > 1 {
                    subjectFilters
                }
                
                // Card carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                        FlipCard(
                            card: card,
                            onDelete: {
                                onDelete(card)
                                if currentIndex >= filteredCards.count - 1 {
                                    currentIndex = max(0, filteredCards.count - 2)
                                }
                            },
                            onMarkReviewed: { onMarkReviewed(card) }
                        )
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Card counter
                Text("\(min(currentIndex + 1, filteredCards.count)) of \(filteredCards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tricky Concepts")
                    .font(.title2.bold())
                Text("\(flashcards.count) flashcard\(flashcards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(AppTheme.primary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Subject Filters
    
    private var subjectFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedSubject == nil) {
                    selectedSubject = nil
                    currentIndex = 0
                }
                
                ForEach(subjects, id: \.self) { subject in
                    FilterChip(label: subject, isSelected: selectedSubject == subject) {
                        selectedSubject = subject
                        currentIndex = 0
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No flashcards yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("When you struggle with a concept during tutoring, Gemma will create a flashcard for you to review later.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

// MARK: - Flip Card

private struct FlipCard: View {
    let card: Flashcard
    let onDelete: () -> Void
    let onMarkReviewed: () -> Void
    
    @State private var isFlipped = false
    
    var body: some View {
        ZStack {
            // Front
            cardFace(isFront: true)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
            
            // Back
            cardFace(isFront: false)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0)
                )
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.5)) {
                isFlipped.toggle()
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func cardFace(isFront: Bool) -> some View {
        VStack(spacing: 16) {
            // Subject tag
            HStack {
                Text(card.subject)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
                
                if !isFront {
                    // Review count badge
                    if card.reviewCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Reviewed \(card.reviewCount)x")
                                .font(.caption2)
                        }
                        .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            // Content
            VStack(spacing: 8) {
                if isFront {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.primary.opacity(0.6))
                    
                    Text(card.front)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "lightbulb.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    
                    Text(card.back)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
            
            // Bottom hint / action
            if isFront {
                Text("Tap to reveal answer")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    onMarkReviewed()
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isFlipped = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                        Text("Got it")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppTheme.primary)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.3), AppTheme.primaryLight.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.primary : Color(uiColor: .systemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }
}

#Preview {
    FlashcardView(
        flashcards: [
            Flashcard(subject: "Algebra", front: "What is the quadratic formula?", back: "x = (-b ± √(b²-4ac)) / 2a"),
            Flashcard(subject: "Algebra", front: "What does FOIL stand for?", back: "First, Outer, Inner, Last — a method for multiplying two binomials"),
            Flashcard(subject: "Physics", front: "What is Newton's second law?", back: "Force equals mass times acceleration: F = ma"),
        ],
        onDelete: { _ in },
        onMarkReviewed: { _ in }
    )
}
