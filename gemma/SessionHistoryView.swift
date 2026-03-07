//
//  SessionHistoryView.swift
//  gemma
//

import SwiftUI

struct SessionHistoryView: View {
    let sessions: [TutoringSession]
    let currentSessionId: UUID?
    let onSelect: (TutoringSession) -> Void
    let onNew: () -> Void
    let onDelete: (IndexSet) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Sessions", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    onNew()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No sessions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == currentSessionId
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(session)
                        }
                        .listRowBackground(
                            session.id == currentSessionId
                            ? Color.purple.opacity(0.1)
                            : Color.clear
                        )
                    }
                    .onDelete(perform: onDelete)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: TutoringSession
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(.purple)
                        .frame(width: 8, height: 8)
                }
            }
            
            HStack {
                Text("\(session.messages.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if session.drawingData != nil {
                    Image(systemName: "pencil.tip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(session.lastModified, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
