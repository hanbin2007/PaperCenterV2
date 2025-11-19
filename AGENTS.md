# Repository Guidelines

## Project Structure & Module Organization
`PaperCenterV2App.swift` (SwiftUI entry) plus domain code live under `PaperCenterV2/`. Models are grouped in `Models/Core`, `Models/Metadata`, and `Models/Enums`. Views reside in `Views/Doc`, `Views/PDFBundle`, `Views/Properties`, and `Views/Components`, with matching logic in `ViewModels/`. Shared workflows stay in `Services/` (PDF import, metadata formatting, property management). Tests sit in `PaperCenterV2Tests/` and `PaperCenterV2UITests/`, while assets, Info.plist, and entitlements stay beside the app target for Xcode sync.

## Build, Test, and Development Commands
- `xed PaperCenterV2.xcodeproj` opens the workspace with the PaperCenterV2 scheme.
- `xcodebuild -scheme PaperCenterV2 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` performs a clean CI build.
- `xcodebuild test -scheme PaperCenterV2 -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` executes unit and UI tests; pass `-only-testing:PaperCenterV2UITests` for focused runs.

## Coding Style & Naming Conventions
Swift 5.9+, four-space indentation, trailing commas for multiline literals, and `// MARK:` blocks (see `Models/Core/PDFBundle.swift`). Use `UpperCamelCase` for types, `lowerCamelCase` for members, and prefer lightweight `struct`s or `final class` based on SwiftData needs. Keep view structs declarative and move side effects into the corresponding `Observable` view model. New files should mirror the existing directory namespace so `import PaperCenterV2` stays predictable.

## Testing Guidelines
Unit tests belong in `PaperCenterV2Tests` and mirror the code’s namespace (e.g., `PDFBundleTests`). Name methods `test<Feature><Expectation>()` and rely on in-memory `ModelContainer` fixtures for SwiftData coverage. UI flows go in `PaperCenterV2UITests` with `XCUIApplication` launch helpers shared via extensions. Run `xcodebuild test ...` before every pull request and keep new functionality at ≥80% line coverage.

## Commit & Pull Request Guidelines
Commits follow the repo’s imperative tone (“Add TagVariableAssignmentView and related components”, “Update settings and enhance tag group management UI”). Keep each commit scoped to one behavioral change and include migration helpers when SwiftData schemas move. Pull requests should describe the motivation, list the verification command, link the tracking issue, and attach screenshots for Doc/PDFBundle/Properties UI changes. Call out schema or entitlements updates so reviewers can verify persistence and sandbox behavior.

## Architecture & Data Notes
`PaperCenterV2App` boots a shared SwiftData `ModelContainer` that registers PDFs, Docs, Tags, and Variable assignments. Services handle IO-heavy work (OCR, import, property management) so view models remain pure observers. Helper APIs such as `PDFBundle.fileURL(for:)` encapsulate sandbox paths; reuse them instead of touching `FileManager` directly. When adding entities or relationships, update the schema list, extend Services/ViewModels accordingly, and document any new controls under `Views/Properties` for discoverability.

---
Architecture Specification

1. Scope & Objectives

This document defines the core architecture for the UniversalDoc system used to manage and view structured study materials composed of multiple PDF sources and page versions.

The architecture is organized into three clearly separated layers:
	1.	Domain Layer – system of record for all documents, pages, versions, bundles, tags, variables, and annotations.
	2.	Session Layer – adapter that transforms domain data plus a specific usage scenario into a concrete, consumable viewing session.
	3.	UniversalDoc Viewer Layer – embeddable, UI-focused document viewer that renders pages, supports per-page version/source switching, and exposes user interactions as events.

This specification assumes:
	•	Only Page entities are versioned.
	•	Doc is not versioned.
	•	Switching versions inside the Viewer is purely a preview behavior and never mutates Page.currentVersion.
	•	The Viewer must support per-page switching between:
	•	multiple PageVersions of the same Page (preview only),
	•	multiple sources within a PDFBundle (e.g. DisplayPDF / OriginalPDF / OCR-based view).

⸻

2. Domain Layer

2.1 Responsibilities

The Domain Layer is the source of truth for all persistent business entities and rules. It:
	•	Defines and owns all core data models.
	•	Enforces versioning rules and structural consistency.
	•	Provides query APIs for the Session Layer.
	•	Does not handle UI concerns or per-session transient state.

2.2 Core Entities (Conceptual)

Doc
	•	Represents a logical document (e.g. an exam, a collection of pages).
	•	Contains:
	•	Ordered list of PageGroups and Pages.
	•	Not versioned.
	•	May be empty (no pages initially).

