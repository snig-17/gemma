//
//  AvatarView.swift
//  gemma
//

import SwiftUI

struct AvatarView: View {
    let config: AvatarConfig
    var size: CGFloat = 80
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [config.outfitColorValue.opacity(0.3), config.outfitColorValue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            // Body / outfit
            outfitView
                .frame(width: size * 0.55, height: size * 0.3)
                .offset(y: size * 0.22)
            
            // Head
            Circle()
                .fill(config.skinColor)
                .frame(width: size * 0.45, height: size * 0.45)
                .offset(y: -size * 0.05)
            
            // Hair
            hairView
                .frame(width: size * 0.5, height: size * 0.25)
                .offset(y: -size * 0.22)
            
            // Eyes
            eyeView
                .offset(y: -size * 0.05)
            
            // Mouth
            mouthView
                .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
    
    // MARK: - Hair Styles
    
    @ViewBuilder
    private var hairView: some View {
        let hairColor = config.hairColorValue
        switch config.hairStyle {
        case 0:
            // Short straight
            Capsule()
                .fill(hairColor)
        case 1:
            // Round
            Ellipse()
                .fill(hairColor)
        case 2:
            // Spiky
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { _ in
                    Triangle()
                        .fill(hairColor)
                }
            }
        case 3:
            // Side part
            HStack(spacing: 0) {
                Rectangle()
                    .fill(hairColor)
                    .frame(width: size * 0.15)
                Capsule()
                    .fill(hairColor)
            }
        case 4:
            // Full round
            Circle()
                .fill(hairColor)
        default:
            // Wavy
            Capsule()
                .fill(hairColor)
                .rotationEffect(.degrees(-5))
        }
    }
    
    // MARK: - Eye Styles
    
    @ViewBuilder
    private var eyeView: some View {
        let eyeSpacing = size * 0.12
        HStack(spacing: eyeSpacing) {
            singleEye
            singleEye
        }
    }
    
    @ViewBuilder
    private var singleEye: some View {
        let eyeSize = size * 0.08
        switch config.eyeStyle {
        case 0:
            // Simple dots
            Circle()
                .fill(.black)
                .frame(width: eyeSize, height: eyeSize)
        case 1:
            // Filled larger
            Circle()
                .fill(.black)
                .frame(width: eyeSize * 1.3, height: eyeSize * 1.3)
        case 2:
            // Circle outline
            Circle()
                .stroke(.black, lineWidth: 1.5)
                .frame(width: eyeSize * 1.2, height: eyeSize * 1.2)
                .overlay(
                    Circle()
                        .fill(.black)
                        .frame(width: eyeSize * 0.6, height: eyeSize * 0.6)
                )
        case 3:
            // Circle filled with highlight
            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: eyeSize * 1.3, height: eyeSize * 1.3)
                Circle()
                    .fill(.white)
                    .frame(width: eyeSize * 0.4, height: eyeSize * 0.4)
                    .offset(x: eyeSize * 0.15, y: -eyeSize * 0.15)
            }
        case 4:
            // Glasses
            ZStack {
                Circle()
                    .stroke(.gray, lineWidth: 1.5)
                    .frame(width: eyeSize * 1.8, height: eyeSize * 1.8)
                Circle()
                    .fill(.black)
                    .frame(width: eyeSize * 0.7, height: eyeSize * 0.7)
            }
        default:
            // Squinting
            Capsule()
                .fill(.black)
                .frame(width: eyeSize * 1.2, height: eyeSize * 0.5)
        }
    }
    
    // MARK: - Mouth Styles
    
    @ViewBuilder
    private var mouthView: some View {
        let mouthWidth = size * 0.15
        switch config.mouthStyle {
        case 0:
            // Simple line
            Capsule()
                .fill(.black.opacity(0.6))
                .frame(width: mouthWidth, height: size * 0.02)
        case 1:
            // Smile
            HalfCircle()
                .fill(.black.opacity(0.6))
                .frame(width: mouthWidth, height: size * 0.06)
        case 2:
            // Open smile
            Ellipse()
                .fill(.black.opacity(0.6))
                .frame(width: mouthWidth * 0.8, height: size * 0.07)
        default:
            // Small circle (surprised)
            Circle()
                .fill(.black.opacity(0.6))
                .frame(width: size * 0.05, height: size * 0.05)
        }
    }
    
    // MARK: - Outfit
    
    @ViewBuilder
    private var outfitView: some View {
        let outfitColor = config.outfitColorValue
        switch config.outfitStyle {
        case 0:
            // T-shirt
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(outfitColor)
        case 1:
            // V-neck
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(outfitColor)
                Triangle()
                    .fill(config.skinColor)
                    .frame(width: size * 0.12, height: size * 0.1)
                    .offset(y: -size * 0.1)
            }
        case 2:
            // Dress
            UnevenRoundedRectangle(
                bottomLeadingRadius: size * 0.15,
                bottomTrailingRadius: size * 0.15
            )
            .fill(outfitColor)
        case 3:
            // Hoodie
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(outfitColor)
                Circle()
                    .stroke(outfitColor.opacity(0.8), lineWidth: 2)
                    .frame(width: size * 0.15)
                    .offset(y: -size * 0.12)
            }
        default:
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(outfitColor)
        }
    }
}

// MARK: - Helper Shapes

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        AvatarView(config: AvatarConfig(), size: 120)
        AvatarView(config: AvatarConfig(skinTone: 3, hairStyle: 2, hairColor: 4, eyeStyle: 3, mouthStyle: 1, outfitStyle: 2, outfitColor: 3), size: 120)
    }
}
