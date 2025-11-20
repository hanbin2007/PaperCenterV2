//
//  VariableAssignment.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

// MARK: - PDFBundle Variable Assignment

/// Assignment of a variable value to a PDFBundle
@Model
final class PDFBundleVariableAssignment {
    /// Unique identifier
    var id: UUID

    /// The variable being assigned
    @Relationship(deleteRule: .nullify)
    var variable: Variable?

    /// The PDFBundle this assignment belongs to
    @Relationship(deleteRule: .nullify)
    var pdfBundle: PDFBundle?

    /// Integer value (for int type variables)
    var intValue: Int?

    /// List selection (for list type variables)
    var listValue: String?

    /// Text value (for text type variables)
    var textValue: String?

    /// Date value (for date type variables)
    var dateValue: Date?

    /// System-managed creation timestamp
    var createdAt: Date

    init(
        id: UUID = UUID(),
        variable: Variable,
        pdfBundle: PDFBundle,
        intValue: Int? = nil,
        listValue: String? = nil,
        textValue: String? = nil,
        dateValue: Date? = nil
    ) {
        self.id = id
        self.variable = variable
        self.pdfBundle = pdfBundle
        self.intValue = intValue
        self.listValue = listValue
        self.textValue = textValue
        self.dateValue = dateValue
        self.createdAt = Date()
    }
}

// MARK: - Doc Variable Assignment

/// Assignment of a variable value to a Doc
@Model
final class DocVariableAssignment {
    /// Unique identifier
    var id: UUID

    /// The variable being assigned
    @Relationship(deleteRule: .nullify)
    var variable: Variable?

    /// The Doc this assignment belongs to
    @Relationship(deleteRule: .nullify)
    var doc: Doc?

    /// Integer value (for int type variables)
    var intValue: Int?

    /// List selection (for list type variables)
    var listValue: String?

    /// Text value (for text type variables)
    var textValue: String?

    /// Date value (for date type variables)
    var dateValue: Date?

    /// System-managed creation timestamp
    var createdAt: Date

    init(
        id: UUID = UUID(),
        variable: Variable,
        doc: Doc,
        intValue: Int? = nil,
        listValue: String? = nil,
        textValue: String? = nil,
        dateValue: Date? = nil
    ) {
        self.id = id
        self.variable = variable
        self.doc = doc
        self.intValue = intValue
        self.listValue = listValue
        self.textValue = textValue
        self.dateValue = dateValue
        self.createdAt = Date()
    }
}

// MARK: - PageGroup Variable Assignment

/// Assignment of a variable value to a PageGroup
@Model
final class PageGroupVariableAssignment {
    /// Unique identifier
    var id: UUID

    /// The variable being assigned
    @Relationship(deleteRule: .nullify)
    var variable: Variable?

    /// The PageGroup this assignment belongs to
    @Relationship(deleteRule: .nullify)
    var pageGroup: PageGroup?

    /// Integer value (for int type variables)
    var intValue: Int?

    /// List selection (for list type variables)
    var listValue: String?

    /// Text value (for text type variables)
    var textValue: String?

    /// Date value (for date type variables)
    var dateValue: Date?

    /// System-managed creation timestamp
    var createdAt: Date

    init(
        id: UUID = UUID(),
        variable: Variable,
        pageGroup: PageGroup,
        intValue: Int? = nil,
        listValue: String? = nil,
        textValue: String? = nil,
        dateValue: Date? = nil
    ) {
        self.id = id
        self.variable = variable
        self.pageGroup = pageGroup
        self.intValue = intValue
        self.listValue = listValue
        self.textValue = textValue
        self.dateValue = dateValue
        self.createdAt = Date()
    }
}

// MARK: - Page Variable Assignment

/// Assignment of a variable value to a Page
@Model
final class PageVariableAssignment {
    /// Unique identifier
    var id: UUID

    /// The variable being assigned
    @Relationship(deleteRule: .nullify)
    var variable: Variable?

    /// The Page this assignment belongs to
    @Relationship(deleteRule: .nullify)
    var page: Page?

    /// Integer value (for int type variables)
    var intValue: Int?

    /// List selection (for list type variables)
    var listValue: String?

    /// Text value (for text type variables)
    var textValue: String?

    /// Date value (for date type variables)
    var dateValue: Date?

    /// System-managed creation timestamp
    var createdAt: Date

    init(
        id: UUID = UUID(),
        variable: Variable,
        page: Page,
        intValue: Int? = nil,
        listValue: String? = nil,
        textValue: String? = nil,
        dateValue: Date? = nil
    ) {
        self.id = id
        self.variable = variable
        self.page = page
        self.intValue = intValue
        self.listValue = listValue
        self.textValue = textValue
        self.dateValue = dateValue
        self.createdAt = Date()
    }
}

// MARK: - NoteBlock Variable Assignment

/// Assignment of a variable value to a NoteBlock
@Model
final class NoteBlockVariableAssignment {
    /// Unique identifier
    var id: UUID

    /// The variable being assigned
    @Relationship(deleteRule: .nullify)
    var variable: Variable?

    /// The NoteBlock this assignment belongs to
    @Relationship(deleteRule: .nullify)
    var noteBlock: NoteBlock?

    /// Integer value (for int type variables)
    var intValue: Int?

    /// List selection (for list type variables)
    var listValue: String?

    /// Text value (for text type variables)
    var textValue: String?

    /// Date value (for date type variables)
    var dateValue: Date?

    /// System-managed creation timestamp
    var createdAt: Date

    init(
        id: UUID = UUID(),
        variable: Variable,
        noteBlock: NoteBlock,
        intValue: Int? = nil,
        listValue: String? = nil,
        textValue: String? = nil,
        dateValue: Date? = nil
    ) {
        self.id = id
        self.variable = variable
        self.noteBlock = noteBlock
        self.intValue = intValue
        self.listValue = listValue
        self.textValue = textValue
        self.dateValue = dateValue
        self.createdAt = Date()
    }
}
