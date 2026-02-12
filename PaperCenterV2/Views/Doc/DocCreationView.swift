//
//  DocCreationView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData

/// View for creating a new Doc from a PDFBundle
struct DocCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    let bundle: PDFBundle?

    @State private var title = ""
    @State private var selectedBundle: PDFBundle?
    @State private var errorMessage: String?
    @State private var creationService: DocCreationService?
    @State private var assignmentViewModel: TagVariableAssignmentViewModel?
    @State private var showingImportBundle = false
    @State private var showingBundleCreationPrompt = false
    @State private var hasPromptedBundleCreation = false

    init(bundle: PDFBundle? = nil) {
        self.bundle = bundle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Document Title", text: $title)
                } header: {
                    Text("Document Information")
                }

                if bundle == nil {
                    Section {
                        if bundles.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("No PDF bundles available", systemImage: "tray")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Select PDFBundle", selection: $selectedBundle) {
                                Text("Select a bundle").tag(nil as PDFBundle?)

                                ForEach(bundles) { bundle in
                                    BundlePickerRow(bundle: bundle)
                                        .tag(bundle as PDFBundle?)
                                }
                            }
                        }

                        Button {
                            showingImportBundle = true
                        } label: {
                            Label("Import PDF Bundle", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("PDF Source")
                    } footer: {
                        if bundles.isEmpty {
                            Text("Create a PDF bundle first, then continue creating this document.")
                        } else {
                            Text("Choose which PDF bundle to use as the source for this document, or import a new bundle.")
                        }
                    }
                }

                if let assignmentViewModel {
                    Section {
                        TagVariableAssignmentView(
                            viewModel: assignmentViewModel,
                            layoutMode: .form
                        )
                    } header: {
                        Text("Tags & Variables")
                    } footer: {
                        Text("Selections will be applied to the new document on create")
                            .font(.caption)
                    }

                    Section {
                        VariableValueSectionView(viewModel: assignmentViewModel)
                    } header: {
                        Text("Variable Values")
                    } footer: {
                        Text("Set values for the variables you selected above")
                            .font(.caption)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createDocument()
                    }
                    .disabled(!canCreate)
                }
            }
            .sheet(isPresented: $showingImportBundle) {
                PDFBundleImportView()
            }
            .onAppear {
                creationService = DocCreationService(modelContext: modelContext)
                if let bundle = bundle {
                    selectedBundle = bundle
                } else if selectedBundle == nil {
                    selectedBundle = bundles.first
                }
                assignmentViewModel = TagVariableAssignmentViewModel(
                    modelContext: modelContext,
                    entityType: .doc
                )
                promptForBundleCreationIfNeeded()
            }
            .onChange(of: bundles.map(\.id)) { _, _ in
                if let selectedBundle,
                   bundles.contains(where: { $0.id == selectedBundle.id }) == false {
                    self.selectedBundle = nil
                }
                if bundle == nil, selectedBundle == nil {
                    selectedBundle = bundles.first
                }
                promptForBundleCreationIfNeeded()
            }
            .alert("No PDF Bundle Available", isPresented: $showingBundleCreationPrompt) {
                Button("Import Bundle") {
                    showingImportBundle = true
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Creating a document requires at least one PDF bundle.")
            }
        }
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedBundle != nil
    }

    private func createDocument() {
        guard let bundle = selectedBundle,
              let service = creationService else {
            if self.bundle == nil, bundles.isEmpty {
                promptForBundleCreationIfNeeded(force: true)
            }
            errorMessage = "Missing required information"
            return
        }

        do {
            let createdDoc = try service.createDoc(from: bundle, title: title)
            if let assignmentViewModel {
                assignmentViewModel.applyPending(to: .doc(createdDoc))
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promptForBundleCreationIfNeeded(force: Bool = false) {
        guard bundle == nil, bundles.isEmpty else { return }
        guard force || !hasPromptedBundleCreation else { return }
        hasPromptedBundleCreation = true
        showingBundleCreationPrompt = true
    }
}

/// Row for bundle picker
private struct BundlePickerRow: View {
    let bundle: PDFBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bundle.displayName)
                .font(.body)

            HStack(spacing: 4) {
                if bundle.displayPDFPath != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Has Display PDF")
                        .font(.caption2)
                }
                Text("• Created: \(bundle.createdAt, format: .dateTime.month().day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
