//
//  VariableDisplayView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI

/// Displays variable assignments in a formatted way
/// Format: **VariableName**: Value
struct VariableDisplayView: View {
    let variables: [FormattedVariable]

    var body: some View {
        if !variables.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(variables) { variable in
                    HStack(spacing: 4) {
                        // Variable color indicator
                        Circle()
                            .fill(Color(hex: variable.color) ?? .purple)
                            .frame(width: 8, height: 8)

                        // Variable name in bold
                        Text("\(variable.name):")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        // Value in capsule
                        Text(variable.value)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((Color(hex: variable.color) ?? .purple).opacity(0.1))
                            .foregroundColor(Color(hex: variable.color) ?? .purple)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke((Color(hex: variable.color) ?? .purple).opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }
}
