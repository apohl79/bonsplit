import Foundation
import SwiftUI

/// Central controller managing the entire split view state (internal implementation)
@Observable
@MainActor
final class SplitViewController {
    /// The root node of the split tree
    var rootNode: SplitNode

    /// Currently focused pane ID
    var focusedPaneId: PaneID?

    /// Tab currently being dragged (for visual feedback and hit-testing).
    /// This is @Observable so SwiftUI views react (e.g. allowsHitTesting).
    var draggingTab: TabItem?

    /// Monotonic counter incremented on each drag start. Used to invalidate stale
    /// timeout timers that would otherwise cancel a new drag of the same tab.
    var dragGeneration: Int = 0

    /// Source pane of the dragging tab
    var dragSourcePaneId: PaneID?

    /// Non-observable drag session state. Drop delegates read these instead of the
    /// @Observable properties above, because SwiftUI batches observable updates and
    /// createItemProvider's writes may not be visible to validateDrop/performDrop yet.
    @ObservationIgnored var activeDragTab: TabItem?
    @ObservationIgnored var activeDragSourcePaneId: PaneID?

    /// When false, drop delegates reject all drags and NSViews are hidden.
    /// Mirrors BonsplitController.isInteractive. Must be observable so
    /// updateNSView is called to toggle isHidden on the AppKit containers.
    var isInteractive: Bool = true

    /// Handler for file/URL drops from external apps (e.g. Finder).
    /// Receives the dropped URLs and the pane ID where the drop occurred.
    @ObservationIgnored var onFileDrop: ((_ urls: [URL], _ paneId: PaneID) -> Bool)?

    /// During drop, SwiftUI may keep the source tab view alive briefly (default removal animation)
    /// even after we've updated the model. Hide it explicitly so it disappears immediately.
    var dragHiddenSourceTabId: UUID?
    var dragHiddenSourcePaneId: PaneID?

    /// Single source of truth for pane-edge drop overlay ownership.
    /// Only this pane should render a drop zone at any time.
    var activeDropPaneId: PaneID?
    var activeDropZone: DropZone?
    @ObservationIgnored private var lastDropUpdateUptimeByPane: [PaneID: TimeInterval] = [:]
    @ObservationIgnored private var lastDropUpdateZoneByPane: [PaneID: DropZone] = [:]
    @ObservationIgnored private var dropTargetClearToken: UInt64 = 0

    /// Current frame of the entire split view container
    var containerFrame: CGRect = .zero

    /// Flag to prevent notification loops during external updates
    var isExternalUpdateInProgress: Bool = false

    /// Timestamp of last geometry notification for debouncing
    var lastGeometryNotificationTime: TimeInterval = 0

    /// Callback for geometry changes
    var onGeometryChange: (() -> Void)?

    init(rootNode: SplitNode? = nil) {
        if let rootNode {
            self.rootNode = rootNode
        } else {
            // Initialize with a single pane containing a welcome tab
            let welcomeTab = TabItem(title: "Welcome", icon: "star")
            let initialPane = PaneState(tabs: [welcomeTab])
            self.rootNode = .pane(initialPane)
            self.focusedPaneId = initialPane.id
        }
    }

    // MARK: - Focus Management

    func setActiveDropTarget(paneId: PaneID, zone: DropZone) {
        // Cancel a pending deferred clear when ownership is reaffirmed in the same drag turn.
        dropTargetClearToken &+= 1
        let oldPane = activeDropPaneId
        let oldZone = activeDropZone
        guard oldPane != paneId || oldZone != zone else { return }
#if DEBUG
        dlog(
            "pane.dropTarget oldPane=\(oldPane.map { String($0.id.uuidString.prefix(5)) } ?? "nil") " +
            "oldZone=\(oldZone.map { String(describing: $0) } ?? "none") " +
            "newPane=\(paneId.id.uuidString.prefix(5)) newZone=\(zone)"
        )
#endif
        if let oldPane, oldPane != paneId {
            clearDropUpdateTiming(for: oldPane, reason: "ownerChanged")
        }
        activeDropPaneId = paneId
        activeDropZone = zone
    }

