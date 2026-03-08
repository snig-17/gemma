//
//  GemmaAvatarView.swift
//  gemma
//

import SwiftUI
import CoreMotion

struct GemmaAvatarView: View {
    let speechState: SpeechState
    let audioLevel: Float
    
    // Animation state
    @State private var floatOffset: CGFloat = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var isBlinking = false
    @State private var eyeOffset: CGSize = .zero
    @State private var mouthOpen: CGFloat = 0
    @State private var motionManager = CMMotionManager()
    
    // Pulsing circuit dots
    @State private var circuitPulse1: CGFloat = 0.2
    @State private var circuitPulse2: CGFloat = 0.2
    @State private var circuitPulse3: CGFloat = 0.15
    @State private var ventPulse: CGFloat = 0.1
    @State private var gearRotation: Double = 0
    
    // Body colors
    private let bodyColor = AppTheme.primary
    private let bodyHighlight = AppTheme.primaryLight
    private let bodyDark = AppTheme.primaryDark
    private let glowColor = AppTheme.primaryLight
    private let cheekColor = AppTheme.primaryLight
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                // Ambient glow behind character
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [stateColor.opacity(0.15), stateColor.opacity(0.0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.15)
                    .animation(.easeOut(duration: 0.15), value: audioLevel)
                
                // The character
                characterBody
                    .offset(y: floatOffset)
                    .scaleEffect(breatheScale)
            }
            
