//
//  AvatarBuilderView.swift
//  gemma
//

import SwiftUI

struct AvatarBuilderView: View {
    @Binding var avatar: AvatarConfig
    var onDone: () -> Void
    
    @State private var selectedCategory = 0
    
    private let categories = ["Hair", "Eyes", "Mouth", "Skin", "Outfit"]
    
    var body: some View {
        VStack(spacing: 20) {
            // Live preview
            AvatarView(config: avatar, size: 140)
                .padding(.top, 16)
            
            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories.indices, id: \.self) { index in
                        Button {
                            selectedCategory = index
                        } label: {
                            Text(categories[index])
                                .font(.subheadline.weight(selectedCategory == index ? .semibold : .regular))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedCategory == index ? AppTheme.primary.opacity(0.15) : Color.secondary.opacity(0.08))
                                .foregroundStyle(selectedCategory == index ? AppTheme.primary : .secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Category content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedCategory {
                    case 0:
                        hairSection
                    case 1:
                        eyeSection
                    case 2:
                        mouthSection
                    case 3:
                        skinSection
                    default:
                        outfitSection
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Done button
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Hair Section
    
    private var hairSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            styleGrid(count: AvatarConfig.hairStyleIcons.count, selected: avatar.hairStyle) { index in
                avatar.hairStyle = index
            } icon: { index in
                Image(systemName: AvatarConfig.hairStyleIcons[index])
            }
            
            Text("Color")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            colorStrip(colors: AvatarConfig.hairColors, selected: avatar.hairColor) { index in
                avatar.hairColor = index
            }
        }
    }
    
    // MARK: - Eye Section
    
    private var eyeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            styleGrid(count: AvatarConfig.eyeStyleIcons.count, selected: avatar.eyeStyle) { index in
                avatar.eyeStyle = index
            } icon: { index in
                Image(systemName: AvatarConfig.eyeStyleIcons[index])
            }
        }
    }
    
    // MARK: - Mouth Section
    
    private var mouthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            styleGrid(count: AvatarConfig.mouthStyleIcons.count, selected: avatar.mouthStyle) { index in
                avatar.mouthStyle = index
            } icon: { index in
                Image(systemName: AvatarConfig.mouthStyleIcons[index])
            }
        }
    }
    
    // MARK: - Skin Section
    
    private var skinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skin Tone")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            colorStrip(colors: AvatarConfig.skinTones, selected: avatar.skinTone) { index in
                avatar.skinTone = index
            }
        }
    }
    
    // MARK: - Outfit Section
    
    private var outfitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            styleGrid(count: AvatarConfig.outfitStyleIcons.count, selected: avatar.outfitStyle) { index in
                avatar.outfitStyle = index
            } icon: { index in
                Image(systemName: AvatarConfig.outfitStyleIcons[index])
            }
            
            Text("Color")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            colorStrip(colors: AvatarConfig.outfitColors, selected: avatar.outfitColor) { index in
                avatar.outfitColor = index
            }
        }
    }
    
    // MARK: - Reusable Components
    
    private func styleGrid(count: Int, selected: Int, onSelect: @escaping (Int) -> Void, @ViewBuilder icon: @escaping (Int) -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    icon(index)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(selected == index ? AppTheme.primary.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected == index ? AppTheme.primary : Color.clear, lineWidth: 2)
                        )
                }
                .foregroundStyle(.primary)
            }
        }
    }
    
    private func colorStrip(colors: [Color], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(selected == index ? AppTheme.primary : Color.clear, lineWidth: 3)
                                .padding(2)
                        )
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: selected == index ? 2 : 0)
                                .padding(4)
                        )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AvatarBuilderView(avatar: .constant(AvatarConfig())) {
            // done
        }
        .navigationTitle("Customise Avatar")
    }
}
