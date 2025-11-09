# PaperCenterV2 - Document Organizing App

## Project Overview

**Platform**: iOS 17.0+
**Framework**: SwiftUI + SwiftData
**Bundle ID**: `hanbin.PaperCenterV2`
**Purpose**: Study material organization tool for managing multiple PDF variants of exam/learning materials

## Core Concept

This app manages exam papers and study materials where the same logical document exists in three different PDF forms:
- **DisplayPDF**: Final content for display (core, recommended)
- **OCRPDF**: Used for text extraction (optional)
- **OriginalPDF**: Original exam paper without handwriting (optional)

Materials are organized into reusable bundles and logical structures to support efficient navigation, tagging, and versioning.

---

## Entity Specifications

### 1. PDFBundle

**Purpose**: Container for PDF files and their extracted text

**Properties**:
- `id: UUID` - Unique identifier
- `createdAt: Date` - System managed
- `updatedAt: Date` - System managed
- `displayPDFPath: String?` - Sandbox-relative path
- `ocrPDFPath: String?` - Sandbox-relative path
- `originalPDFPath: String?` - Sandbox-relative path
- `pageMapping: [String: Any]?` - Custom page alignment overrides (JSON)
- `ocrTextByPage: [Int: String]` - Extracted text per page number

**Relationships**:
- `pages: [Page]` - Inverse relationship to all Pages referencing this bundle

**Rules**:
1. Can contain up to 3 aligned PDF variants (display, OCR, original)
2. Can be reused by multiple Docs
3. May contain multiple unrelated PDFs if needed
4. All files stored in app sandbox (external paths not relied upon)
5. Page alignment:
   - Default: strict alignment (same page count and ordering)
   - Override: user-defined mapping, top-down order, extra pages ignored
6. OCR text extracted only from OCRPDF, stored per-page
7. Lifecycle:
   - Append-only (can add files/pages)
   - Cannot be deleted if referenced by any Page
   - Cannot be modified in ways that break existing Page references

**File Storage Strategy**:
- Files copied to: `Documents/PDFBundles/{bundleID}/`
- Naming: `display.pdf`, `ocr.pdf`, `original.pdf`

---

### 2. Page

**Purpose**: Logical unit referring to exactly one page within one PDFBundle

**Properties**:
- `id: UUID` - Unique identifier
- `createdAt: Date` - System managed
- `updatedAt: Date` - System managed
- `currentPDFBundleID: UUID` - Current bundle reference
- `currentPageNumber: Int` - Current page number in bundle

**Relationships**:
- `pdfBundle: PDFBundle` - Reference to containing bundle
- `pageGroup: PageGroup` - Parent group (required, exclusive)
- `versions: [PageVersion]` - Version history
- `tags: [Tag]` - Applied tags
- `variableAssignments: [PageVariableAssignment]` - Variable values

**Rules**:
1. Created whenever a PDFBundle page is used in a Doc/PageGroup
2. Cannot be shared - belongs to exactly one PageGroup
3. Has no title (title is at PageGroup level)
4. Supports metadata (tags, variables)
5. Maintains full version history

**Versioning Triggers**:
- New version created when:
  - Referenced PDFBundle changes, OR
  - Page number within bundle changes
- Tag/variable changes do NOT create new versions

---

### 3. PageVersion

**Purpose**: Immutable snapshot of a Page at a point in time

**Properties**:
- `id: UUID` - Unique identifier
- `createdAt: Date` - Version timestamp
- `pdfBundleID: UUID` - Bundle at this version
- `pageNumber: Int` - Page number at this version
- `metadataSnapshot: Data` - Encoded snapshot of tags/variables

**Relationships**:
- `page: Page` - Parent page

**Rules**:
1. Immutable once created
2. Metadata snapshot is independent of current Page metadata
3. Complete history retained
4. Referenced PDFBundles must not be destructively altered

---

### 4. PageGroup

**Purpose**: Ordered collection of Pages within a Doc

