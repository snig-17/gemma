//
//  Models.swift
//  gemma
//

import Foundation
import SwiftUI

// MARK: - App Theme

enum AppTheme {
    /// Primary coral/salmon color #ea785c
    static let primary = Color(red: 0.918, green: 0.471, blue: 0.361)
    /// Light gray background #f0f0f0
    static let secondary = Color(red: 0.941, green: 0.941, blue: 0.941)
    /// Darker shade of primary for gradients
    static let primaryDark = Color(red: 0.82, green: 0.38, blue: 0.28)
    /// Lighter shade of primary for highlights/backgrounds
    static let primaryLight = Color(red: 0.95, green: 0.60, blue: 0.50)
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - Tutoring Session

struct TutoringSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var subject: String
    var messages: [ChatMessage]
    var drawingData: Data?
    let createdAt: Date
    var lastModified: Date
    
    init(id: UUID = UUID(), title: String = "New Session", subject: String = "General", messages: [ChatMessage] = [], drawingData: Data? = nil) {
        self.id = id
        self.title = title
        self.subject = subject
        self.messages = messages
        self.drawingData = drawingData
        self.createdAt = Date()
        self.lastModified = Date()
    }
}

// MARK: - User Role (Onboarding)

enum UserRole: String, Codable, CaseIterable {
    case student, mature, gcse, aLevel, uni, other
    
    var displayName: String {
        switch self {
        case .student: "Student"
        case .mature: "Mature"
        case .gcse: "GCSE"
        case .aLevel: "A-Level / Beyond"
        case .uni: "University"
        case .other: "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .student: "graduationcap"
        case .mature: "person.fill"
        case .gcse: "book.fill"
        case .aLevel: "star.fill"
        case .uni: "building.columns"
        case .other: "ellipsis.circle"
        }
    }
}

// MARK: - Avatar Configuration

struct AvatarConfig: Codable, Equatable {
    var skinTone: Int
    var hairStyle: Int
    var hairColor: Int
    var eyeStyle: Int
    var mouthStyle: Int
    var outfitStyle: Int
    var outfitColor: Int
    
    init(skinTone: Int = 2, hairStyle: Int = 0, hairColor: Int = 0,
         eyeStyle: Int = 0, mouthStyle: Int = 0, outfitStyle: Int = 0, outfitColor: Int = 0) {
        self.skinTone = skinTone
        self.hairStyle = hairStyle
        self.hairColor = hairColor
        self.eyeStyle = eyeStyle
        self.mouthStyle = mouthStyle
        self.outfitStyle = outfitStyle
        self.outfitColor = outfitColor
    }
    
    // Palettes
    static let skinTones: [Color] = [
        Color(red: 1.0, green: 0.87, blue: 0.75),
        Color(red: 0.94, green: 0.76, blue: 0.60),
        Color(red: 0.82, green: 0.64, blue: 0.46),
        Color(red: 0.65, green: 0.46, blue: 0.32),
        Color(red: 0.45, green: 0.30, blue: 0.20),
        Color(red: 0.30, green: 0.20, blue: 0.13),
    ]
    
    static let hairColors: [Color] = [
        Color(red: 0.15, green: 0.10, blue: 0.05), // black
        Color(red: 0.40, green: 0.25, blue: 0.12), // dark brown
        Color(red: 0.60, green: 0.35, blue: 0.15), // brown
        Color(red: 0.85, green: 0.55, blue: 0.20), // auburn
        Color(red: 0.95, green: 0.78, blue: 0.30), // blonde
        Color(red: 0.75, green: 0.25, blue: 0.15), // red
        Color(red: 0.45, green: 0.45, blue: 0.50), // grey
        Color(red: 0.55, green: 0.30, blue: 0.70), // purple
    ]
    
    static let outfitColors: [Color] = [
        .blue, .red, .green, .purple, .orange, .pink, .teal, .indigo
    ]
    
    static let hairStyleIcons: [String] = [
        "person.crop.circle", "person.crop.circle.fill", "person.and.background.dotted",
        "figure.stand", "person.fill", "person.crop.square"
    ]
    
    static let eyeStyleIcons: [String] = [
        "eye", "eye.fill", "eye.circle", "eye.circle.fill", "eyeglasses", "sunglasses"
    ]
    
    static let mouthStyleIcons: [String] = [
        "mouth", "mouth.fill", "face.smiling", "face.smiling.inverse"
    ]
    
    static let outfitStyleIcons: [String] = [
        "tshirt", "tshirt.fill", "figure.dress.line.vertical.figure",
        "figure.walk", "figure.run", "figure.stand"
    ]
    
