#if DEBUG
import AppKit
import SwiftUI

public struct BonsplitTabChromeDebugScenario: Sendable {
    public var tab: Tab
    public var isSelected: Bool
    public var isHovered: Bool
    public var isCloseHovered: Bool
    public var isClosePressed: Bool
    public var showsZoomIndicator: Bool
    public var isZoomHovered: Bool
    public var isZoomPressed: Bool
    public var appearance: BonsplitConfiguration.Appearance
    public var saturation: Double
    public var fixedSpinnerPhaseDegrees: Double?

    public init(
        tab: Tab,
        isSelected: Bool,
        isHovered: Bool,
        isCloseHovered: Bool,
        isClosePressed: Bool,
        showsZoomIndicator: Bool,
        isZoomHovered: Bool,
        isZoomPressed: Bool,
        appearance: BonsplitConfiguration.Appearance = .default,
        saturation: Double = 1.0,
        fixedSpinnerPhaseDegrees: Double? = nil
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isCloseHovered = isCloseHovered
        self.isClosePressed = isClosePressed
        self.showsZoomIndicator = showsZoomIndicator
        self.isZoomHovered = isZoomHovered
        self.isZoomPressed = isZoomPressed
        self.appearance = appearance
        self.saturation = saturation
        self.fixedSpinnerPhaseDegrees = fixedSpinnerPhaseDegrees
    }
}

struct BonsplitTabChromeDebugInteractionState {
    let isHovered: Bool
    let isCloseHovered: Bool
    let isClosePressed: Bool
    let isZoomHovered: Bool
    let isZoomPressed: Bool
    let fixedSpinnerPhaseDegrees: Double?
}

enum BonsplitTabChromeDebugContext {
    @MainActor static var current: BonsplitTabChromeDebugInteractionState?
}

@MainActor
public enum BonsplitTabChromeDebugRenderer {
    public static func renderImage(
        scenario: BonsplitTabChromeDebugScenario,
        scale: CGFloat = 2
    ) -> NSImage? {
        let tab = TabItem(
            id: scenario.tab.id.uuid,
            title: scenario.tab.title,
            hasCustomTitle: scenario.tab.hasCustomTitle,
            icon: scenario.tab.icon,
            iconImageData: scenario.tab.iconImageData,
            kind: scenario.tab.kind,
            isDirty: scenario.tab.isDirty,
            showsNotificationBadge: scenario.tab.showsNotificationBadge,
            isLoading: scenario.tab.isLoading,
            isPinned: scenario.tab.isPinned
        )

        let contextMenuState = TabContextMenuState(
            isPinned: scenario.tab.isPinned,
            isUnread: scenario.tab.showsNotificationBadge,
            isBrowser: scenario.tab.kind == "browser",
            isTerminal: scenario.tab.kind == "terminal",
            hasCustomTitle: scenario.tab.hasCustomTitle,
            canCloseToLeft: false,
            canCloseToRight: false,
            canCloseOthers: false,
            canMoveToLeftPane: false,
            canMoveToRightPane: false,
            isZoomed: scenario.showsZoomIndicator,
            hasSplits: scenario.showsZoomIndicator,
            shortcuts: [:]
        )

        let debugInteractionState = BonsplitTabChromeDebugInteractionState(
            isHovered: scenario.isHovered,
            isCloseHovered: scenario.isCloseHovered,
            isClosePressed: scenario.isClosePressed,
            isZoomHovered: scenario.isZoomHovered,
            isZoomPressed: scenario.isZoomPressed,
            fixedSpinnerPhaseDegrees: scenario.fixedSpinnerPhaseDegrees
        )

        let previousDebugState = BonsplitTabChromeDebugContext.current
        BonsplitTabChromeDebugContext.current = debugInteractionState
        defer {
            BonsplitTabChromeDebugContext.current = previousDebugState
        }

        let rootView = TabItemView(
            tab: tab,
            isSelected: scenario.isSelected,
            isPaneFocused: scenario.saturation > 0.5,
            showsZoomIndicator: scenario.showsZoomIndicator,
            appearance: scenario.appearance,
            saturation: scenario.saturation,
            controlShortcutDigit: nil,
            showsControlShortcutHint: false,
            shortcutModifierSymbol: "^",
            contextMenuState: contextMenuState,
            onSelect: {},
            onClose: {},
            onZoomToggle: {},
            onContextAction: { _ in }
        )
        .allowsHitTesting(false)

        let host = NSHostingView(rootView: rootView)
        let fittingWidth = ceil(host.fittingSize.width)
        host.frame = CGRect(x: 0, y: 0, width: fittingWidth, height: TabBarMetrics.tabHeight)
        host.layoutSubtreeIfNeeded()
        return bonsplitTabChromeSnapshotImage(
            for: host,
            scale: scale,
            backgroundColor: TabBarColors.nsColorPaneBackground(for: scenario.appearance)
        )
    }
}

private func bonsplitTabChromeSnapshotImage(
    for view: NSView,
    scale: CGFloat,
    backgroundColor: NSColor
) -> NSImage? {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
    let width = max(1, Int(ceil(view.bounds.width * scale)))
    let height = max(1, Int(ceil(view.bounds.height * scale)))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    rep.size = view.bounds.size
    if let context = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        backgroundColor.setFill()
        NSBezierPath(rect: view.bounds).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
}
#endif