**Properties**:
- `id: UUID` - Unique identifier
- `title: String` - Required, user-defined
- `createdAt: Date` - System managed
- `updatedAt: Date` - System managed
- `pageOrder: [UUID]` - Ordered array of Page IDs

**Relationships**:
- `pages: [Page]` - Ordered collection (1-to-many, exclusive ownership)
- `doc: Doc` - Parent document (required)
- `tags: [Tag]` - Applied tags
- `variableAssignments: [PageGroupVariableAssignment]` - Variable values

**Rules**:
1. Contains one or more Pages
2. Cannot contain nested PageGroups
3. Pages cannot belong to multiple PageGroups
4. Title required
5. Supports metadata (tags, variables)

**Use Cases**:
- Group by section, question type, or topic
- Organize pages within a single exam
- Create custom collections

---

### 5. Doc (Document)

**Purpose**: Top-level logical container for organizing study materials

**Properties**:
- `id: UUID` - Unique identifier
- `title: String` - Required, user-defined
- `createdAt: Date` - System managed
- `updatedAt: Date` - System managed
- `pageGroupOrder: [UUID]` - Ordered array of PageGroup IDs

**Relationships**:
- `pageGroups: [PageGroup]` - Ordered collection
- `tags: [Tag]` - Applied tags
- `variableAssignments: [DocVariableAssignment]` - Variable values

**Rules**:
1. Contains one or more PageGroups (or may start empty)
2. May reference Pages that reference PDFBundles reused across multiple Docs
3. Title required
4. Supports metadata (tags, variables)

**Use Cases**:
- Single exam paper
- Multiple unrelated materials
- Custom collection from various PDFBundles

---

## Metadata System

All entities support flexible annotation via Tags and Variables. System-managed fields (`createdAt`, `updatedAt`) exist on all entities; all other semantic annotations use Tags/Variables.

### TagGroup

**Properties**:
- `id: UUID` - Unique identifier
- `name: String` - Group name (e.g., "Subject", "Difficulty")
- `createdAt: Date` - System managed
- `updatedAt: Date` - System managed

**Relationships**:
- `tags: [Tag]` - Tags in this group

---

### Tag

**Properties**:
- `id: UUID` - Unique identifier
- `name: String` - Tag name (e.g., "Mathematics", "Hard")
- `color: String` - Hex color code
- `scope: TagScope` - Which entities can use this tag

**Relationships**:
- `tagGroup: TagGroup` - Parent group
- Many-to-many with: `PDFBundle`, `Doc`, `PageGroup`, `Page` (based on scope)

**TagScope Enum**:
```swift
enum TagScope: String, Codable {
    case pdfBundle    // PDFBundle only
    case doc          // Doc only
    case pageGroup    // PageGroup only
    case page         // Page only
    case docAndBelow  // Doc, PageGroup, Page
    case all          // All entities
}
```

---

### Variable

**Purpose**: Typed, scoped fields attachable to entities

**Properties**:
- `id: UUID` - Unique identifier
- `name: String` - Variable name (e.g., "Year", "Score")
- `type: VariableType` - Data type
- `scope: VariableScope` - Which entities can use this variable
- `listOptions: [String]?` - For list type, predefined options

**VariableType Enum**:
```swift
enum VariableType: String, Codable {
    case int    // Integer value
    case list   // Single choice from predefined options
}
```

**VariableScope Enum**:
```swift
enum VariableScope: String, Codable {
    case pdfBundle
    case doc
    case pageGroup
    case page
    case all
}
```

**Variable Assignments**:
Separate models for each entity type:
- `PDFBundleVariableAssignment`
- `DocVariableAssignment`
- `PageGroupVariableAssignment`
- `PageVariableAssignment`

Each assignment contains:
- Entity reference
- Variable reference
- Value (int or selected list option)

**Rules**:
1. Variables defined globally
2. Assignments per-element only (no inheritance currently)
3. List type: exactly one option selected
4. Int type: single integer value

---

