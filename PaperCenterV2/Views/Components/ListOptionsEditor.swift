//
//  ListOptionsEditor.swift
//  PaperCenterV2
//
//  Component for editing list options for list-type variables
//

import SwiftUI

/// Editor for managing list options
struct ListOptionsEditor: View {
    @Binding var options: [String]

    @State private var newOption: String = ""
    @State private var editingIndex: Int?
    @State private var editingText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("List Options")
                .font(.headline)

            Text("At least 2 options are required")
                .font(.caption)
                .foregroundStyle(.secondary)

            // List of current options
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack {
                    if editingIndex == index {
                        TextField("Option", text: $editingText, onCommit: {
                            saveEdit(at: index)
                        })
                        .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            saveEdit(at: index)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            cancelEdit()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            startEditing(at: index)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            deleteOption(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(options.count <= 2) // Prevent deleting if only 2 options
                    }
                }
                .padding(.vertical, 4)
            }

            // Add new option
            HStack {
                TextField("New option", text: $newOption, onCommit: addOption)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addOption()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 8)

            if options.count < 2 {
                Text("Warning: At least 2 options are required")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func addOption() {
        let trimmed = newOption.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !options.contains(trimmed) else { return }

        options.append(trimmed)
        newOption = ""
    }

    private func deleteOption(at index: Int) {
        guard options.count > 2 else { return }
        options.remove(at: index)
    }

    private func startEditing(at index: Int) {
        editingIndex = index
        editingText = options[index]
    }

    private func saveEdit(at index: Int) {
        let trimmed = editingText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelEdit()
            return
        }

        options[index] = trimmed
        cancelEdit()
    }

    private func cancelEdit() {
        editingIndex = nil
        editingText = ""
    }
}

// MARK: - Preview

#Preview("List Options Editor") {
    @Previewable @State var options: [String] = ["Easy", "Medium", "Hard"]

    Form {
        ListOptionsEditor(options: $options)
    }
}

#Preview("List Options Editor - Minimal") {
    @Previewable @State var options: [String] = ["Yes", "No"]

    Form {
        ListOptionsEditor(options: $options)

        Text("Options count: \(options.count)")
            .font(.caption)
    }
}