    func clearActiveDropTarget(for paneId: PaneID? = nil, reason: String? = nil) {
        if let paneId, activeDropPaneId != paneId {
            return
        }
        guard activeDropPaneId != nil || activeDropZone != nil else { return }
        let clearReason = reason ?? "unspecified"
        let dragInProgress = draggingTab != nil || activeDragTab != nil
        let shouldDefer = clearReason == "dropExited" && dragInProgress

        if shouldDefer {
            let expectedPaneUUID = activeDropPaneId?.id
            let expectedZone = activeDropZone
            dropTargetClearToken &+= 1
            let clearToken = dropTargetClearToken
#if DEBUG
            dlog(
                "pane.dropTarget.clear.defer pane=\(expectedPaneUUID.map { String($0.uuidString.prefix(5)) } ?? "nil") " +
                "zone=\(expectedZone.map { String(describing: $0) } ?? "none") reason=\(clearReason)"
            )
#endif
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                guard self.dropTargetClearToken == clearToken else {
#if DEBUG
                    dlog("pane.dropTarget.clear.deferSkip reason=tokenInvalidated")
#endif
                    return
                }
                guard self.activeDropPaneId?.id == expectedPaneUUID,
                      self.activeDropZone == expectedZone else {
#if DEBUG
                    dlog("pane.dropTarget.clear.deferSkip reason=ownerChanged")
#endif
                    return
                }
                self.applyActiveDropTargetClear(reason: clearReason, clearTimingFor: self.activeDropPaneId)
            }
            return
        }