## Implementation Details

### SwiftData Model Design

All models use `@Model` macro. Key patterns:

**Relationships**:
- Use `@Relationship(deleteRule: .cascade)` for parent-child
- Use `@Relationship(inverse: \Path.to.property)` for bidirectional
- Page → PageGroup: required, exclusive (deleteRule: .nullify on PageGroup side)
- PageGroup → Doc: required (deleteRule: .nullify on Doc side)

**Unique Constraints**:
- All entities use UUID for `id`
- Tag names unique within TagGroup
- Variable names unique globally

**Indexes**:
- Index on Page.currentPDFBundleID for lookup
- Index on creation dates for sorting

### File Management

**Strategy**:
- All PDFs copied to app sandbox on import
- Base path: `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]`
- Structure: `Documents/PDFBundles/{bundleID}/{display|ocr|original}.pdf`

**Import Process**:
1. User selects external PDF file
2. Create new PDFBundle with UUID
3. Create bundle directory
4. Copy file to sandbox with standardized name
5. Store relative path in PDFBundle
6. Extract OCR text if OCRPDF (background task)

**Deletion Rules**:
- PDFBundle can only be deleted if no Page references it
- Deleting a Page removes it from version history
- Deleting a PageGroup cascades to all owned Pages
- Deleting a Doc cascades to all PageGroups and their Pages

### Concurrency & Thread Safety

**Strategy**:
- Use SwiftData's `@ModelActor` for background operations
- Main thread: UI updates and user interactions
- Background thread: PDF imports, OCR extraction, large queries

**Conflict Resolution**:
- Simple locking or last-writer-wins for same-Page edits
- No simultaneous editing of same Page allowed
- UI should prevent concurrent edits (e.g., edit mode locks)

### OCR Text Extraction

**Approach**:
- Use Vision framework (`VNRecognizeTextRequest`)
- Extract per-page on background thread
- Store in `PDFBundle.ocrTextByPage` dictionary
- Support search across all OCR text

**Process**:
1. Load OCRPDF from sandbox
2. Iterate pages using PDFKit
3. For each page: Vision text recognition
4. Store results keyed by page number

---

## Data Model Relationships Diagram

```
Doc (1) ──────┬──────> (M) PageGroup
              │
              └──────> (M) Tag
              └──────> (M) DocVariableAssignment

PageGroup (1) ──┬────> (M) Page (exclusive ownership)
                │
                └────> (M) Tag
                └────> (M) PageGroupVariableAssignment

Page (1) ──────┬─────> (1) PDFBundle
               │
               ├─────> (M) PageVersion
               ├─────> (M) Tag
               └─────> (M) PageVariableAssignment

PageVersion ───┬─────> (1) PDFBundle (historical reference)
               └─────> (snapshot) Metadata

PDFBundle ─────┬─────> (M) Page (inverse)
               └─────> (M) Tag

TagGroup (1) ──┬─────> (M) Tag

Variable (global registry)
```

---

## Project Structure

```
PaperCenterV2/
├── PaperCenterV2App.swift          # App entry point
├── Models/
│   ├── Core/
│   │   ├── PDFBundle.swift
│   │   ├── Page.swift
│   │   ├── PageVersion.swift
│   │   ├── PageGroup.swift
│   │   └── Doc.swift
│   ├── Metadata/
│   │   ├── Tag.swift
│   │   ├── TagGroup.swift
│   │   ├── Variable.swift
│   │   └── VariableAssignment.swift
│   └── Enums/
│       ├── TagScope.swift
│       ├── VariableType.swift
│       └── VariableScope.swift
├── Services/
│   ├── PDFImportService.swift      # Import & file management
│   ├── OCRService.swift             # Text extraction
│   └── VersioningService.swift      # Page version management
├── Views/                           # (Future: UI implementation)
├── Assets.xcassets
└── Info.plist
```

---

## Current Progress

### ✅ Phase 1 Complete - Core Data Models (2025-11-09)

