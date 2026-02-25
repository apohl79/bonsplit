import XCTest
@testable import Bonsplit
import AppKit

final class BonsplitTests: XCTestCase {
    private final class TabContextActionDelegateSpy: BonsplitDelegate {
        var action: TabContextAction?
        var tabId: TabID?
        var paneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Tab, inPane pane: PaneID) {
            self.action = action
            self.tabId = tab.id
            self.paneId = pane
        }
    }

    @MainActor
    func testControllerCreation() {
        let controller = BonsplitController()
        XCTAssertNotNil(controller.focusedPaneId)
    }

    @MainActor
    func testTabCreation() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")
        XCTAssertNotNil(tabId)
    }

    @MainActor
    func testTabRetrieval() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")!
        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.title, "Test Tab")
        XCTAssertEqual(tab?.icon, "doc")
    }

    @MainActor
    func testTabUpdate() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Original", icon: "doc")!

        controller.updateTab(tabId, title: "Updated", isDirty: true)

        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.title, "Updated")
        XCTAssertEqual(tab?.isDirty, true)
    }

    @MainActor
    func testTabClose() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")!

        let closed = controller.closeTab(tabId)

        XCTAssertTrue(closed)
        XCTAssertNil(controller.tab(tabId))
    }

    @MainActor
    func testCloseSelectedTabKeepsIndexStableWhenPossible() {
        do {
            let config = BonsplitConfiguration(newTabPosition: .end)
            let controller = BonsplitController(configuration: config)

            let tab0 = controller.createTab(title: "0")!
            let tab1 = controller.createTab(title: "1")!
            let tab2 = controller.createTab(title: "2")!

            let pane = controller.focusedPaneId!

            controller.selectTab(tab1)
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab1)

            _ = controller.closeTab(tab1)

            // Order is [0,1,2] and 1 was selected; after close we should select 2 (same index).
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab2)
            XCTAssertNotNil(controller.tab(tab0))
        }

        do {
            let config = BonsplitConfiguration(newTabPosition: .end)
            let controller = BonsplitController(configuration: config)

            let tab0 = controller.createTab(title: "0")!
            let tab1 = controller.createTab(title: "1")!
            let tab2 = controller.createTab(title: "2")!

            let pane = controller.focusedPaneId!

            controller.selectTab(tab2)
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab2)

            _ = controller.closeTab(tab2)

            // Closing last should select previous.
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab1)
            XCTAssertNotNil(controller.tab(tab0))
        }
    }

    @MainActor
    func testConfiguration() {
        let config = BonsplitConfiguration(
            allowSplits: false,
            allowCloseTabs: true
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertFalse(controller.configuration.allowSplits)
        XCTAssertTrue(controller.configuration.allowCloseTabs)
    }

    func testConfigurationSupportsContentManagedDropOverlayKinds() {
        let config = BonsplitConfiguration(
            contentManagedDropOverlayTabKinds: ["terminal"]
        )
        XCTAssertEqual(config.contentManagedDropOverlayTabKinds, ["terminal"])
    }

    func testPaneDropPlaceholderPolicyRespectsContentManagedKinds() {
        XCTAssertFalse(
            PaneDropOverlayPolicy.shouldRenderSwiftUIDropPlaceholder(
                selectedTabKind: "terminal",
                contentManagedKinds: ["terminal"]
            )
        )
        XCTAssertTrue(
            PaneDropOverlayPolicy.shouldRenderSwiftUIDropPlaceholder(
                selectedTabKind: "browser",
                contentManagedKinds: ["terminal"]
            )
        )
        XCTAssertTrue(
            PaneDropOverlayPolicy.shouldRenderSwiftUIDropPlaceholder(
                selectedTabKind: nil,
                contentManagedKinds: ["terminal"]
            )
        )
    }

    func testPaneDropOverlayVisibilityIsOwnedByActivePane() {
        let paneA = PaneID()
        let paneB = PaneID()

        XCTAssertEqual(
            PaneDropOverlayPolicy.visibleDropZone(
                for: paneA,
                activePaneId: paneA,
                activeZone: .right
            ),
            .right
        )
        XCTAssertNil(
            PaneDropOverlayPolicy.visibleDropZone(
                for: paneB,
                activePaneId: paneA,
                activeZone: .right
            )
        )
        XCTAssertNil(
            PaneDropOverlayPolicy.visibleDropZone(
                for: paneA,
                activePaneId: nil,
                activeZone: .right
            )
        )
    }

    func testPaneDropOverlayUpdatePolicyRejectsStaleNonOwnerUpdates() {
        let paneA = PaneID()
        let paneB = PaneID()

        XCTAssertTrue(
            PaneDropOverlayPolicy.shouldAcceptDropUpdate(
                for: paneA,
                activePaneId: nil
            )
        )
        XCTAssertTrue(
            PaneDropOverlayPolicy.shouldAcceptDropUpdate(
                for: paneA,
                activePaneId: paneA
            )
        )
        XCTAssertFalse(
            PaneDropOverlayPolicy.shouldAcceptDropUpdate(
                for: paneA,
                activePaneId: paneB
            )
        )
    }

    func testTabTransferDataMarksCurrentProcessPayload() {
        let transfer = TabTransferData(
            tab: TabItem(title: "Drag", icon: "terminal.fill"),
            sourcePaneId: UUID()
        )
        XCTAssertTrue(transfer.isFromCurrentProcess)
    }

    func testTabTransferDataLegacyPayloadDefaultsToForeignProcess() throws {
        let original = TabTransferData(
            tab: TabItem(title: "Drag", icon: "terminal.fill"),
            sourcePaneId: UUID()
        )
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "sourceProcessId")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TabTransferData.self, from: legacyData)
        XCTAssertFalse(decoded.isFromCurrentProcess)
    }

    @MainActor
    func testDropTargetClearDefersForDropExitedDuringActiveDrag() async {
        let controller = SplitViewController()
        let pane = controller.focusedPaneId!
        controller.draggingTab = TabItem(title: "Drag", icon: "terminal.fill")
        controller.setActiveDropTarget(paneId: pane, zone: .top)

        controller.clearActiveDropTarget(for: pane, reason: "dropExited")

        // During drag handoff, clear is deferred by one turn to avoid one-frame flashes.
        XCTAssertEqual(controller.activeDropPaneId, pane)
        XCTAssertEqual(controller.activeDropZone, .top)

        await Task.yield()
        await Task.yield()

        XCTAssertNil(controller.activeDropPaneId)
        XCTAssertNil(controller.activeDropZone)
    }

    @MainActor
    func testDropTargetDeferredClearCancelsWhenNewOwnerArrives() async {
        let controller = SplitViewController()
        let paneA = controller.focusedPaneId!
        let paneB = PaneID()
        controller.draggingTab = TabItem(title: "Drag", icon: "terminal.fill")
        controller.setActiveDropTarget(paneId: paneA, zone: .top)

        controller.clearActiveDropTarget(for: paneA, reason: "dropExited")
        controller.setActiveDropTarget(paneId: paneB, zone: .right)

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(controller.activeDropPaneId, paneB)
        XCTAssertEqual(controller.activeDropZone, .right)
    }

    func testDefaultSplitButtonTooltips() {
        let defaults = BonsplitConfiguration.SplitButtonTooltips.default
        XCTAssertEqual(defaults.newTerminal, "New Terminal")
        XCTAssertEqual(defaults.newBrowser, "New Browser")
        XCTAssertEqual(defaults.splitRight, "Split Right")
        XCTAssertEqual(defaults.splitDown, "Split Down")
    }

    @MainActor
    func testConfigurationAcceptsCustomSplitButtonTooltips() {
        let customTooltips = BonsplitConfiguration.SplitButtonTooltips(
            newTerminal: "Terminal (⌘T)",
            newBrowser: "Browser (⌘⇧L)",
            splitRight: "Split Right (⌘D)",
            splitDown: "Split Down (⌘⇧D)"
        )
        let config = BonsplitConfiguration(
            appearance: .init(
                splitButtonTooltips: customTooltips
            )
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertEqual(controller.configuration.appearance.splitButtonTooltips, customTooltips)
    }

    func testChromeBackgroundHexOverrideParsesForPaneBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#FDF6E3")
        )
        let color = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(Int(round(red * 255)), 253)
        XCTAssertEqual(Int(round(green * 255)), 246)
        XCTAssertEqual(Int(round(blue * 255)), 227)
        XCTAssertEqual(Int(round(alpha * 255)), 255)
    }

    func testChromeBorderHexOverrideParsesForSeparatorColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822", borderHex: "#112233")
        )
        let color = TabBarColors.nsColorSeparator(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(Int(round(red * 255)), 17)
        XCTAssertEqual(Int(round(green * 255)), 34)
        XCTAssertEqual(Int(round(blue * 255)), 51)
        XCTAssertEqual(Int(round(alpha * 255)), 255)
    }

    func testInvalidChromeBackgroundHexFallsBackToPaneDefaultColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#ZZZZZZ")
        )
        let resolved = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!
        let fallback = NSColor.textBackgroundColor.usingColorSpace(.sRGB)!

        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        resolved.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        fallback.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)

        XCTAssertEqual(rr, fr, accuracy: 0.0001)
        XCTAssertEqual(rg, fg, accuracy: 0.0001)
        XCTAssertEqual(rb, fb, accuracy: 0.0001)
        XCTAssertEqual(ra, fa, accuracy: 0.0001)
    }

    func testPartiallyInvalidChromeBackgroundHexFallsBackToPaneDefaultColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#FF000G")
        )
        let resolved = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!
        let fallback = NSColor.textBackgroundColor.usingColorSpace(.sRGB)!

        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        resolved.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        fallback.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)

        XCTAssertEqual(rr, fr, accuracy: 0.0001)
        XCTAssertEqual(rg, fg, accuracy: 0.0001)
        XCTAssertEqual(rb, fb, accuracy: 0.0001)
        XCTAssertEqual(ra, fa, accuracy: 0.0001)
    }

    func testInactiveTextUsesLightForegroundOnDarkCustomChromeBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822")
        )
        let color = TabBarColors.nsColorInactiveText(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertGreaterThan(red, 0.5)
        XCTAssertGreaterThan(green, 0.5)
        XCTAssertGreaterThan(blue, 0.5)
        XCTAssertGreaterThan(alpha, 0.6)
    }

    func testSplitActionPressedStateUsesHigherContrast() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822")
        )

        let idleIcon = TabBarColors.nsColorSplitActionIcon(for: appearance, isPressed: false).usingColorSpace(.sRGB)!
        let pressedIcon = TabBarColors.nsColorSplitActionIcon(for: appearance, isPressed: true).usingColorSpace(.sRGB)!

        var idleAlpha: CGFloat = 0
        idleIcon.getRed(nil, green: nil, blue: nil, alpha: &idleAlpha)
        var pressedAlpha: CGFloat = 0
        pressedIcon.getRed(nil, green: nil, blue: nil, alpha: &pressedAlpha)

        XCTAssertGreaterThan(pressedAlpha, idleAlpha)
    }

    @MainActor
    func testMoveTabNoopAfterItself() {
        let t0 = TabItem(title: "0")
        let t1 = TabItem(title: "1")
        let pane = PaneState(tabs: [t0, t1], selectedTabId: t1.id)

        // Dragging the last tab to the right corresponds to moving it to `tabs.count`,
        // which should be treated as a no-op.
        pane.moveTab(from: 1, to: 2)
        XCTAssertEqual(pane.tabs.map(\.id), [t0.id, t1.id])
        XCTAssertEqual(pane.selectedTabId, t1.id)

        // Still allow real moves.
        pane.moveTab(from: 0, to: 2)
        XCTAssertEqual(pane.tabs.map(\.id), [t1.id, t0.id])
        XCTAssertEqual(pane.selectedTabId, t1.id)
    }

    @MainActor
    func testPinnedTabInsertionsStayAheadOfUnpinnedTabs() {
        let unpinnedA = TabItem(title: "A", isPinned: false)
        let unpinnedB = TabItem(title: "B", isPinned: false)
        let pinned = TabItem(title: "Pinned", isPinned: true)
        let pane = PaneState(tabs: [unpinnedA, unpinnedB], selectedTabId: unpinnedA.id)

        pane.insertTab(pinned, at: 2)

        XCTAssertEqual(pane.tabs.map(\.isPinned), [true, false, false])
        XCTAssertEqual(pane.tabs.first?.id, pinned.id)
    }

    @MainActor
    func testMovingUnpinnedTabCannotCrossPinnedBoundary() {
        let pinnedA = TabItem(title: "Pinned A", isPinned: true)
        let pinnedB = TabItem(title: "Pinned B", isPinned: true)
        let unpinnedA = TabItem(title: "A", isPinned: false)
        let unpinnedB = TabItem(title: "B", isPinned: false)
        let pane = PaneState(
            tabs: [pinnedA, pinnedB, unpinnedA, unpinnedB],
            selectedTabId: unpinnedB.id
        )

        // Attempt to move an unpinned tab ahead of pinned tabs; move should clamp to
        // the first unpinned position.
        pane.moveTab(from: 3, to: 0)

        XCTAssertEqual(pane.tabs.map(\.id), [pinnedA.id, pinnedB.id, unpinnedB.id, unpinnedA.id])
        XCTAssertEqual(pane.tabs.prefix(2).allSatisfy(\.isPinned), true)
        XCTAssertEqual(pane.tabs.suffix(2).allSatisfy { !$0.isPinned }, true)
    }

    @MainActor
    func testCreateTabStoresKindAndPinnedState() {
        let controller = BonsplitController()
        let tabId = controller.createTab(
            title: "Browser",
            icon: "globe",
            kind: "browser",
            isPinned: true
        )!

        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.kind, "browser")
        XCTAssertEqual(tab?.isPinned, true)
    }

    @MainActor
    func testCreateAndUpdateTabCustomTitleFlag() {
        let controller = BonsplitController()
        let tabId = controller.createTab(
            title: "Infra",
            hasCustomTitle: true
        )!

        XCTAssertEqual(controller.tab(tabId)?.hasCustomTitle, true)

        controller.updateTab(tabId, hasCustomTitle: false)
        XCTAssertEqual(controller.tab(tabId)?.hasCustomTitle, false)
    }

    @MainActor
    func testSplitPaneWithOptionalTabPreservesCustomTitleFlag() {
        let controller = BonsplitController()
        _ = controller.createTab(title: "Base")
        let sourcePaneId = controller.focusedPaneId!
        let customTab = Tab(title: "Custom", hasCustomTitle: true)

        guard let newPaneId = controller.splitPane(sourcePaneId, orientation: .horizontal, withTab: customTab) else {
            return XCTFail("Expected splitPane to return new pane")
        }
        let inserted = controller.tabs(inPane: newPaneId).first(where: { $0.id == customTab.id })
        XCTAssertEqual(inserted?.hasCustomTitle, true)
    }

    @MainActor
    func testSplitPaneWithInsertSidePreservesCustomTitleFlag() {
        let controller = BonsplitController()
        _ = controller.createTab(title: "Base")
        let sourcePaneId = controller.focusedPaneId!
        let customTab = Tab(title: "Custom", hasCustomTitle: true)

        guard let newPaneId = controller.splitPane(
            sourcePaneId,
            orientation: .vertical,
            withTab: customTab,
            insertFirst: true
        ) else {
            return XCTFail("Expected splitPane(insertFirst:) to return new pane")
        }
        let inserted = controller.tabs(inPane: newPaneId).first(where: { $0.id == customTab.id })
        XCTAssertEqual(inserted?.hasCustomTitle, true)
    }

    @MainActor
    func testRequestTabContextActionForwardsToDelegate() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Test", kind: "browser")!
        let spy = TabContextActionDelegateSpy()
        controller.delegate = spy

        controller.requestTabContextAction(.reload, for: tabId, inPane: pane)

        XCTAssertEqual(spy.action, .reload)
        XCTAssertEqual(spy.tabId, tabId)
        XCTAssertEqual(spy.paneId, pane)
    }

    @MainActor
    func testRequestTabContextActionForwardsMarkAsReadToDelegate() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Test", kind: "terminal")!
        let spy = TabContextActionDelegateSpy()
        controller.delegate = spy

        controller.requestTabContextAction(.markAsRead, for: tabId, inPane: pane)

        XCTAssertEqual(spy.action, .markAsRead)
        XCTAssertEqual(spy.tabId, tabId)
        XCTAssertEqual(spy.paneId, pane)
    }

    func testIconSaturationKeepsRasterFaviconInColorWhenInactive() {
        XCTAssertEqual(
            TabItemStyling.iconSaturation(hasRasterIcon: true, tabSaturation: 0.0),
            1.0
        )
    }

    func testIconSaturationStillDesaturatesSymbolIconsWhenInactive() {
        XCTAssertEqual(
            TabItemStyling.iconSaturation(hasRasterIcon: false, tabSaturation: 0.0),
            0.0
        )
    }

    func testResolvedFaviconImageUsesIncomingDataWhenDecodable() {
        let existing = NSImage(size: NSSize(width: 12, height: 12))
        let incoming = NSImage(size: NSSize(width: 16, height: 16))
        incoming.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        incoming.unlockFocus()
        let data = incoming.tiffRepresentation

        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: data)
        XCTAssertNotNil(resolved)
        XCTAssertFalse(resolved === existing)
    }

    func testResolvedFaviconImageKeepsExistingImageWhenIncomingDataIsInvalid() {
        let existing = NSImage(size: NSSize(width: 16, height: 16))
        let invalidData = Data([0x00, 0x11, 0x22, 0x33])

        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: invalidData)
        XCTAssertTrue(resolved === existing)
    }

    func testResolvedFaviconImageClearsWhenIncomingDataIsNil() {
        let existing = NSImage(size: NSSize(width: 16, height: 16))
        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: nil)
        XCTAssertNil(resolved)
    }

    func testTabControlShortcutHintPolicyRequiresCommandOrControlOnly() {
        XCTAssertNotNil(TabControlShortcutHintPolicy.hintModifier(for: [.control]))
        XCTAssertNotNil(TabControlShortcutHintPolicy.hintModifier(for: [.command]))
        XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: []))
        XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.control, .shift]))
        XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.command, .option]))
    }

    func testTabControlShortcutHintsAreScopedToCurrentKeyWindow() {
        XCTAssertTrue(
            TabControlShortcutHintPolicy.shouldShowHints(
                for: [.command],
                hostWindowNumber: 42,
                hostWindowIsKey: true,
                eventWindowNumber: 42,
                keyWindowNumber: 42
            )
        )

        XCTAssertFalse(
            TabControlShortcutHintPolicy.shouldShowHints(
                for: [.command],
                hostWindowNumber: 42,
                hostWindowIsKey: true,
                eventWindowNumber: 7,
                keyWindowNumber: 42
            )
        )

        XCTAssertFalse(
            TabControlShortcutHintPolicy.shouldShowHints(
                for: [.command],
                hostWindowNumber: 42,
                hostWindowIsKey: false,
                eventWindowNumber: 42,
                keyWindowNumber: 42
            )
        )
    }

    func testTabControlShortcutHintsFallbackToKeyWindowWhenEventWindowMissing() {
        XCTAssertTrue(
            TabControlShortcutHintPolicy.shouldShowHints(
                for: [.control],
                hostWindowNumber: 42,
                hostWindowIsKey: true,
                eventWindowNumber: nil,
                keyWindowNumber: 42
            )
        )

        XCTAssertFalse(
            TabControlShortcutHintPolicy.shouldShowHints(
                for: [.control],
                hostWindowNumber: 42,
                hostWindowIsKey: true,
                eventWindowNumber: nil,
                keyWindowNumber: 7
            )
        )
    }

    func testSelectedTabNeverShowsHoverBackground() {
        XCTAssertFalse(
            TabItemStyling.shouldShowHoverBackground(isHovered: true, isSelected: true)
        )
        XCTAssertTrue(
            TabItemStyling.shouldShowHoverBackground(isHovered: true, isSelected: false)
        )
        XCTAssertFalse(
            TabItemStyling.shouldShowHoverBackground(isHovered: false, isSelected: false)
        )
    }

    func testTabBarSeparatorSegmentsClampGapIntoBounds() {
        var segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: -20...40)
        XCTAssertEqual(segments.left, 0, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 60, accuracy: 0.0001)

        segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: 25...120)
        XCTAssertEqual(segments.left, 25, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 0, accuracy: 0.0001)

        segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: nil)
        XCTAssertEqual(segments.left, 100, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 0, accuracy: 0.0001)
    }
}
