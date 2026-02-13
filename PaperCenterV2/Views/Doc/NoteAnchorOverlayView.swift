//
//  NoteAnchorOverlayView.swift
//  PaperCenterV2
//
//  Interactive overlay for note anchors on top of PDFView.

import CoreGraphics
import PDFKit
import UIKit

// 增加 Equatable 以启用高效率的变化检测拦截
struct NoteAnchorOverlayItem: Identifiable, Equatable {
    let id: UUID
    let composedPageIndex: Int
    let normalizedRect: CGRect
    let title: String?
    let body: String
}

struct PageTagOverlayChip: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct PageTagOverlayItem: Identifiable, Equatable {
    let composedPageIndex: Int
    let pageGroupTitle: String
    let chips: [PageTagOverlayChip]
    var id: Int { composedPageIndex }
}

private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
    
    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(
            width: base.width + insets.left + insets.right,
            height: base.height + insets.top + insets.bottom
        )
    }
}

private final class PageTagBadgeView: UIView {
    private let titleLabel = UILabel()
    private let chipsStack = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .right
        titleLabel.numberOfLines = 1
        
        chipsStack.axis = .vertical
        chipsStack.alignment = .trailing
        chipsStack.spacing = 6
        chipsStack.distribution = .fill
        
        addSubview(titleLabel)
        addSubview(chipsStack)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 8
        let contentRect = bounds.insetBy(dx: inset, dy: inset)
        
        let titleHeight: CGFloat = titleLabel.isHidden ? 0 : 16
        titleLabel.frame = CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: contentRect.width,
            height: titleHeight
        )
        
        chipsStack.frame = CGRect(
            x: contentRect.minX,
            y: titleLabel.frame.maxY + (titleLabel.isHidden ? 0 : 6),
            width: contentRect.width,
            height: max(0, contentRect.maxY - titleLabel.frame.maxY - (titleLabel.isHidden ? 0 : 6))
        )
    }
    
    func configure(groupTitle: String, chips: [PageTagOverlayChip]) {
        let trimmedGroup = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGroup.isEmpty {
            titleLabel.isHidden = true
            titleLabel.text = nil
        } else {
            titleLabel.isHidden = false
            titleLabel.text = trimmedGroup
        }
        
        chipsStack.arrangedSubviews.forEach { view in
            chipsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        let maxVisible = 4
        let visibleChips = Array(chips.prefix(maxVisible))
        
        for chip in visibleChips {
            let label = InsetLabel()
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.text = chip.name
            label.textAlignment = .right
            label.textColor = UIColor.paperHex(chip.colorHex, fallback: .systemBlue)
            label.backgroundColor = UIColor.paperHex(chip.colorHex, fallback: .systemBlue).withAlphaComponent(0.15)
            
            label.layer.cornerRadius = 10
            label.layer.cornerCurve = .continuous
            label.layer.masksToBounds = true
            label.numberOfLines = 1
            
            chipsStack.addArrangedSubview(label)
        }
        
        let overflow = chips.count - visibleChips.count
        if overflow > 0 {
            let moreLabel = UILabel()
            moreLabel.font = .systemFont(ofSize: 11, weight: .medium)
            moreLabel.textColor = .secondaryLabel
            moreLabel.textAlignment = .right
            moreLabel.text = "+\(overflow) more"
            chipsStack.addArrangedSubview(moreLabel)
        }
    }
}

private final class NoteContentBubbleView: UIView {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.numberOfLines = 1
        
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.numberOfLines = 2
        
        addSubview(titleLabel)
        addSubview(bodyLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 8
        let contentRect = bounds.insetBy(dx: inset, dy: inset)
        
        let titleHeight: CGFloat = titleLabel.isHidden ? 0 : 16
        titleLabel.frame = CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: contentRect.width,
            height: titleHeight
        )
        