**Project Setup**:
- ✅ Cleared default Xcode template files
- ✅ Created organized folder structure (Models/Core, Models/Metadata, Models/Enums, Services, Views)
- ✅ Updated iOS deployment target to 17.0
- ✅ Configured SwiftData ModelContainer with all models

**Core Models Implemented**:
- ✅ PDFBundle - Container for PDF variants with OCR text storage
- ✅ Page - Logical page unit with versioning support
- ✅ PageVersion - Immutable version history snapshots
- ✅ PageGroup - Ordered collection of Pages
- ✅ Doc - Top-level document container

**Metadata System**:
- ✅ Tag & TagGroup - Flexible tagging with scope control
- ✅ Variable - Typed metadata fields (int/list types)
- ✅ VariableAssignment - Per-entity variable assignments for all types

**Enums & Supporting Types**:
- ✅ TagScope - Defines tag applicability
- ✅ VariableType - Int and list variable types
- ✅ VariableScope - Defines variable applicability
- ✅ PDFType - Display, OCR, and original PDF types

**Services**:
- ✅ PDFImportService - File management and OCR extraction
  - PDF import with sandbox copying
  - Bundle directory management
  - Basic OCR text extraction using PDFKit
  - Safe deletion with reference checking

**Build Status**:
- ✅ Project builds successfully with no errors
- ✅ All SwiftData models compile correctly
- ✅ Placeholder UI created for testing

### 📋 Next Phase: UI Implementation

**Phase 2 Goals**:
- Doc list view with create/edit/delete
- PageGroup browser with navigation
- Page viewer with PDF display (PDFKit)
- Tag/Variable management interface
- Search functionality across OCR text
- Batch operations for organizing content

---

## Future Roadmap

### Phase 2: Basic UI (Future)
- Doc list view
- PageGroup browser
- Page viewer with PDF display
- Tag/Variable management UI

### Phase 3: Advanced Features (Future)
- Full-text search across OCR
- PDF annotations
- Export to various formats
- Batch operations
- Statistics and analytics
- iCloud sync
- Multi-device support

---

## Design Decisions & Rationale

1. **Why SwiftData over Core Data?**
   - Modern Swift-native API
   - Less boilerplate
   - Better type safety
   - Seamless SwiftUI integration

2. **Why exclusive Page ownership?**
   - Simplifies relationship management
   - Clear lifecycle and deletion rules
   - Prevents complex reference counting issues
   - Reusability at PDFBundle level instead

3. **Why separate VariableAssignment models?**
   - Type safety (can't assign Doc variable to Page)
   - Clear querying (fetch all Doc variables)
   - Easier to enforce scope rules

4. **Why immutable PageVersions?**
   - Historical accuracy
   - Audit trail for changes
   - Prevents accidental history modification
   - Enables "time travel" debugging

5. **Why file copying instead of references?**
   - Reliability (external files may move/delete)
   - App sandbox security
   - Consistent file access
   - Enable iCloud backup

---

## Notes & Considerations

- **iOS Deployment Target**: Originally set to 26.0 (unusually high), will adjust to iOS 17.0 minimum for SwiftData
- **iCloud**: Currently enabled but not configured; future feature
- **CloudKit**: Container identifiers empty; will configure if sync needed
- **Testing**: Unit test and UI test targets included; will implement tests for core logic
- **Accessibility**: Future consideration for VoiceOver and PDF navigation
- **Localization**: Future consideration for multi-language support

---

## Version History

- **v0.1** (2025-11-09): Initial specification and planning phase
- **v0.2** (2025-11-09): Phase 1 complete - Core SwiftData models, services, and project setup
  - Implemented all core models (PDFBundle, Page, PageVersion, PageGroup, Doc)
  - Implemented metadata system (Tag, TagGroup, Variable, VariableAssignments)
  - Created PDFImportService for file management and OCR extraction
  - Project builds successfully with iOS 17.0 deployment target
  - Ready for Phase 2: UI implementation