        // Invalidate any pending deferred clear before doing an immediate clear.
        dropTargetClearToken &+= 1
        applyActiveDropTargetClear(reason: clearReason, clearTimingFor: paneId)
    }

    private func applyActiveDropTargetClear(reason: String, clearTimingFor paneId: PaneID?) {
#if DEBUG
        dlog(
            "pane.dropTarget.clear pane=\(activeDropPaneId.map { String($0.id.uuidString.prefix(5)) } ?? "nil") " +
            "zone=\(activeDropZone.map { String(describing: $0) } ?? "none") " +
            "reason=\(reason)"
        )
#endif
        activeDropPaneId = nil
        activeDropZone = nil
        clearDropUpdateTiming(for: paneId, reason: "dropTargetCleared")
    }

    /// Record drop-update cadence so we can detect stutters while dragging.
    /// A long delta between updates usually indicates a frame drop in drag handling.
    func noteDropUpdateTiming(paneId: PaneID, zone: DropZone, event: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let last = lastDropUpdateUptimeByPane[paneId]
        let previousZone = lastDropUpdateZoneByPane[paneId]
        lastDropUpdateUptimeByPane[paneId] = now
        lastDropUpdateZoneByPane[paneId] = zone

        guard let last else { return }
        let deltaMs = (now - last) * 1000
        guard deltaMs >= 20 else { return }

#if DEBUG
        let severity: String = deltaMs >= 40 ? "jank" : "slow"
        dlog(
            "pane.dropTiming.\(severity) pane=\(paneId.id.uuidString.prefix(5)) event=\(event) " +
            "zone=\(zone) prevZone=\(previousZone.map { String(describing: $0) } ?? "none") " +
            "owner=\(activeDropPaneId?.id.uuidString.prefix(5) ?? "nil") " +
            "deltaMs=\(String(format: "%.1f", deltaMs))"
        )
#endif
    }

    func clearDropUpdateTiming(for paneId: PaneID? = nil, reason: String) {
        if let paneId {
            lastDropUpdateUptimeByPane.removeValue(forKey: paneId)
            lastDropUpdateZoneByPane.removeValue(forKey: paneId)
#if DEBUG
            dlog("pane.dropTiming.clear pane=\(paneId.id.uuidString.prefix(5)) reason=\(reason)")
#endif
            return
        }

        guard !lastDropUpdateUptimeByPane.isEmpty || !lastDropUpdateZoneByPane.isEmpty else { return }
        lastDropUpdateUptimeByPane.removeAll(keepingCapacity: false)
        lastDropUpdateZoneByPane.removeAll(keepingCapacity: false)
#if DEBUG
        dlog("pane.dropTiming.clear pane=all reason=\(reason)")
#endif
    }

    /// Set focus to a specific pane
    func focusPane(_ paneId: PaneID) {
        guard rootNode.findPane(paneId) != nil else { return }
#if DEBUG
        dlog("focus.bonsplit pane=\(paneId.id.uuidString.prefix(5))")
#endif
        focusedPaneId = paneId
    }

    /// Get the currently focused pane state
    var focusedPane: PaneState? {
        guard let focusedPaneId else { return nil }
        return rootNode.findPane(focusedPaneId)
    }

    // MARK: - Split Operations

    /// Split the specified pane in the given orientation
    func splitPane(_ paneId: PaneID, orientation: SplitOrientation, with newTab: TabItem? = nil) {
        rootNode = splitNodeRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            newTab: newTab
        )
    }

    private func splitNodeRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        newTab: TabItem?
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane - empty if no tab provided (gives developer full control)
                let newPane: PaneState
                if let tab = newTab {
                    newPane = PaneState(tabs: [tab])
                } else {
                    newPane = PaneState(tabs: [])
                }

                // Start with divider at the edge so there's no flash before animation
                let splitState = SplitState(
                    orientation: orientation,
                    first: .pane(paneState),
                    second: .pane(newPane),
                    // Keep the model at its steady-state ratio. The view layer can still animate
                    // from an edge via animationOrigin, but the model should never represent a
                    // fully-collapsed pane (which can get stuck under view reparenting timing).
                    dividerPosition: 0.5,
                    animationOrigin: .fromSecond  // New pane slides in from right/bottom
                )

                // Focus the new pane
                focusedPaneId = newPane.id

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTab: newTab
            )
            splitState.second = splitNodeRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTab: newTab
            )
            return .split(splitState)
        }
    }

    /// Split a pane with a specific tab, optionally inserting the new pane first
    func splitPaneWithTab(_ paneId: PaneID, orientation: SplitOrientation, tab: TabItem, insertFirst: Bool) {
        rootNode = splitNodeWithTabRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            tab: tab,
            insertFirst: insertFirst
        )
    }

    private func splitNodeWithTabRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        tab: TabItem,
        insertFirst: Bool
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane with the tab
                let newPane = PaneState(tabs: [tab])

                // Start with divider at the edge so there's no flash before animation
                let splitState: SplitState
                if insertFirst {
                    // New pane goes first (left or top).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(newPane),
                        second: .pane(paneState),
                        dividerPosition: 0.5,
                        animationOrigin: .fromFirst
                    )
                } else {
                    // New pane goes second (right or bottom).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(paneState),
                        second: .pane(newPane),
                        dividerPosition: 0.5,
                        animationOrigin: .fromSecond
                    )
                }

                // Focus the new pane
                focusedPaneId = newPane.id

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeWithTabRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tab: tab,
                insertFirst: insertFirst
            )
            splitState.second = splitNodeWithTabRecursively(
                node: splitState.second,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tab: tab,
                insertFirst: insertFirst
            )
            return .split(splitState)
        }
    }

    /// Close a pane and collapse the split
    func closePane(_ paneId: PaneID) {
        // Don't close the last pane
        guard rootNode.allPaneIds.count > 1 else { return }

        let (newRoot, siblingPaneId) = closePaneRecursively(node: rootNode, targetPaneId: paneId)

        if let newRoot {
            rootNode = newRoot
        }

        // Focus the sibling or first available pane
        if let siblingPaneId {
            focusedPaneId = siblingPaneId
        } else if let firstPane = rootNode.allPaneIds.first {
            focusedPaneId = firstPane
        }
    }

    private func closePaneRecursively(
        node: SplitNode,
        targetPaneId: PaneID
    ) -> (SplitNode?, PaneID?) {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                return (nil, nil)
            }
            return (node, nil)

        case .split(let splitState):
            // Check if either direct child is the target
            if case .pane(let firstPane) = splitState.first, firstPane.id == targetPaneId {
                let focusTarget = splitState.second.allPaneIds.first
                return (splitState.second, focusTarget)
            }

            if case .pane(let secondPane) = splitState.second, secondPane.id == targetPaneId {
                let focusTarget = splitState.first.allPaneIds.first
                return (splitState.first, focusTarget)
            }

            // Recursively check children
            let (newFirst, focusFromFirst) = closePaneRecursively(node: splitState.first, targetPaneId: targetPaneId)
            if newFirst == nil {
                return (splitState.second, splitState.second.allPaneIds.first)
            }

            let (newSecond, focusFromSecond) = closePaneRecursively(node: splitState.second, targetPaneId: targetPaneId)
            if newSecond == nil {
                return (splitState.first, splitState.first.allPaneIds.first)
            }

            if let newFirst { splitState.first = newFirst }
            if let newSecond { splitState.second = newSecond }

            return (.split(splitState), focusFromFirst ?? focusFromSecond)
        }
    }

    // MARK: - Tab Operations

    /// Add a tab to the focused pane (or specified pane)
    func addTab(_ tab: TabItem, toPane paneId: PaneID? = nil, atIndex index: Int? = nil) {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              let pane = rootNode.findPane(targetPaneId) else { return }

        if let index {
            pane.insertTab(tab, at: index)
        } else {
            pane.addTab(tab)
        }
    }

    /// Move a tab from one pane to another
    func moveTab(_ tab: TabItem, from sourcePaneId: PaneID, to targetPaneId: PaneID, atIndex index: Int? = nil) {
        guard let sourcePane = rootNode.findPane(sourcePaneId),
              let targetPane = rootNode.findPane(targetPaneId) else { return }

        // Remove from source
        sourcePane.removeTab(tab.id)

        // Add to target
        if let index {
            targetPane.insertTab(tab, at: index)
        } else {
            targetPane.addTab(tab)
        }

        // Focus target pane
        focusPane(targetPaneId)

        // If source pane is now empty and not the only pane, close it
        if sourcePane.tabs.isEmpty && rootNode.allPaneIds.count > 1 {
            closePane(sourcePaneId)
        }
    }

    /// Close a tab in a specific pane
    func closeTab(_ tabId: UUID, inPane paneId: PaneID) {
        guard let pane = rootNode.findPane(paneId) else { return }

        pane.removeTab(tabId)

        // If pane is now empty and not the only pane, close it
        if pane.tabs.isEmpty && rootNode.allPaneIds.count > 1 {
            closePane(paneId)
        }
    }

    // MARK: - Keyboard Navigation

    /// Navigate focus to an adjacent pane based on spatial position
    func navigateFocus(direction: NavigationDirection) {
        guard let currentPaneId = focusedPaneId else { return }

        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == currentPaneId })?.bounds else { return }

        if let targetPaneId = findBestNeighbor(from: currentBounds, currentPaneId: currentPaneId,
                                               direction: direction, allPaneBounds: allPaneBounds) {
            focusPane(targetPaneId)
        }
        // No neighbor found = at edge, do nothing
    }

    private func findBestNeighbor(from currentBounds: CGRect, currentPaneId: PaneID,
                                  direction: NavigationDirection, allPaneBounds: [PaneBounds]) -> PaneID? {
        let epsilon: CGFloat = 0.001

        // Filter to panes in the target direction
        let candidates = allPaneBounds.filter { paneBounds in
            guard paneBounds.paneId != currentPaneId else { return false }
            let b = paneBounds.bounds
            switch direction {
            case .left:  return b.maxX <= currentBounds.minX + epsilon
            case .right: return b.minX >= currentBounds.maxX - epsilon
            case .up:    return b.maxY <= currentBounds.minY + epsilon
            case .down:  return b.minY >= currentBounds.maxY - epsilon
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Score by overlap (perpendicular axis) and distance
        let scored: [(PaneID, CGFloat, CGFloat)] = candidates.map { c in
            let overlap: CGFloat
            let distance: CGFloat

            switch direction {
            case .left, .right:
                // Vertical overlap for horizontal movement
                overlap = max(0, min(currentBounds.maxY, c.bounds.maxY) - max(currentBounds.minY, c.bounds.minY))
                distance = direction == .left ? (currentBounds.minX - c.bounds.maxX) : (c.bounds.minX - currentBounds.maxX)
            case .up, .down:
                // Horizontal overlap for vertical movement
                overlap = max(0, min(currentBounds.maxX, c.bounds.maxX) - max(currentBounds.minX, c.bounds.minX))
                distance = direction == .up ? (currentBounds.minY - c.bounds.maxY) : (c.bounds.minY - currentBounds.maxY)
            }

            return (c.paneId, overlap, distance)
        }

        // Sort: prefer more overlap, then closer distance
        let sorted = scored.sorted { a, b in
            if abs(a.1 - b.1) > epsilon { return a.1 > b.1 }
            return a.2 < b.2
        }

        return sorted.first?.0
    }

    /// Create a new tab in the focused pane
    func createNewTab() {
        guard let pane = focusedPane else { return }
        let count = pane.tabs.count + 1
        let newTab = TabItem(title: "Untitled \(count)", icon: "doc")
        pane.addTab(newTab)
    }

    /// Close the currently selected tab in the focused pane
    func closeSelectedTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId else { return }
        closeTab(selectedTabId, inPane: pane.id)
    }

    /// Select the previous tab in the focused pane
    func selectPreviousTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : pane.tabs.count - 1
        pane.selectTab(pane.tabs[newIndex].id)
    }

    /// Select the next tab in the focused pane
    func selectNextTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex < pane.tabs.count - 1 ? currentIndex + 1 : 0
        pane.selectTab(pane.tabs[newIndex].id)
    }

    // MARK: - Split State Access

    /// Find a split state by its UUID
    func findSplit(_ splitId: UUID) -> SplitState? {
        return findSplitRecursively(in: rootNode, id: splitId)
    }

    private func findSplitRecursively(in node: SplitNode, id: UUID) -> SplitState? {
        switch node {
        case .pane:
            return nil
        case .split(let splitState):
            if splitState.id == id {
                return splitState
            }
            if let found = findSplitRecursively(in: splitState.first, id: id) {
                return found
            }
            return findSplitRecursively(in: splitState.second, id: id)
        }
    }

    /// Get all split states in the tree
    var allSplits: [SplitState] {
        return collectSplits(from: rootNode)
    }

    private func collectSplits(from node: SplitNode) -> [SplitState] {
        switch node {
        case .pane:
            return []
        case .split(let splitState):
            return [splitState] + collectSplits(from: splitState.first) + collectSplits(from: splitState.second)
        }
    }
}