            // Status label
            VStack(spacing: 8) {
                Text("Gemma")
                    .font(.title.bold())
                
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: speechState)
            }
            
            Spacer()
        }
        .onAppear {
            startAnimations()
            startMotionTracking()
        }
        .onDisappear {
            motionManager.stopDeviceMotionUpdates()
        }
        .onChange(of: speechState) {
            updateMouthAnimation()
        }
        .onChange(of: audioLevel) {
            if speechState == .speaking {
                withAnimation(.easeOut(duration: 0.08)) {
                    mouthOpen = CGFloat(audioLevel)
                }
            }
        }
    }
    
    // MARK: - Character Body
    
    private var characterBody: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let r: CGFloat = 100 // Main sphere radius
            
            // --- Bottom shadow for grounding ---
            let shadowRect = CGRect(x: cx - 60, y: cy + r + 8, width: 120, height: 16)
            context.opacity = 0.06
            context.fill(Ellipse().path(in: shadowRect), with: .color(.black))
            context.opacity = 1.0
            
            // --- Main sphere body ---
            let bodyRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let sphereGradient = Gradient(colors: [glowColor, bodyColor, bodyDark.opacity(0.85)])
            context.fill(
                Circle().path(in: bodyRect),
                with: .radialGradient(
                    sphereGradient,
                    center: CGPoint(x: cx - r * 0.24, y: cy - r * 0.36),
                    startRadius: 0,
                    endRadius: r * 1.3
                )
            )
            
            // --- 3D rim light (subtle dark edge) ---
            let rimGradient = Gradient(colors: [.clear, .clear, Color.black.opacity(0.08)])
            context.fill(
                Circle().path(in: bodyRect),
                with: .radialGradient(
                    rimGradient,
                    center: CGPoint(x: cx + r * 0.4, y: cy + r * 0.5),
                    startRadius: 0,
                    endRadius: r
                )
            )
            
            // --- Top highlight for 3D effect ---
            let highlightRect = CGRect(x: cx - r * 0.35, y: cy - r * 0.6, width: 40, height: 24)
            context.opacity = 0.13
            context.fill(Ellipse().path(in: highlightRect), with: .color(.white))
            context.opacity = 1.0
            
            // --- Robot panel lines ---
            // Horizontal curves
            var panelLine1 = Path()
            panelLine1.move(to: CGPoint(x: cx - r * 0.82, y: cy - r * 0.13))
            panelLine1.addQuadCurve(
                to: CGPoint(x: cx + r * 0.82, y: cy - r * 0.13),
                control: CGPoint(x: cx, y: cy - r * 0.18)
            )
            context.stroke(panelLine1, with: .color(bodyDark.opacity(0.3)), lineWidth: 1)
            
            var panelLine2 = Path()
            panelLine2.move(to: CGPoint(x: cx - r * 0.9, y: cy + r * 0.2))
            panelLine2.addQuadCurve(
                to: CGPoint(x: cx + r * 0.9, y: cy + r * 0.2),
                control: CGPoint(x: cx, y: cy + r * 0.25)
            )
            context.stroke(panelLine2, with: .color(bodyDark.opacity(0.25)), lineWidth: 1)
            
            // Vertical seam
            var seam = Path()
            seam.move(to: CGPoint(x: cx, y: cy - r * 0.96))
            seam.addQuadCurve(
                to: CGPoint(x: cx, y: cy + r * 0.96),
                control: CGPoint(x: cx - 2, y: cy)
            )
            context.stroke(seam, with: .color(bodyDark.opacity(0.15)), lineWidth: 0.8)
            
            // --- Circuit pattern dots (pulsing) ---
            let dotPositions: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (cx - r * 0.5, cy - r * 0.4, 2.5, circuitPulse1),
                (cx + r * 0.5, cy - r * 0.4, 2.5, circuitPulse2),
                (cx - r * 0.6, cy + r * 0.5, 2.0, circuitPulse3),
                (cx + r * 0.6, cy + r * 0.5, 2.0, circuitPulse2),
                (cx, cy + r * 0.75, 2.0, circuitPulse3),
            ]
            for (dx, dy, dr, alpha) in dotPositions {
                let dotRect = CGRect(x: dx - dr, y: dy - dr, width: dr * 2, height: dr * 2)
                context.opacity = Double(alpha)
                context.fill(Circle().path(in: dotRect), with: .color(glowColor))
            }
            context.opacity = 1.0
            
            // --- Panel screws / rivets ---
            let screwPositions: [(CGFloat, CGFloat)] = [
                (cx - r * 0.65, cy),
                (cx + r * 0.65, cy),
            ]
            for (sx, sy) in screwPositions {
                let outerRect = CGRect(x: sx - 3, y: sy - 3, width: 6, height: 6)
                context.stroke(Circle().path(in: outerRect), with: .color(bodyDark.opacity(0.25)), lineWidth: 1)
                let innerRect = CGRect(x: sx - 1, y: sy - 1, width: 2, height: 2)
                context.opacity = 0.2
                context.fill(Circle().path(in: innerRect), with: .color(bodyDark))
                context.opacity = 1.0
            }
            
            // --- Circuit traces (pulsing lines) ---
            var trace1 = Path()
            trace1.move(to: CGPoint(x: cx - r * 0.5, y: cy - r * 0.4))
            trace1.addLine(to: CGPoint(x: cx - r * 0.5, y: cy - r * 0.25))
            trace1.addLine(to: CGPoint(x: cx - r * 0.38, y: cy - r * 0.25))
            context.opacity = Double(circuitPulse1) * 0.8
            context.stroke(trace1, with: .color(glowColor), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var trace2 = Path()
            trace2.move(to: CGPoint(x: cx + r * 0.5, y: cy - r * 0.4))
            trace2.addLine(to: CGPoint(x: cx + r * 0.5, y: cy - r * 0.25))
            trace2.addLine(to: CGPoint(x: cx + r * 0.38, y: cy - r * 0.25))
            context.opacity = Double(circuitPulse2) * 0.8
            context.stroke(trace2, with: .color(glowColor), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var trace3 = Path()
            trace3.move(to: CGPoint(x: cx - r * 0.6, y: cy + r * 0.5))
            trace3.addLine(to: CGPoint(x: cx - r * 0.4, y: cy + r * 0.5))
            trace3.addLine(to: CGPoint(x: cx - r * 0.4, y: cy + r * 0.6))
            context.opacity = Double(circuitPulse3) * 0.7
            context.stroke(trace3, with: .color(glowColor), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var trace4 = Path()
            trace4.move(to: CGPoint(x: cx + r * 0.6, y: cy + r * 0.5))
            trace4.addLine(to: CGPoint(x: cx + r * 0.4, y: cy + r * 0.5))
            trace4.addLine(to: CGPoint(x: cx + r * 0.4, y: cy + r * 0.6))
            context.opacity = Double(circuitPulse2) * 0.7
            context.stroke(trace4, with: .color(glowColor), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            context.opacity = 1.0
            
            // --- Gear-like circles (decorative, around upper sphere) ---
            drawGearCircle(context: context, cx: cx - r * 0.7, cy: cy - r * 0.25, radius: 6, color: bodyDark, rotation: gearRotation)
            drawGearCircle(context: context, cx: cx + r * 0.7, cy: cy - r * 0.25, radius: 6, color: bodyDark, rotation: -gearRotation * 0.8)
            
            // --- Panel lines around eyes ---
            var eyePanel1 = Path()
            eyePanel1.move(to: CGPoint(x: cx - r * 0.65, y: cy - r * 0.22))
            eyePanel1.addLine(to: CGPoint(x: cx - r * 0.55, y: cy - r * 0.22))
            eyePanel1.addLine(to: CGPoint(x: cx - r * 0.55, y: cy - r * 0.17))
            context.stroke(eyePanel1, with: .color(bodyDark.opacity(0.2)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var eyePanel2 = Path()
            eyePanel2.move(to: CGPoint(x: cx + r * 0.65, y: cy - r * 0.22))
            eyePanel2.addLine(to: CGPoint(x: cx + r * 0.55, y: cy - r * 0.22))
            eyePanel2.addLine(to: CGPoint(x: cx + r * 0.55, y: cy - r * 0.17))
            context.stroke(eyePanel2, with: .color(bodyDark.opacity(0.2)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            // === EYES ===
            let eyeSpacing: CGFloat = 45
            let eyeY = cy + r * 0.06
            let leftEyeX = cx - eyeSpacing
            let rightEyeX = cx + eyeSpacing
            let pupilOffsetX = eyeOffset.width
            let pupilOffsetY = eyeOffset.height
            
            if isBlinking {
                // Closed eyes — thin horizontal line (blink)
                var leftBlink = Path()
                leftBlink.move(to: CGPoint(x: leftEyeX - 10, y: eyeY))
                leftBlink.addLine(to: CGPoint(x: leftEyeX + 10, y: eyeY))
                context.opacity = 0.85
                context.stroke(leftBlink, with: .color(Color(white: 0.12)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                
                var rightBlink = Path()
                rightBlink.move(to: CGPoint(x: rightEyeX - 10, y: eyeY))
                rightBlink.addLine(to: CGPoint(x: rightEyeX + 10, y: eyeY))
                context.stroke(rightBlink, with: .color(Color(white: 0.12)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                context.opacity = 1.0
            } else {
                // Open eyes — dark tall ellipses (like the React version)
                let eyeW: CGFloat = 13
                let eyeH: CGFloat = 16
                
                // Left eye
                let leftEyeRect = CGRect(
                    x: leftEyeX - eyeW / 2 + pupilOffsetX,
                    y: eyeY - eyeH / 2 + pupilOffsetY,
                    width: eyeW * 2, height: eyeH * 2
                )
                context.opacity = 0.85
                context.fill(Ellipse().path(in: leftEyeRect), with: .color(Color(white: 0.12)))
                
                // Right eye
                let rightEyeRect = CGRect(
                    x: rightEyeX - eyeW / 2 + pupilOffsetX,
                    y: eyeY - eyeH / 2 + pupilOffsetY,
                    width: eyeW * 2, height: eyeH * 2
                )
                context.fill(Ellipse().path(in: rightEyeRect), with: .color(Color(white: 0.12)))
                context.opacity = 1.0
                
                // Eye highlights (small white dot, upper-left of each eye)
                let shineR: CGFloat = 3.5
                let leftShineRect = CGRect(
                    x: leftEyeX - 5 + pupilOffsetX * 0.5,
                    y: eyeY - 6 + pupilOffsetY * 0.5,
                    width: shineR * 2, height: shineR * 2
                )
                context.opacity = 0.75
                context.fill(Circle().path(in: leftShineRect), with: .color(.white))
                
                let rightShineRect = CGRect(
                    x: rightEyeX - 5 + pupilOffsetX * 0.5,
                    y: eyeY - 6 + pupilOffsetY * 0.5,
                    width: shineR * 2, height: shineR * 2
                )
                context.fill(Circle().path(in: rightShineRect), with: .color(.white))
                context.opacity = 1.0
            }
            
            // === CHEEKS ===
            let cheekY = cy + r * 0.33
            let cheekR: CGFloat = 10
            let leftCheekRect = CGRect(x: cx - r * 0.65 - cheekR, y: cheekY - cheekR, width: cheekR * 2, height: cheekR * 2)
            let rightCheekRect = CGRect(x: cx + r * 0.65 - cheekR, y: cheekY - cheekR, width: cheekR * 2, height: cheekR * 2)
            context.opacity = 0.3
            context.fill(Circle().path(in: leftCheekRect), with: .color(glowColor))
            context.fill(Circle().path(in: rightCheekRect), with: .color(glowColor))
            context.opacity = 1.0
            
            // --- Vent lines (animated opacity) ---
            let ventY = cy + r * 0.63
            // Left vents
            var vent1 = Path()
            vent1.move(to: CGPoint(x: cx - r * 0.3, y: ventY))
            vent1.addLine(to: CGPoint(x: cx - r * 0.17, y: ventY))
            context.opacity = Double(ventPulse) * 2.5
            context.stroke(vent1, with: .color(bodyDark), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var vent2 = Path()
            vent2.move(to: CGPoint(x: cx - r * 0.3, y: ventY + 4))
            vent2.addLine(to: CGPoint(x: cx - r * 0.2, y: ventY + 4))
            context.opacity = Double(ventPulse) * 2.0
            context.stroke(vent2, with: .color(bodyDark), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            // Right vents
            var vent3 = Path()
            vent3.move(to: CGPoint(x: cx + r * 0.17, y: ventY))
            vent3.addLine(to: CGPoint(x: cx + r * 0.3, y: ventY))
            context.opacity = Double(ventPulse) * 2.5
            context.stroke(vent3, with: .color(bodyDark), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            
            var vent4 = Path()
            vent4.move(to: CGPoint(x: cx + r * 0.2, y: ventY + 4))
            vent4.addLine(to: CGPoint(x: cx + r * 0.3, y: ventY + 4))
            context.opacity = Double(ventPulse) * 2.0
            context.stroke(vent4, with: .color(bodyDark), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            context.opacity = 1.0
            
            // === MOUTH ===
            let mouthY = cy + r * 0.38
            
            if speechState == .speaking {
                // Animated open mouth — white filled curve that pulses
                let openAmount = max(4, mouthOpen * 14)
                var speakMouth = Path()
                speakMouth.move(to: CGPoint(x: cx - 10, y: mouthY))
                speakMouth.addQuadCurve(
                    to: CGPoint(x: cx + 10, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY + openAmount)
                )
                speakMouth.closeSubpath()
                context.opacity = 0.4
                context.fill(speakMouth, with: .color(.white))
                context.stroke(speakMouth, with: .color(.white.opacity(0.6)), lineWidth: 2.5)
                context.opacity = 1.0
            } else {
                // Resting smile — small white curve
                var smile = Path()
                smile.move(to: CGPoint(x: cx - 10, y: mouthY))
                smile.addQuadCurve(
                    to: CGPoint(x: cx + 10, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY + 10)
                )
                context.opacity = 0.3
                context.stroke(smile, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                context.opacity = 1.0
            }
            
        }
        .frame(width: 280, height: 280)
        .shadow(color: stateColor.opacity(0.3), radius: 15 + CGFloat(audioLevel) * 20)
        .overlay(alignment: .bottomTrailing) {
            // State indicator badge
            if speechState != .idle {
                Image(systemName: stateIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(stateColor)
                    .clipShape(Circle())
                    .shadow(color: stateColor.opacity(0.5), radius: 6)
                    .offset(x: -30, y: -20)
                    .symbolEffect(.pulse, isActive: speechState == .processing)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: speechState)
    }
    
    // MARK: - Gear Drawing Helper
    
    private func drawGearCircle(context: GraphicsContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, color: Color, rotation: Double) {
        // Draw a dashed circle that appears to rotate via dash offset
        let gearRect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        let dashPattern: [CGFloat] = [2, 2]
        let phase = CGFloat(rotation.truncatingRemainder(dividingBy: 360)) / 360.0 * 4.0
        var gearContext = context
        gearContext.opacity = 0.2
        gearContext.stroke(
            Circle().path(in: gearRect),
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: dashPattern, dashPhase: phase)
        )
    }
    
    // MARK: - Computed Properties
    
    private var stateColor: Color {
        switch speechState {
        case .idle: AppTheme.primary
        case .listening: .blue
        case .processing: AppTheme.primaryDark
        case .speaking: .green
        }
    }
    
    private var stateIcon: String {
        switch speechState {
        case .idle: "sparkle"
        case .listening: "waveform"
        case .processing: "ellipsis"
        case .speaking: "speaker.wave.2.fill"
        }
    }
    
    private var statusText: String {
        switch speechState {
        case .idle: "Tap the mic to talk"
        case .listening: "Listening..."
        case .processing: "Thinking..."
        case .speaking: "Speaking..."
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Floating bob
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            floatOffset = -10
        }
        
        // Breathing scale
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            breatheScale = 1.03
        }
        
        // Blinking loop
        startBlinkLoop()
        
        // Circuit pulse animations
        startCircuitPulse()
        
        // Gear rotation
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            gearRotation = 360
        }
    }
    
    private func startCircuitPulse() {
        // Pulse group 1
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            circuitPulse1 = 0.6
        }
        // Pulse group 2 (offset)
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(0.5)) {
            circuitPulse2 = 0.6
        }
        // Pulse group 3 (slower)
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(1.0)) {
            circuitPulse3 = 0.5
        }
        // Vent pulse
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            ventPulse = 0.3
        }
    }
    
    private func startBlinkLoop() {
        let delay = Double.random(in: 2.5...5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.08)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.08)) {
                    isBlinking = false
                }
                startBlinkLoop()
            }
        }
    }
    
    private func updateMouthAnimation() {
        if speechState != .speaking {
            withAnimation(.easeOut(duration: 0.2)) {
                mouthOpen = 0
            }
        }
    }
    
    // MARK: - Motion Tracking (Eye Follow)
    
    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let attitude = motion?.attitude else { return }
            
            let rollOffset = CGFloat(attitude.roll) * 3.0
            let pitchOffset = CGFloat(attitude.pitch - 0.8) * 2.0
            
            let clampedX = max(-3, min(3, rollOffset))
            let clampedY = max(-2, min(2, pitchOffset))
            
            withAnimation(.easeOut(duration: 0.1)) {
                eyeOffset = CGSize(width: clampedX, height: clampedY)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        GemmaAvatarView(speechState: .idle, audioLevel: 0.0)
        
        GemmaAvatarView(speechState: .speaking, audioLevel: 0.5)
    }
    .background(Color(uiColor: .systemBackground))
}
