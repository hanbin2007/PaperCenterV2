//
//  VariableDisplayView.swift
//  PaperCenterV2
//
//  Shows variables in a single horizontal row.
//

import SwiftUI

struct VariableDisplayView: View {
    let variables: [FormattedVariable]

    var body: some View {
        if !variables.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(variables) { variable in
                        VariablePill(variable: variable)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct VariablePill: View {
    let variable: FormattedVariable

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: variable.color))
                .frame(width: 6, height: 6)
            Text("\(variable.name): \(variable.value)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((Color(hex: variable.color)).opacity(0.12))
                .foregroundStyle(Color(hex: variable.color))
                .clipShape(Capsule())
        }
    }
}