PageGroup
	•	Logical grouping of Pages.
	•	Flat: cannot nest PageGroups.
	•	A Page belongs to exactly one PageGroup within a Doc.
	•	Has title, metadata (via tags/variables).

Page
	•	Represents a logical page slot within a Doc.
	•	Constraints:
	•	A Page belongs to exactly one PageGroup / Doc.
	•	A Page is not shared across Docs/PageGroups.
	•	Has:
	•	Multiple PageVersions.
	•	A single currentVersion (the default/effective version for this Page).
	•	Metadata via tags/variables.

PageVersion
	•	Immutable snapshot of a Page’s content binding at a given time.
	•	Contains:
	•	Reference to PDFBundle (by ID).
	•	Page index within that bundle.
	•	Metadata snapshot (tags/variables as of creation time).
	•	Created only when:
	•	The bound PDFBundle changes, or
	•	The page index within the bundle changes.
	•	Historical versions are retained.
	•	Changing tags/variables on the live Page does not retroactively modify existing PageVersion snapshots.

PDFBundle
	•	Stores up to three aligned PDF variants plus extracted text:
	•	DisplayPDF (primary for display)
	•	OriginalPDF (e.g. raw scan with handwriting)
	•	OCRPDF (for text extraction)
	•	All files are copied into the app sandbox.
	•	Page alignment:
	•	By default, variants are expected to have strictly aligned page counts.
	•	When misaligned, an override mapping may be defined:
	•	Pages are matched top-down.
	•	Unmapped extra pages are ignored for alignment-related operations.
	•	OCR text is stored per page.

Tags / Variables
	•	Global configuration:
	•	TagGroup:
	•	Named group of tags.
	•	Tag:
	•	Has name, color, and scope (which entity types it may be applied to).
	•	May be assigned to any entity within its allowed scope.
	•	Variable:
	•	Types: int or single-choice list.
	•	Has scope (which entity types it may apply to).
	•	Values are assigned per element (no inheritance behavior implemented).
	•	Aside from system fields (createdAt, updatedAt), all semantic metadata is represented via Tags and Variables.

Annotations / Comments (high-level)
	•	Persisted at Domain Layer.
	•	Anchored to:
	•	A specific PageVersion and page-relative coordinates, or
	•	A logical page reference plus normalized coordinates (implementation-dependent).

2.3 Domain-Level Invariants
	•	Page.currentVersion is the only canonical default for that Page.
	•	Page.currentVersion is modified only through explicit domain operations (e.g. administrative/editor flows), never by Viewer preview actions.
	•	A PageVersion never mutates once created.
	•	A PDFBundle that is referenced must not be destructively modified in ways that break existing references.

⸻

3. Session Layer

3.1 Responsibilities

The Session Layer is an adapter between Domain and Viewer. It:
	•	Consumes Domain data plus a concrete usage scenario.
	•	Produces a UniversalDoc Session:
	•	A structured, ordered set of logical pages with all necessary context to render and interact.
	•	Maintains per-session, in-memory state:
	•	Current per-page preview version.
	•	Current per-page source (Display/Original/OCR).
	•	Cross-viewer synchronization state (if applicable).
	•	Forwards Viewer events to Domain if/when persistence is required (e.g. saving annotations).

The Session Layer does not:
	•	Define persistent models.
	•	Change Page.currentVersion as a result of preview switching.
	•	Render UI.

3.2 Logical Page Slot

The core abstraction produced by the Session Layer is the Logical Page Slot.

For each logical page position in the viewing context, the Session Layer defines:
	•	logicalPageID
	•	Typically the Page.id.
	•	May be a synthetic ID for ad-hoc sessions (e.g. bundle-only previews, search snippets).
	•	versionOptions
	•	All PageVersions available for this Page.
	•	For each option:
	•	pageVersionID
	•	pdfBundleID
	•	pageIndex
	•	Optional flags (e.g. “current”, “historical”).
	•	defaultVersionID
	•	Must be set to Page.currentVersion for standard Doc-based sessions.
	•	Used as the initial selection in the Viewer.
	•	sourceOptionsForDefaultVersion
	•	Derived from the default version’s PDFBundle:
	•	e.g. [Display, Original, OCRText?].
	•	defaultSource
	•	Typically Display if available, else Original.
	•	capabilities
	•	Flags controlling allowed interactions for this slot:
	•	e.g. canPreviewOtherVersions, canSwitchSource, canAnnotate.

The Session Layer aggregates these slots into an ordered list representing the reading flow.