        bodyLabel.frame = CGRect(
            x: contentRect.minX,
            y: titleLabel.frame.maxY + (titleLabel.isHidden ? 0 : 2),
            width: contentRect.width,
            height: max(0, contentRect.maxY - titleLabel.frame.maxY)
        )
    }
    
    func configure(title: String?, body: String, selected: Bool) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            titleLabel.text = trimmedTitle
            titleLabel.isHidden = false
        } else {
            titleLabel.text = nil
            titleLabel.isHidden = true
        }
        
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        bodyLabel.text = trimmedBody.isEmpty ? "Empty note" : trimmedBody
        
        backgroundColor = selected
            ? UIColor.systemOrange.withAlphaComponent(0.15)
            : UIColor.systemBackground.withAlphaComponent(0.95)
        
        layer.borderColor = selected
            ? UIColor.systemOrange.cgColor
            : UIColor.secondaryLabel.withAlphaComponent(0.2).cgColor
    }
}

final class NoteAnchorOverlayView: UIView, UIGestureRecognizerDelegate {
    
    var onCreateRect: ((_ composedPageIndex: Int, _ normalizedRect: CGRect) -> Void)?
    var onSelectNote: ((_ noteID: UUID?) -> Void)?
    var onUpdateRect: ((_ noteID: UUID, _ normalizedRect: CGRect) -> Void)?
    
    weak var pdfView: PDFView? {
        didSet {
            setNeedsLayout()
            scheduleRefresh()
        }
    }
    
    var anchors: [NoteAnchorOverlayItem] = [] {
        didSet {
            anchorsByComposedIndex = Dictionary(grouping: anchors, by: { $0.composedPageIndex })
            scheduleRefresh()
        }
    }
    private var anchorsByComposedIndex: [Int: [NoteAnchorOverlayItem]] = [:]
    
    var selectedNoteID: UUID? {
        didSet { scheduleRefresh() }
    }
    
    var isCreateMode: Bool = false {
        didSet {
            activeState = .idle
            scheduleRefresh()
        }
    }
    
    var isEditingEnabled: Bool = true {
        didSet {
            if !isEditingEnabled {
                activeState = .idle
            }
            scheduleRefresh()
        }
    }
    
    var showsContentBubbles: Bool = true {
        didSet { scheduleRefresh() }
    }
    
    var pageTagsByComposedIndex: [Int: PageTagOverlayItem] = [:] {
        didSet { scheduleRefresh() }
    }
    
    var pageByComposedIndex: [Int: PDFPage] = [:] {
        didSet {
            reversePageIndexMap = Dictionary(uniqueKeysWithValues: pageByComposedIndex.map { (ObjectIdentifier($0.value), $0.key) })
            scheduleRefresh()
        }
    }
    
    private var reversePageIndexMap: [ObjectIdentifier: Int] = [:]
    
    private var shapeLayers: [UUID: CAShapeLayer] = [:]
    private var bubbleViews: [UUID: NoteContentBubbleView] = [:]
    private var tagBadgeViews: [Int: PageTagBadgeView] = [:]
    private var rectCache: [UUID: CGRect] = [:]
    
    private let previewLayer = CAShapeLayer()
    
    private enum EditMode {
        case move
        case resize
    }
    
    private enum ActiveState {
        case idle
        case creating(page: PDFPage, composedPageIndex: Int, startPagePoint: CGPoint, currentPagePoint: CGPoint)
        case editing(noteID: UUID, page: PDFPage, mode: EditMode, startPagePoint: CGPoint, originalRect: CGRect, workingRect: CGRect)
    }
    
