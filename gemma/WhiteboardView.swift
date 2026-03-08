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
    let background: WhiteboardBackground
    
    // Large virtual canvas size for scrolling
    static let canvasWidth: CGFloat = 2048
    static let canvasHeight: CGFloat = 4096
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = true
        canvasView.backgroundColor = .white
        
        // Enable scrolling and zooming
        canvasView.contentSize = CGSize(width: Self.canvasWidth, height: Self.canvasHeight)
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.bouncesZoom = true
        canvasView.showsVerticalScrollIndicator = true
        canvasView.showsHorizontalScrollIndicator = true
        
        // Add background pattern view behind drawing content
        let bgView = BackgroundPatternView(
            frame: CGRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight),
            background: background
        )
        bgView.tag = 999
        canvasView.insertSubview(bgView, at: 0)
        
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update background pattern when changed
        if let bgView = uiView.viewWithTag(999) as? BackgroundPatternView {
            if bgView.background != background {
                bgView.background = background
                bgView.setNeedsDisplay()
            }
        }
    }
}

// MARK: - UIKit Background Pattern View

class BackgroundPatternView: UIView {
    var background: WhiteboardBackground
    
    init(frame: CGRect, background: WhiteboardBackground) {
        self.background = background
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // Fill white background
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        
        switch background {
        case .grid:
            drawGrid(in: ctx, rect: rect)
        case .dotted:
            drawDotted(in: ctx, rect: rect)
        case .lined:
            drawLined(in: ctx, rect: rect)
        case .plain:
            break
        }
    }
    
    private func drawGrid(in ctx: CGContext, rect: CGRect) {
        let spacing: CGFloat = 24
        ctx.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.1).cgColor)
        ctx.setLineWidth(0.5)
        
        let rows = Int(rect.height / spacing)
        let cols = Int(rect.width / spacing)
        
        for row in 0...rows {
            let y = CGFloat(row) * spacing
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        for col in 0...cols {
            let x = CGFloat(col) * spacing
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: rect.height))
        }
        ctx.strokePath()
    }
    
    private func drawDotted(in ctx: CGContext, rect: CGRect) {
        let spacing: CGFloat = 24
        ctx.setFillColor(UIColor.secondaryLabel.withAlphaComponent(0.15).cgColor)
        
        let rows = Int(rect.height / spacing)
        let cols = Int(rect.width / spacing)
        
        for row in 0...rows {
            for col in 0...cols {
                let x = CGFloat(col) * spacing
                let y = CGFloat(row) * spacing
                ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            }
        }
    }
    
    private func drawLined(in ctx: CGContext, rect: CGRect) {
        let spacing: CGFloat = 32
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        
        let rows = Int(rect.height / spacing)
        for row in 1...rows {
            let y = CGFloat(row) * spacing
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        ctx.strokePath()
    }
}

// MARK: - Whiteboard View

struct WhiteboardView: View {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var background: WhiteboardBackground
    let onClear: () -> Void
    let onSnapshot: () -> Void
    let onSave: () -> Void
    let onExportPDF: () -> URL?
    let onFinishNote: () -> Void
    
    @State private var showBackgroundPicker = false
    @State private var showExportEmpty = false
    
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
                
                // Export PDF
                Button {
                    onSave()
                    if let url = onExportPDF() {
                        presentShareSheet(url: url)
                    } else {
                        showExportEmpty = true
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
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
            CanvasView(canvasView: $canvasView, toolPicker: $toolPicker, background: background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .alert("Nothing to Export", isPresented: $showExportEmpty) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Draw something on the whiteboard first, then try exporting again.")
        }
    }
    
    /// Present UIActivityViewController directly from the root window so it works on iPad
    private func presentShareSheet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        // Walk to the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // iPad requires popover source — anchor to center-top of the screen
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 60, width: 0, height: 0)
            popover.permittedArrowDirections = .up
        }
        
        topVC.present(activityVC, animated: true)
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
                                        .stroke(bg == background ? AppTheme.primary : Color.secondary.opacity(0.3), lineWidth: bg == background ? 2 : 1)
                                )
                            
                            Text(bg.displayName)
                                .font(.caption2)
                                .foregroundStyle(bg == background ? AppTheme.primary : .secondary)
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