3.3 Session Object (Conceptual)

A UniversalDoc Session includes:
	•	Ordered list of Logical Page Slots.
	•	Global configuration:
	•	View mode: single page, continuous scroll, spread, side-by-side, etc.
	•	Feature flags: annotations enabled, side comments enabled, etc.
	•	Transient state:
	•	For each slot:
	•	currentPreviewVersionID (initially = defaultVersionID)
	•	currentSource (initially = defaultSource)
	•	Shared navigation/sync state for multi-viewer scenarios.

3.4 Handling Viewer Events

The Session Layer receives events from the Viewer, such as:
	•	onPageVersionPreviewChanged(logicalPageID, pageVersionID)
	•	onSourceChanged(logicalPageID, source)
	•	onPageNavigated(newIndex)
	•	onAnnotationCreated(...)
	•	onAnnotationUpdated(...)

Expected behavior:
	•	Preview actions:
	•	Update only the in-session state (e.g. currentPreviewVersionID).
	•	Do not update Page.currentVersion.
	•	Source switches:
	•	Update only session state.
	•	Annotation-related events:
	•	Forward to Domain services for persistence as needed.
	•	Synchronization:
	•	Optionally propagate navigation/selection changes to other Session/Viewer instances if configured.

The Session Layer is the only layer that interprets Viewer events in a business-aware way.

⸻

4. UniversalDoc Viewer Layer

4.1 Responsibilities

The UniversalDoc Viewer is a reusable, embeddable document viewing component. It:
	•	Renders pages according to a provided Session.
	•	Supports:
	•	Paging and scrolling.
	•	Zoom and basic navigation.
	•	Per-page version preview switching (when allowed by Session).
	•	Per-page source switching (Display/Original/OCR) for the selected version.
	•	Annotation overlay rendering and interaction.
	•	Optional side-panel / side-by-side layouts (e.g. commentary, parallel views).
	•	Emits structured events for user interactions.

The Viewer does not:
	•	Query the Domain Layer directly.
	•	Decide which versions exist or which is default.
	•	Modify Page.currentVersion or any domain entity.
	•	Persist any data.

4.2 Rendering Behavior

Given a Session and its Logical Page Slots, for each displayed page the Viewer:
	1.	Reads the slot’s:
	•	currentPreviewVersionID (or defaultVersionID if unchanged).
	•	currentSource.
	2.	Requests the corresponding render data from a higher-level data provider (e.g. a ViewerDataSource bound to the Session Layer), including:
	•	Resolved PDFBundle page for the selected version.
	•	Renderable content for the selected source (DisplayPDF, OriginalPDF, OCR-based).
	•	Associated annotations and comments for that context.
	3.	Renders the content accordingly.

4.3 Interaction Semantics

All interactive controls within the Viewer operate on session-local state and emit events upward:
	•	Version selector (per page):
	•	Allows switching between available versionOptions when canPreviewOtherVersions is true.
	•	Triggers onPageVersionPreviewChanged, with no implied persistence.
	•	Source selector (per page):
	•	Allows switching between Display, Original, OCRText when available.
	•	Triggers onSourceChanged.
	•	Navigation:
	•	Updates current page index; emits onPageNavigated.
	•	Annotations & comments:
	•	User actions emit creation/update/delete events with precise anchors.
	•	Actual persistence is handled outside the Viewer.

Multi-viewer synchronization (e.g. parallel viewers for answer/solution) is built by:
	•	Sharing or coordinating Session/State at the Session Layer.
	•	The Viewer simply observes and reflects provided state.

⸻

5. Invariants & Guarantees
	1.	Domain as Source of Truth
	•	All entities (Doc, Page, PageVersion, PDFBundle, Tag, Variable, annotations) are defined and persisted exclusively in the Domain Layer.
	2.	Doc is Non-Versioned
	•	A Doc’s structure may change over time, but there is no Doc-level versioning in this design.
	3.	Page-Level Versioning Only
	•	PageVersion changes are explicit and append-only.
	•	Page.currentVersion is the authoritative default, modified only by explicit domain operations (not Viewer interactions).
	4.	Viewer-Only Preview Switching
	•	Any version/source switching performed inside UniversalDoc Viewer:
	•	Affects only the active Session.
	•	Never mutates Page.currentVersion.
	•	Never implicitly redefines domain-level defaults.
	5.	Clear Separation of Concerns
	•	Domain: “What exists” and “what is officially current”.
	•	Session: “How we want to present it in this context, right now”.
	•	Viewer: “How it looks and behaves on screen, based on what it was given”.