    private var activeState: ActiveState = .idle {
        didSet { scheduleRefresh() }
    }
    
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        gesture.delegate = self
        return gesture
    }()
    
    private lazy var panGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.delegate = self
        gesture.maximumNumberOfTouches = 1
        return gesture
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        
        addGestureRecognizer(tapGesture)
        addGestureRecognizer(panGesture)
        
        previewLayer.name = "create-preview"
        previewLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        previewLayer.strokeColor = UIColor.systemBlue.cgColor
        previewLayer.lineWidth = 1.5
        previewLayer.isHidden = true
        layer.addSublayer(previewLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }
    
    func scheduleRefresh() {
        setNeedsLayout() // 接入系统渲染周期批处理绘制调用
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Never intercept multi-touch so PDFView pinch zoom always works.
        if let touches = event?.allTouches, touches.count > 1 {
            return false
        }
        
        if isCreateMode && isEditingEnabled {
            return true
        }
        
        // In view mode, pass touches through to PDFView for smooth inertial scrolling.
        if !isEditingEnabled {
            return false
        }
        
        return hitTestNote(at: point) != nil
    }
    
    func refresh() {
        guard let pdfView else {
            shapeLayers.values.forEach { $0.removeFromSuperlayer() }
            shapeLayers.removeAll()
            bubbleViews.values.forEach { $0.removeFromSuperview() }
            bubbleViews.removeAll()
            tagBadgeViews.values.forEach { $0.removeFromSuperview() }
            tagBadgeViews.removeAll()
            rectCache.removeAll()
            return
        }
        
        let visiblePageRects = visiblePageRectsAroundCurrent(pdfView: pdfView)
        var renderedIDs = Set<UUID>()
        rectCache.removeAll(keepingCapacity: true)

        for (index, pageRect) in visiblePageRects {
            guard let page = pageByComposedIndex[index] else { continue }
            if let pageAnchors = anchorsByComposedIndex[index] {
                for anchor in pageAnchors {
                    var normalizedRect = anchor.normalizedRect
                    if case .editing(let noteID, _, _, _, _, let workingRect) = activeState,
                       noteID == anchor.id {
                        normalizedRect = workingRect
                    }
                    
                    let overlayRect = overlayRectFor(normalizedRect: normalizedRect, page: page, pdfView: pdfView)
                    guard !overlayRect.isNull,
                          !overlayRect.isEmpty,
                          overlayRect.intersects(bounds) else { continue }
                    
                    renderedIDs.insert(anchor.id)
                    rectCache[anchor.id] = overlayRect
                    
                    let layer = shapeLayers[anchor.id] ?? {
                        let layer = CAShapeLayer()
                        self.layer.addSublayer(layer)
                        shapeLayers[anchor.id] = layer
                        return layer
                    }()
                    
                    let selected = anchor.id == selectedNoteID
                    layer.path = UIBezierPath(roundedRect: overlayRect, cornerRadius: 4).cgPath
                    layer.fillColor = UIColor.clear.cgColor
                    layer.strokeColor = (selected ? UIColor.systemOrange : UIColor.systemYellow).cgColor
                    layer.lineWidth = selected ? 2.0 : 1.2
                    
                    if selected && isEditingEnabled {
                        let handle = resizeHandleRect(for: overlayRect)
                        let handlePath = UIBezierPath(roundedRect: handle, cornerRadius: 2)
                        
                        let handleLayer = CAShapeLayer()
                        handleLayer.path = handlePath.cgPath
                        handleLayer.fillColor = UIColor.systemOrange.cgColor
                        handleLayer.name = "resize-handle"
                        
                        layer.sublayers?.removeAll(where: { $0.name == "resize-handle" })
                        layer.addSublayer(handleLayer)
                    } else {
                        layer.sublayers?.removeAll(where: { $0.name == "resize-handle" })
                    }
                    
                    if showsContentBubbles {
                        let bubble = bubbleViews[anchor.id] ?? {
                            let view = NoteContentBubbleView()
                            addSubview(view)
                            bubbleViews[anchor.id] = view
                            return view
                        }()
                        
                        if let bubbleFrame = bubbleFrame(for: overlayRect, pageRect: pageRect) {
                            bubble.frame = bubbleFrame
                            bubble.configure(
                                title: anchor.title,
                                body: anchor.body,
                                selected: selected
                            )
                            bubble.isHidden = false
                        } else {
                            bubble.isHidden = true
                        }
                    } else {
                        bubbleViews[anchor.id]?.isHidden = true
                    }
                }
            }
        }
        
        let obsolete = Set(shapeLayers.keys).subtracting(renderedIDs)
        for id in obsolete {
            shapeLayers[id]?.removeFromSuperlayer()
            shapeLayers.removeValue(forKey: id)
            bubbleViews[id]?.removeFromSuperview()
            bubbleViews.removeValue(forKey: id)
        }
        
        if case .creating(let page, _, let startPagePoint, let currentPagePoint) = activeState {
            let preview = normalizedRectFromPagePoints(startPagePoint, currentPagePoint, page: page)
            let overlayRect = overlayRectFor(normalizedRect: preview, page: page, pdfView: pdfView)
            previewLayer.path = UIBezierPath(roundedRect: overlayRect, cornerRadius: 4).cgPath
            previewLayer.isHidden = false
        } else {
            previewLayer.isHidden = true
        }
        
        refreshPageTagBadges(visiblePageRects: visiblePageRects)
    }
    
    // MARK: - Gestures
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let noteID = hitTestNote(at: point) {
            selectedNoteID = noteID
            onSelectNote?(noteID)
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let pdfView else { return }
        guard isEditingEnabled || isCreateMode else { return }
        
        let point = gesture.location(in: self)
        let pointInPDFView = convert(point, to: pdfView)
        
        switch gesture.state {
        case .began:
            if isCreateMode {
                beginCreating(at: pointInPDFView, pdfView: pdfView)
            } else {
                beginEditing(atOverlayPoint: point, pointInPDFView: pointInPDFView, pdfView: pdfView)
            }
            
        case .changed:
            switch activeState {
            case .creating(let page, let composedIndex, let startPoint, _):
                let currentPoint = pdfView.convert(pointInPDFView, to: page)
                activeState = .creating(
                    page: page,
                    composedPageIndex: composedIndex,
                    startPagePoint: startPoint,
                    currentPagePoint: currentPoint
                )
            case .editing(let noteID, let page, let mode, let startPoint, let originalRect, _):
                let currentPoint = pdfView.convert(pointInPDFView, to: page)
                let working = updatedRect(
                    original: originalRect,
                    mode: mode,
                    startPoint: startPoint,
                    currentPoint: currentPoint,
                    page: page
                )
                activeState = .editing(
                    noteID: noteID,
                    page: page,
                    mode: mode,
                    startPagePoint: startPoint,
                    originalRect: originalRect,
                    workingRect: working
                )
            case .idle:
                break
            }
            
        case .ended, .cancelled, .failed:
            finishPan()
            
        default:
            break
        }
    }
    
    private func beginCreating(at pointInPDFView: CGPoint, pdfView: PDFView) {
        guard let page = pdfView.page(for: pointInPDFView, nearest: true) else {
            activeState = .idle
            return
        }
        let pagePoint = pdfView.convert(pointInPDFView, to: page)
        let key = ObjectIdentifier(page)
        
        guard let composedIndex = reversePageIndexMap[key] else {
            activeState = .idle
            return
        }
        
        activeState = .creating(
            page: page,
            composedPageIndex: composedIndex,
            startPagePoint: pagePoint,
            currentPagePoint: pagePoint
        )
    }
    
    private func beginEditing(atOverlayPoint overlayPoint: CGPoint, pointInPDFView: CGPoint, pdfView: PDFView) {
        guard isEditingEnabled else {
            activeState = .idle
            return
        }
        guard let noteID = hitTestNote(at: overlayPoint),
              let anchor = anchors.first(where: { $0.id == noteID }),
              let page = pageByComposedIndex[anchor.composedPageIndex] else {
            activeState = .idle
            return
        }
        
        let pagePoint = pdfView.convert(pointInPDFView, to: page)
        let mode: EditMode
        
        if noteID == selectedNoteID,
           let rect = rectCache[noteID],
           resizeHandleRect(for: rect).insetBy(dx: -8, dy: -8).contains(overlayPoint) {
            mode = .resize
        } else {
            mode = .move
        }
        
        selectedNoteID = noteID
        onSelectNote?(noteID)
        
        activeState = .editing(
            noteID: noteID,
            page: page,
            mode: mode,
            startPagePoint: pagePoint,
            originalRect: anchor.normalizedRect,
            workingRect: anchor.normalizedRect
        )
    }
    
    private func finishPan() {
        defer { activeState = .idle }
        switch activeState {
        case .creating(let page, let composedIndex, let startPoint, let currentPoint):
            let rect = normalizedRectFromPagePoints(startPoint, currentPoint, page: page)
            guard rect.width >= 0.01, rect.height >= 0.01 else { return }
            onCreateRect?(composedIndex, rect)
            
        case .editing(let noteID, _, _, _, _, let workingRect):
            onUpdateRect?(noteID, clampNormalizedRect(workingRect))
            
        case .idle:
            break
        }
    }
    
    // MARK: - Geometry
    
    private func overlayRectFor(normalizedRect: CGRect, page: PDFPage, pdfView: PDFView) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageRect = CGRect(
            x: pageBounds.minX + normalizedRect.origin.x * pageBounds.width,
            y: pageBounds.minY + normalizedRect.origin.y * pageBounds.height,
            width: normalizedRect.width * pageBounds.width,
            height: normalizedRect.height * pageBounds.height
        )
        let inPDFView = pdfView.convert(pageRect, from: page)
        return convert(inPDFView, from: pdfView)
    }
    
    private func normalizedRectFromPagePoints(_ start: CGPoint, _ end: CGPoint, page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        
        let rect = CGRect(
            x: (minX - pageBounds.minX) / max(pageBounds.width, 1),
            y: (minY - pageBounds.minY) / max(pageBounds.height, 1),
            width: (maxX - minX) / max(pageBounds.width, 1),
            height: (maxY - minY) / max(pageBounds.height, 1)
        )
        return clampNormalizedRect(rect)
    }
    
    private func updatedRect(
        original: CGRect,
        mode: EditMode,
        startPoint: CGPoint,
        currentPoint: CGPoint,
        page: PDFPage
    ) -> CGRect {
        let bounds = page.bounds(for: .mediaBox)
        let dx = (currentPoint.x - startPoint.x) / max(bounds.width, 1)
        let dy = (currentPoint.y - startPoint.y) / max(bounds.height, 1)
        
        switch mode {
        case .move:
            let moved = CGRect(
                x: original.origin.x + dx,
                y: original.origin.y + dy,
                width: original.width,
                height: original.height
            )
            return clampNormalizedRect(moved)
        case .resize:
            let resized = CGRect(
                x: original.origin.x,
                y: original.origin.y,
                width: original.width + dx,
                height: original.height + dy
            )
            return clampNormalizedRect(resized)
        }
    }
    
    private func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        let minSize: CGFloat = 0.01
        let x = max(0, min(1, rect.origin.x))
        let y = max(0, min(1, rect.origin.y))
        let width = max(minSize, min(1 - x, rect.width))
        let height = max(minSize, min(1 - y, rect.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func hitTestNote(at point: CGPoint) -> UUID? {
        let hit = rectCache
            .filter { _, rect in rect.insetBy(dx: -8, dy: -8).contains(point) }
            .sorted { lhs, rhs in
                lhs.value.width * lhs.value.height < rhs.value.width * rhs.value.height
            }
            .first
        return hit?.key
    }
    
    private func resizeHandleRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 12, height: 12)
    }
    
    private func bubbleFrame(for anchorRect: CGRect, pageRect: CGRect) -> CGRect? {
        let horizontalGap: CGFloat = 10
        let edgeInset: CGFloat = 8
        let preferredWidth: CGFloat = min(240, max(bounds.width * 0.28, 160))
        let minimumWidth: CGFloat = 120
        let fixedHeight: CGFloat = 68
        
        let rightStartX = pageRect.maxX + horizontalGap
        let rightAvailableWidth = (bounds.width - edgeInset) - rightStartX
        
        var x: CGFloat
        var width: CGFloat
        
        if rightAvailableWidth >= minimumWidth {
            x = rightStartX
            width = min(preferredWidth, rightAvailableWidth)
        } else {
            // When zoomed in and no right margin remains, hide bubbles to avoid blocking PDF content.
            return nil
        }
        
        if width < minimumWidth {
            return nil
        }
        
        var y = anchorRect.minY
        if y + fixedHeight > bounds.height - edgeInset {
            y = bounds.height - fixedHeight - edgeInset
        }
        y = max(edgeInset, y)
        
        return CGRect(x: x, y: y, width: width, height: fixedHeight)
    }
    
    private func visiblePageRectsAroundCurrent(pdfView: PDFView) -> [Int: CGRect] {
        guard let document = pdfView.document,
              document.pageCount > 0 else {
            return [:]
        }
        
        let currentIndex: Int
        if let currentPage = pdfView.currentPage {
            let index = document.index(for: currentPage)
            currentIndex = index >= 0 ? index : 0
        } else {
            currentIndex = 0
        }
        
        let scanRadius = 4
        let lower = max(0, currentIndex - scanRadius)
        let upper = min(document.pageCount - 1, currentIndex + scanRadius)
        
        let expandedBounds = bounds.insetBy(dx: -120, dy: -160)
        var rects: [Int: CGRect] = [:]
        
        for index in lower...upper {
            guard let page = pageByComposedIndex[index] else { continue }
            let pageRect = overlayRectFor(
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                page: page,
                pdfView: pdfView
            )
            
            guard !pageRect.isNull,
                  !pageRect.isEmpty,
                  pageRect.intersects(expandedBounds) else {
                continue
            }
            rects[index] = pageRect
        }
        return rects
    }
    
    private func refreshPageTagBadges(visiblePageRects: [Int: CGRect]) {
        var renderedIndices = Set<Int>()
        
        for (index, pageRect) in visiblePageRects {
            if let item = pageTagsByComposedIndex[index], !item.chips.isEmpty {
                guard !pageRect.isNull,
                      !pageRect.isEmpty,
                      pageRect.intersects(bounds),
                      let badgeFrame = tagBadgeFrame(for: item, pageRect: pageRect) else {
                    tagBadgeViews[index]?.isHidden = true
                    continue
                }

                renderedIndices.insert(index)
                let badge = tagBadgeViews[index] ?? {
                    let view = PageTagBadgeView()
                    addSubview(view)
                    tagBadgeViews[index] = view
                    return view
                }()

                badge.frame = badgeFrame
                badge.configure(groupTitle: item.pageGroupTitle, chips: item.chips)
                badge.isHidden = false
            }
        }

        let obsoleteIndices = Set(tagBadgeViews.keys).subtracting(renderedIndices)
        for index in obsoleteIndices {
            tagBadgeViews[index]?.removeFromSuperview()
            tagBadgeViews.removeValue(forKey: index)
        }
    }
    
    private func tagBadgeFrame(for item: PageTagOverlayItem, pageRect: CGRect) -> CGRect? {
        let edgeInset: CGFloat = 8
        let horizontalGap: CGFloat = 0
        let preferredWidth: CGFloat = min(220, max(bounds.width * 0.22, 150))
        let minimumWidth: CGFloat = 120
        
        let availableLeftWidth = pageRect.minX - horizontalGap - edgeInset
        guard availableLeftWidth >= minimumWidth else {
            // Keep tags out of the PDF content area when zooming leaves no side margin.
            return nil
        }
        
        let width = min(preferredWidth, availableLeftWidth)
        let visibleChipCount = min(item.chips.count, 4)
        let overflowLine = item.chips.count > visibleChipCount ? 1 : 0
        let totalLines = visibleChipCount + overflowLine
        
        guard totalLines > 0 else { return nil }
        
        let hasTitle = !item.pageGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let titleBlockHeight: CGFloat = hasTitle ? 22 : 0
        let lineHeight: CGFloat = 20
        let lineSpacing: CGFloat = 6
        
        let chipsHeight = CGFloat(totalLines) * lineHeight
            + CGFloat(max(0, totalLines - 1)) * lineSpacing
        
        let height = 16 + titleBlockHeight + chipsHeight
        var y = pageRect.minY
        if y + height > bounds.height - edgeInset {
            y = bounds.height - height - edgeInset
        }
        y = max(edgeInset, y)
        
        let x = pageRect.minX - horizontalGap - width
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === tapGesture {
            return !isCreateMode
        }
        
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        
        if !isEditingEnabled {
            return false
        }
        
        if isCreateMode {
            return true
        }
        
        let point = pan.location(in: self)
        return hitTestNote(at: point) != nil
    }
}

private extension UIColor {
    static func paperHex(_ hex: String, fallback: UIColor) -> UIColor {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&int) else {
            return fallback
        }
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch value.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return fallback
        }
        return UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