    var skinColor: Color {
        Self.skinTones[safe: skinTone] ?? Self.skinTones[2]
    }
    var hairColorValue: Color {
        Self.hairColors[safe: hairColor] ?? Self.hairColors[0]
    }
    var outfitColorValue: Color {
        Self.outfitColors[safe: outfitColor] ?? Self.outfitColors[0]
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Whiteboard Background

enum WhiteboardBackground: String, Codable, CaseIterable {
    case grid, dotted, lined, plain
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .grid: "grid"
        case .dotted: "circle.grid.3x3"
        case .lined: "line.3.horizontal"
        case .plain: "rectangle"
        }
    }
}

// MARK: - Subject

struct Subject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var sessionCount: Int
    var totalMessages: Int
    
    init(id: UUID = UUID(), name: String, icon: String = "book.fill", sessionCount: Int = 0, totalMessages: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sessionCount = sessionCount
        self.totalMessages = totalMessages
    }
    
    static let defaultSubjects: [Subject] = [
        Subject(name: "Algebra", icon: "function"),
        Subject(name: "Geometry", icon: "triangle"),
        Subject(name: "Physics", icon: "atom"),
        Subject(name: "Chemistry", icon: "flask"),
    ]
}

// MARK: - Gem Tier

enum GemTier: String, Codable, CaseIterable {
    case diamond
    case sapphire
    case emerald
    case ruby
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var subtitle: String {
        switch self {
        case .diamond: "Beginner"
        case .sapphire: "Learner"
        case .emerald: "Scholar"
        case .ruby: "Pro"
        }
    }
    
    var color: Color {
        switch self {
        case .diamond: Color(red: 0.7, green: 0.85, blue: 0.95)
        case .sapphire: Color(red: 0.2, green: 0.4, blue: 0.8)
        case .emerald: Color(red: 0.2, green: 0.75, blue: 0.5)
        case .ruby: Color(red: 0.85, green: 0.15, blue: 0.25)
        }
    }
    
    var icon: String {
        switch self {
        case .diamond: "diamond"
        case .sapphire: "seal"
        case .emerald: "shield"
        case .ruby: "crown"
        }
    }
    
    /// Determine tier from total message count
    static func tier(forMessages count: Int) -> GemTier {
        switch count {
        case 0..<20: .diamond
        case 20..<80: .sapphire
        case 80..<200: .emerald
        default: .ruby
        }
    }
}

// MARK: - Flashcard

struct Flashcard: Identifiable, Codable {
    let id: UUID
    var subject: String
    var front: String
    var back: String
    var createdAt: Date
    var reviewCount: Int
    var lastReviewed: Date?
    
    init(id: UUID = UUID(), subject: String, front: String, back: String) {
        self.id = id
        self.subject = subject
        self.front = front
        self.back = back
        self.createdAt = Date()
        self.reviewCount = 0
        self.lastReviewed = nil
    }
    
    /// Parse [FLASHCARD front:... back:...] tags from an AI response.
    /// Returns the parsed flashcards and the cleaned text with tags removed.
    static func parseFlashcards(from response: String, subject: String) -> ([Flashcard], String) {
        var cleaned = response
        var cards: [Flashcard] = []
        
        // Match [FLASHCARD front:... back:...]
        let pattern = #"\[FLASHCARD\s+front:(.*?)\s+back:(.*?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ([], response)
        }
        
        let nsString = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() {
            let frontRange = match.range(at: 1)
            let backRange = match.range(at: 2)
            
            let front = nsString.substring(with: frontRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let back = nsString.substring(with: backRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !front.isEmpty && !back.isEmpty {
                cards.append(Flashcard(subject: subject, front: front, back: back))
            }
            
            // Remove the tag from cleaned text
            let fullRange = match.range(at: 0)
            cleaned = (cleaned as NSString).replacingCharacters(in: fullRange, with: "")
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cards, cleaned)
    }
}

// MARK: - User Profile

struct UserProfile: Codable {
    var name: String
    var subjects: [Subject]
    var streak: Int
    var lastActiveDate: Date?
    var role: UserRole?
    var avatar: AvatarConfig
    var hasCompletedOnboarding: Bool
    
    init(name: String = "Student", subjects: [Subject] = Subject.defaultSubjects, streak: Int = 0,
         lastActiveDate: Date? = nil, role: UserRole? = nil, avatar: AvatarConfig = AvatarConfig(),
         hasCompletedOnboarding: Bool = false) {
        self.name = name
        self.subjects = subjects
        self.streak = streak
        self.lastActiveDate = lastActiveDate
        self.role = role
        self.avatar = avatar
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    var totalMessages: Int {
        subjects.reduce(0) { $0 + $1.totalMessages }
    }
    
    var gemTier: GemTier {
        GemTier.tier(forMessages: totalMessages)
    }
    
    /// Update streak based on today's activity
    mutating func recordActivity() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastActive = lastActiveDate {
            let lastDay = calendar.startOfDay(for: lastActive)
            let daysDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            if daysDiff == 1 {
                streak += 1
            } else if daysDiff > 1 {
                streak = 1
            }
            // daysDiff == 0: same day, streak unchanged
        } else {
            streak = 1
        }
        
        lastActiveDate = Date()
    }
}


