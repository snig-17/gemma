//
//  Models.swift
//  gemma
//

import Foundation
import SwiftUI

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

// MARK: - User Profile

struct UserProfile: Codable {
    var name: String
    var subjects: [Subject]
    var streak: Int
    var lastActiveDate: Date?
    
    init(name: String = "Student", subjects: [Subject] = Subject.defaultSubjects, streak: Int = 0, lastActiveDate: Date? = nil) {
        self.name = name
        self.subjects = subjects
        self.streak = streak
        self.lastActiveDate = lastActiveDate
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
