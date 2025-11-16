# Metadata Assignment Components - Integration Guide

This document shows how to integrate the tag and variable assignment components into your Forms for document editing, page editing, etc.

## Components Overview

### 1. TagAssignmentSection
**Location**: `/Views/Components/Form/TagAssignmentSection.swift`

**Use Case**: Display and edit tag assignments in a Form

**In your DocEditView.swift:**
```swift
import SwiftUI
import SwiftData

struct DocEditView: View {
    @Bindable var doc: Doc
    @State private var title: String = ""

    var body: some View {
        Form {
            // Document title
            Section("Title") {
                TextField("Document Title", text: $title)
            }

            // Tags section - shows assigned tags and navigates to selection
            TagAssignmentSection(
                entity: doc,
                assignedTags: $doc.tags,
                entityType: .doc
            )

            // ... other sections
        }
        .onAppear {
            title = doc.title
        }
    }
}
```

### 2. VariableAssignmentSection
**Location**: `/Views/Components/Form/VariableAssignmentSection.swift`

**Use Case**: Display assigned variables and their values, navigate to selection

**In your DocEditView.swift:**
```swift
Form {
    Section("Title") {
        TextField("Document Title", text: $title)
    }

    // Tags section
    TagAssignmentSection(
        entity: doc,
        assignedTags: $doc.tags,
        entityType: .doc
    )

    // Variables section - shows assigned vars with values and selection
    VariableAssignmentSection(
        entity: doc,
        entityType: .doc,
        assignedVariables: doc.variableAssignments
    )

    // ... other sections
}
```

### 3. VariableValueEditor
**Location**: `/Views/Components/Form/VariableValueEditor.swift`

**Use Case**: Edit values for already-assigned variables

**In your DocEditView.swift:**
```swift
Form {
    Section("Title") {
        TextField("Document Title", text: $title)
    }

    // Tags section
    TagAssignmentSection(
        entity: doc,
        assignedTags: $doc.tags,
        entityType: .doc
    )

    // Variables assignment section
    VariableAssignmentSection(
        entity: doc,
        entityType: .doc,
        assignedVariables: doc.variableAssignments
    )

    // Edit variable values section
    if let assignments = doc.variableAssignments, !assignments.isEmpty {
        Section("Variable Values") {
            VariableValueEditor(assignments: assignments)
        }
    }
}
```

### 4. TagSelectionView
**Location**: `/Views/Components/Selection/TagSelectionView.swift`

**Use Case**: Selection screen opened from TagAssignmentSection
- Shows: Searchable, grouped list of all applicable tags
- Features: Capsule styling, grouped by TagGroup, scope-aware filtering

**Navigates automatically** - no manual integration needed

### 5. VariableSelectionView
**Location**: `/Views/Components/Selection/VariableSelectionView.swift`

**Use Case**: Selection screen opened from VariableAssignmentSection
- Shows: Searchable list of all applicable variables
- Features: Type indicators, scope display, color-coded

**Navigates automatically** - no manual integration needed

## Complete Example: Document Edit Form

Here's a complete example showing all three sections working together:

```swift
struct DocEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var doc: Doc

    @State private var title: String = ""
    @State private var showingSaveError = false

    var body: some View {
        NavigationStack {
            Form {
                // Basic information
                Section("Document Information") {
                    TextField("Document Title", text: $title)
                        .autocorrectionDisabled()

                    LabeledContent("Created", value: doc.createdAt, format: .dateTime)
                        .foregroundStyle(.secondary)

                    LabeledContent("Updated", value: doc.updatedAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }

                // Tags section
                Section("Tags") {
                    TagAssignmentSection(
                        entity: doc,
                        assignedTags: $doc.tags,
                        entityType: .doc
                    )
                }

                // Variables section
                if !variableAssignments.isEmpty {
                    Section("Variables") {
                        VariableAssignmentSection(
                            entity: doc,
                            entityType: .doc,
                            assignedVariables: doc.variableAssignments
                        )
                    }
                }

                // Variable values section (only if variables assigned)
                if let assignments = doc.variableAssignments, !assignments.isEmpty {
                    Section("Variable Values") {
                        Text("Set values for your assigned variables")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VariableValueEditor(assignments: assignments)
                    }
                }

                // Page groups (existing functionality)
                if !doc.orderedPageGroups.isEmpty {
                    Section("Page Groups") {
                        ForEach(doc.orderedPageGroups) { pageGroup in
                            LabeledContent(pageGroup.title, value: "\(pageGroup.pages?.count ?? 0) pages")
                        }
                    }
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                title = doc.title
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Unable to save changes. Please try again.")
            }
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveChanges() {
        doc.title = title.trimmingCharacters(in: .whitespaces)
        doc.touch()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Preview

#Preview("Doc Edit with Metadata") {
    let container = try! ModelContainer(for: Doc.self, Tag.self, TagGroup.self, Variable.self)

    // Create sample data
    let tagGroup = TagGroup(name: "Subject")
    let tag = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: tagGroup)
    container.mainContext.insert(tagGroup)
    container.mainContext.insert(tag)

    let variable = Variable(name: "Year", type: .int, scope: .doc, color: "#3B82F6")
    container.mainContext.insert(variable)

    let doc = Doc(title: "Math Exam 2023")
    doc.tags = [tag]
    let assignment = DocVariableAssignment(variable: variable, doc: doc, intValue: 2023)
    container.mainContext.insert(doc)
    container.mainContext.insert(assignment)
    doc.variableAssignments = [assignment]

    return DocEditView(doc: doc)
        .modelContainer(container)
}
```

## Page Edit Form Example

For editing pages (which belong to PageGroups):

```swift
struct PageEditView: View {
    @Bindable var page: Page

    var body: some View {
        Form {
            // Page information section
            Section("Page Information") {
                LabeledContent("Page Number", value: "\(page.currentPageNumber)")

                if let bundle = page.pdfBundle {
                    LabeledContent("PDF Bundle", value: bundle.displayName)
                }
            }

            // Tags section (Page-level tags)
            TagAssignmentSection(
                entity: page,
                assignedTags: $page.tags,
                entityType: .page
            )

            // Variables section (Page-level variables)
            if let assignments = page.variableAssignments, !assignments.isEmpty {
                Section("Variables") {
                    VariableAssignmentSection(
                        entity: page,
                        entityType: .page,
                        assignedVariables: assignments.map { assignment in
                            // Convert to DocVariableAssignment format for display
                            // (or create PageVariableAssignmentSection if needed)
                        }
                    )
                }
            }
        }
        .navigationTitle("Edit Page")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

## Tips

1. **Form Sections**: Each component is designed to work within a Form `Section`
2. **Bindings**: Use `@Bindable` and `@Binding` to ensure changes are reflected immediately
3. **Scope Filtering**: Components automatically filter tags/variables based on entity type
4. **Navigation**: Tap rows to navigate to selection screens (iOS handles back button)
5. **Empty States**: Components show appropriate messages when no tags/variables exist

## SwiftData Integration

Components integrate directly with SwiftData:
- `@Query` for fetching all tags/variables
- `@Bindable` for two-way binding to entity properties
- Automatic save when changes are made (in selection screens)
- Changes are persisted when the form is saved
