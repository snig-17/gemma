//
//  WhiteboardView.swift
//  gemma
//

import SwiftUI
import PencilKit

// MARK: - PencilKit Canvas Representable

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = false
        
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - Whiteboard View

struct WhiteboardView: View {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var background: WhiteboardBackground
    let onClear: () -> Void
    let onSnapshot: () -> Void
    let onSave: () -> Void
    let onFinishNote: () -> Void
    
    @State private var showBackgroundPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Label("Whiteboard", systemImage: "pencil.and.scribble")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Background picker button
                Button {
                    showBackgroundPicker.toggle()
                } label: {
                    Image(systemName: background.icon)
                        .font(.subheadline)
                }
                .popover(isPresented: $showBackgroundPicker) {
                    backgroundPickerContent
                }
                
                // Save work
                Button {
                    onSave()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                }
                .tint(.blue)
                
                // Finish note
                Button {
                    onFinishNote()
                } label: {
                    Label("Finish", systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
                .tint(.green)
                
                // Clear
                Button {
                    onClear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline)
                }
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            
            // Canvas
            ZStack {
                backgroundView
                
                CanvasView(canvasView: $canvasView, toolPicker: $toolPicker)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Background Picker
    
    private var backgroundPickerContent: some View {
        VStack(spacing: 12) {
            Text("Background")
                .font(.subheadline.weight(.medium))
            
            HStack(spacing: 12) {
                ForEach(WhiteboardBackground.allCases, id: \.self) { bg in
                    Button {
                        background = bg
                        showBackgroundPicker = false
                    } label: {
                        VStack(spacing: 6) {
                            backgroundThumbnail(bg)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(bg == background ? Color.purple : Color.secondary.opacity(0.3), lineWidth: bg == background ? 2 : 1)
                                )
                            
                            Text(bg.displayName)
                                .font(.caption2)
                                .foregroundStyle(bg == background ? .purple : .secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .presentationCompactAdaptation(.popover)
    }
    
    @ViewBuilder
    private func backgroundThumbnail(_ bg: WhiteboardBackground) -> some View {
        switch bg {
        case .grid:
            MiniGridBackground()
        case .dotted:
            MiniDottedBackground()
        case .lined:
            MiniLinedBackground()
        case .plain:
            Color.white
        }
    }
    
    // MARK: - Dynamic Background
    
    @ViewBuilder
    private var backgroundView: some View {
        switch background {
        case .grid:
            GridBackground()
        case .dotted:
            DottedBackground()
        case .lined:
            LinedBackground()
        case .plain:
            Color.white
        }
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    let spacing: CGFloat = 24
    
    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / spacing)
            let cols = Int(size.width / spacing)
            
            for row in 0...rows {
                let y = CGFloat(row) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 0.5)
            }
            
            for col in 0...cols {
                let x = CGFloat(col) * spacing
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 0.5)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Dotted Background

struct DottedBackground: View {
    let spacing: CGFloat = 24
    
    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / spacing)
            let cols = Int(size.width / spacing)
            
            for row in 0...rows {
                for col in 0...cols {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                    context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.15)))
                }
            }
        }
        .background(Color.white)
    }
}

// MARK: - Lined Background

struct LinedBackground: View {
    let spacing: CGFloat = 32
    
    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / spacing)
            
            for row in 1...rows {
                let y = CGFloat(row) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.blue.opacity(0.12)), lineWidth: 0.5)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Mini Thumbnail Backgrounds

struct MiniGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let rows = Int(size.height / spacing)
            let cols = Int(size.width / spacing)
            for row in 0...rows {
                let y = CGFloat(row) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
            for col in 0...cols {
                let x = CGFloat(col) * spacing
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .background(Color.white)
    }
}

struct MiniDottedBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let rows = Int(size.height / spacing)
            let cols = Int(size.width / spacing)
            for row in 0...rows {
                for col in 0...cols {
                    let rect = CGRect(x: CGFloat(col) * spacing - 1, y: CGFloat(row) * spacing - 1, width: 2, height: 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.2)))
                }
            }
        }
        .background(Color.white)
    }
}

struct MiniLinedBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let rows = Int(size.height / spacing)
            for row in 1...rows {
                let y = CGFloat(row) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.blue.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .background(Color.white)
    }
}
