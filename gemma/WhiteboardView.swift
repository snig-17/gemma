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
    let onClear: () -> Void
    let onSnapshot: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Label("Whiteboard", systemImage: "pencil.and.scribble")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
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
                GridBackground()
                
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
