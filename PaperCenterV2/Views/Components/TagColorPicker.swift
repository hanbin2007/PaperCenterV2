//
//  TagColorPicker.swift
//  PaperCenterV2
//
//  Component for selecting tag colors from a preset palette
//

import SwiftUI

/// Color picker for tag colors with preset palette
struct TagColorPicker: View {
    @Binding var selectedColor: String

    /// Preset color palette
    private let colorPalette: [String] = [
        "#3B82F6", // Blue
        "#10B981", // Green
        "#F59E0B", // Amber
        "#EF4444", // Red
        "#8B5CF6", // Purple
        "#EC4899", // Pink
        "#14B8A6", // Teal
        "#F97316", // Orange
        "#6366F1", // Indigo
        "#84CC16", // Lime
        "#06B6D4", // Cyan
        "#F43F5E", // Rose
        "#A855F7", // Violet
        "#22C55E", // Emerald
        "#FBBF24", // Yellow
        "#64748B", // Slate
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(colorPalette, id: \.self) { hexColor in
                    ColorButton(
                        hexColor: hexColor,
                        isSelected: selectedColor.uppercased() == hexColor.uppercased(),
                        action: {
                            selectedColor = hexColor
                        }
                    )
                }
            }

            // Show current color with hex code
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: selectedColor) ?? .blue)
                    .frame(width: 30, height: 30)

                Text(selectedColor.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            .padding(.top, 4)
        }
    }
}

/// Individual color button
private struct ColorButton: View {
    let hexColor: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: hexColor) ?? .blue)
                    .frame(width: 44, height: 44)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .bold))
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Tag Color Picker") {
    @Previewable @State var color: String = "#3B82F6"

    Form {
        TagColorPicker(selectedColor: $color)
    }
}
