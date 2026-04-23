import XCTest
@testable import Bonsplit
import AppKit
import SwiftUI

final class BonsplitTests: XCTestCase {
    @MainActor
    private final class FakeTabBarHitRegionView: NSView {
        deinit {
            BonsplitTabBarHitRegionRegistry.unregister(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            BonsplitTabBarHitRegionRegistry.unregister(self)
            if window != nil {
                BonsplitTabBarHitRegionRegistry.register(self)
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview == nil {
                BonsplitTabBarHitRegionRegistry.unregister(self)
            }
        }
    }

    @MainActor
    private final class LayoutProbeView: NSView {
        private(set) var sizeChangeCount = 0
        private(set) var originChangeCount = 0

        override func setFrameSize(_ newSize: NSSize) {
            if frame.size != newSize {
                sizeChangeCount += 1
            }
            super.setFrameSize(newSize)
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            if frame.origin != newOrigin {
                originChangeCount += 1
            }
            super.setFrameOrigin(newOrigin)
        }
    }

    @MainActor
    private struct LayoutProbeRepresentable: NSViewRepresentable {
        let probeView: LayoutProbeView

        func makeNSView(context: Context) -> LayoutProbeView {
            probeView
        }

        func updateNSView(_ nsView: LayoutProbeView, context: Context) {}
    }

    @MainActor
    private final class DropZoneModel: ObservableObject {
        @Published var zone: DropZone?
    }

    @MainActor
    private struct PaneDropInteractionHarness: View {
        @ObservedObject var model: DropZoneModel
        let probeView: LayoutProbeView

        var body: some View {
            PaneDropInteractionContainer(activeDropZone: model.zone) {
                LayoutProbeRepresentable(probeView: probeView)
            } dropLayer: { _ in
                Color.clear
            }
        }
    }

    private final class TabContextActionDelegateSpy: BonsplitDelegate {
        var action: TabContextAction?
        var tabId: TabID?
        var paneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Bonsplit.Tab, inPane pane: PaneID) {
            self.action = action
            self.tabId = tab.id
            self.paneId = pane
        }
    }

    private final class NewTabRequestDelegateSpy: BonsplitDelegate {
        var requestedKind: String?
        var requestedPaneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
            requestedKind = kind
            requestedPaneId = pane
        }
    }

    private final class CustomActionDelegateSpy: BonsplitDelegate {
        var requestedIdentifier: String?
        var requestedPaneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestCustomAction identifier: String, inPane pane: PaneID) {
            requestedIdentifier = identifier
            requestedPaneId = pane
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

    func testDefaultSplitButtonTooltips() {
        let defaults = BonsplitConfiguration.SplitButtonTooltips.default
        XCTAssertEqual(defaults.newTerminal, "New Terminal")
        XCTAssertEqual(defaults.newBrowser, "New Browser")
        XCTAssertEqual(defaults.splitRight, "Split Right")
        XCTAssertEqual(defaults.splitDown, "Split Down")
    }

    func testDefaultSplitActionButtons() {
        XCTAssertEqual(
            BonsplitConfiguration.SplitActionButton.defaults,
            [.newTerminal, .newBrowser, .splitRight, .splitDown]
        )
    }

    func testCustomSplitActionButtonRoundTrips() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "checkmark.circle",
            tooltip: "Run tests",
            action: .custom("run-tests")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded, button)
    }

    func testCustomSplitActionButtonPreservesReservedActionName() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "custom-terminal",
            systemImage: "terminal",
            tooltip: "Custom terminal action",
            action: .custom("newTerminal")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded.action, .custom("newTerminal"))
        XCTAssertEqual(decoded, button)
    }

    func testSplitActionButtonDecodesLegacyBuiltInActionString() throws {
        let data = #"""
        {
          "id": "terminal",
          "icon": { "type": "systemImage", "name": "terminal" },
          "action": "newTerminal"
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded.action, .newTerminal)
    }

    func testCustomSplitActionButtonSupportsEmojiIcon() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "agent",
            icon: .emoji("🤖", scale: 0.85),
            tooltip: "Start agent",
            action: .custom("agent")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded, button)
    }

    func testCustomSplitActionButtonSupportsImageDataIcon() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let button = BonsplitConfiguration.SplitActionButton(
            id: "image-agent",
            icon: .imageData(data),
            tooltip: "Start image agent",
            action: .custom("image-agent")
        )

        let encoded = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: encoded)

        XCTAssertEqual(decoded, button)
    }

    func testCurrentColorSVGImageDataRendersAsTemplate() throws {
        let templateSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="currentColor" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )
        let colorSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#D97757" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )

        XCTAssertTrue(TabBarStyling.imageDataShouldRenderAsTemplate(templateSVG))
        XCTAssertFalse(TabBarStyling.imageDataShouldRenderAsTemplate(colorSVG))
    }

    func testCurrentColorSVGImageDataRendersAsTemplateWithInvalidUTF8Suffix() throws {
        var svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="currentColor" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )
        svg.append(0xE2)

        XCTAssertTrue(TabBarStyling.imageDataShouldRenderAsTemplate(svg))
    }

    @MainActor
    func testSplitActionButtonImageDataIsCached() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        let first = try XCTUnwrap(TabBarStyling.splitActionButtonImage(from: png))
        let second = try XCTUnwrap(TabBarStyling.splitActionButtonImage(from: png))

        XCTAssertTrue(first === second)
    }

    func testMinimalModeDoesNotReserveHiddenSplitButtonStrip() {
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: true),
            0,
            "Minimal mode should let the tab strip fill the full width until the hover-only split buttons are actually shown"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false),
            TabBarStyling.splitButtonsBackdropWidth(buttonCount: 4),
            "Standard mode should keep reserving space for the always-visible split buttons"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false, buttonCount: 2),
            TabBarStyling.splitButtonsBackdropWidth(buttonCount: 2),
            "Standard mode should reserve space for the configured split buttons only"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false, buttonCount: 0),
            0,
            "No strip should be reserved when the configured split button list is empty"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: false, isMinimalMode: false),
            0,
            "No split-button strip should be reserved when split buttons are disabled"
        )
    }

    func testTabBarKeepsNonOverflowingTabsLeadingAligned() {
        let tabId = UUID()

        XCTAssertEqual(
            TabBarStyling.preferredScrollTarget(
                selectedTabId: tabId,
                contentWidth: 132,
                containerWidth: 349
            ),
            .leading,
            "When the tab strip fits in the pane, it should stay leading-aligned instead of creating a dead leading clip-view band"
        )

        XCTAssertEqual(
            TabBarStyling.preferredScrollTarget(
                selectedTabId: tabId,
                contentWidth: 420,
                containerWidth: 349
            ),
            .selectedTab(tabId),
            "Overflowing tab strips should still auto-scroll the selected tab into view"
        )
    }

    func testTabBarForcesLeadingResetWhenNonOverflowingStripStaysScrolled() {
        XCTAssertTrue(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 28,
                contentWidth: 180,
                containerWidth: 349
            ),
            "A non-overflowing tab strip with a stale horizontal offset should be snapped back to x=0"
        )

        XCTAssertTrue(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: -30,
                contentWidth: 180,
                containerWidth: 349
            ),
            "The leading reset must correct both left and right stale offsets"
        )

        XCTAssertFalse(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 0.2,
                contentWidth: 180,
                containerWidth: 349
            ),
            "Tiny floating-point drift should not trigger redundant clip-view resets"
        )

        XCTAssertFalse(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 28,
                contentWidth: 420,
                containerWidth: 349
            ),
            "Overflowing tab strips are allowed to stay horizontally scrolled"
        )
    }

    @MainActor
    func testTabBarHitRegionRegistryTracksVisibleWindowPoint() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let tabBar = FakeTabBarHitRegionView(frame: NSRect(x: 20, y: 132, width: 180, height: 30))
        contentView.addSubview(tabBar)

        let hitPoint = tabBar.convert(NSPoint(x: 24, y: 12), to: nil)
        XCTAssertTrue(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "The registry should expose visible tab-bar hit regions in window coordinates"
        )

        let missPoint = tabBar.convert(NSPoint(x: 24, y: -18), to: nil)
        XCTAssertFalse(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(missPoint, in: window),
            "The registry should ignore points outside the registered tab-bar region"
        )
    }

    @MainActor
    func testTabBarHitRegionRegistryIgnoresViewsHiddenByAncestors() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let container = NSView(frame: contentView.bounds)
        contentView.addSubview(container)

        let tabBar = FakeTabBarHitRegionView(frame: NSRect(x: 32, y: contentView.bounds.maxY + 6, width: 180, height: 30))
        container.addSubview(tabBar)

        let hitPoint = tabBar.convert(NSPoint(x: 20, y: 14), to: nil)
        XCTAssertTrue(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "The registry should use the actual registered tab-bar frame even when it extends outside its immediate container bounds"
        )

        container.isHidden = true
        XCTAssertFalse(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "Ancestor-hidden tab-bar regions must not keep stealing portal hit testing"
        )
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

    @MainActor
    func testConfigurationAcceptsCustomSplitActionButtons() {
        let buttons: [BonsplitConfiguration.SplitActionButton] = [
            .newTerminal,
            .init(
                id: "run-tests",
                systemImage: "checkmark.circle",
                tooltip: "Run tests",
                action: .custom("run-tests")
            ),
        ]
        let config = BonsplitConfiguration(
            appearance: .init(
                splitButtons: buttons
            )
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertEqual(controller.configuration.appearance.splitButtons, buttons)
    }

    func testAppearanceKeepsFirstSplitActionButtonForDuplicateIds() {
        let firstRunTests = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "checkmark.circle",
            tooltip: "Run tests",
            action: .custom("run-tests")
        )
        let duplicateRunTests = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "xmark.circle",
            tooltip: "Duplicate",
            action: .custom("duplicate")
        )
        var appearance = BonsplitConfiguration.Appearance(
            splitButtons: [.newTerminal, .newTerminal, firstRunTests, duplicateRunTests]
        )

        XCTAssertEqual(appearance.splitButtons, [.newTerminal, firstRunTests])

        appearance.splitButtons = [duplicateRunTests, firstRunTests, .splitRight]

        XCTAssertEqual(appearance.splitButtons, [duplicateRunTests, .splitRight])
    }

    @MainActor
    func testControllerRequestsCustomAction() {
        let controller = BonsplitController()
        let delegate = CustomActionDelegateSpy()
        controller.delegate = delegate
        let paneId = controller.focusedPaneId!

        controller.requestCustomAction("run-tests", inPane: paneId)

        XCTAssertEqual(delegate.requestedIdentifier, "run-tests")
        XCTAssertEqual(delegate.requestedPaneId, paneId)
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
        let customTab = Bonsplit.Tab(title: "Custom", hasCustomTitle: true)

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
        let customTab = Bonsplit.Tab(title: "Custom", hasCustomTitle: true)

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
    func testTogglePaneZoomTracksState() {
        let controller = BonsplitController()
        guard let originalPane = controller.focusedPaneId else {
            return XCTFail("Expected focused pane")
        }

        // Single-pane layouts cannot be zoomed.
        XCTAssertFalse(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertNil(controller.zoomedPaneId)

        guard controller.splitPane(originalPane, orientation: .horizontal) != nil else {
            return XCTFail("Expected splitPane to create a new pane")
        }

        XCTAssertTrue(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertEqual(controller.zoomedPaneId, originalPane)
        XCTAssertTrue(controller.isSplitZoomed)

        XCTAssertTrue(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertNil(controller.zoomedPaneId)
        XCTAssertFalse(controller.isSplitZoomed)
    }

    @MainActor
    func testSplitClearsExistingPaneZoom() {
        let controller = BonsplitController()
        guard let originalPane = controller.focusedPaneId else {
            return XCTFail("Expected focused pane")
        }

        guard let secondPane = controller.splitPane(originalPane, orientation: .horizontal) else {
            return XCTFail("Expected splitPane to create a new pane")
        }

        XCTAssertTrue(controller.togglePaneZoom(inPane: secondPane))
        XCTAssertEqual(controller.zoomedPaneId, secondPane)

        _ = controller.splitPane(secondPane, orientation: .vertical)
        XCTAssertNil(controller.zoomedPaneId, "Splitting should reset zoom state")
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

    @MainActor
    func testDoubleClickingEmptyTrailingTabBarSpaceRequestsNewTerminalTab() {
        let appearance = BonsplitConfiguration.Appearance()
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        let pane = controller.internalController.rootNode.allPanes.first!
        let spy = NewTabRequestDelegateSpy()
        controller.delegate = spy

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let clickPoint = NSPoint(x: hostingView.bounds.maxX - 12, y: hostingView.bounds.midY)
        let pointInWindow = hostingView.convert(clickPoint, to: nil)
        guard let hitView = waitForDescendant(
            ofType: TabBarDragZoneView.DragNSView.self,
            in: contentView,
            containingWindowPoint: pointInWindow,
            where: { $0.onDoubleClick != nil }
        ) else {
            XCTFail("Expected trailing tab bar drag zone")
            return
        }
        XCTAssertEqual(hitView.onDoubleClick?(), true)

        XCTAssertEqual(spy.requestedKind, "terminal")
        XCTAssertEqual(spy.requestedPaneId, pane.id)
    }

    @MainActor
    func testEmptyTrailingTabBarSpaceDoesNotRequestNewTerminalWhenButtonHidden() {
        let appearance = BonsplitConfiguration.Appearance(splitButtons: [])
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        let pane = controller.internalController.rootNode.allPanes.first!
        let spy = NewTabRequestDelegateSpy()
        controller.delegate = spy

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let clickPoint = NSPoint(x: hostingView.bounds.maxX - 12, y: hostingView.bounds.midY)
        let pointInWindow = hostingView.convert(clickPoint, to: nil)
        guard let hitView = waitForDescendant(
            ofType: TabBarDragZoneView.DragNSView.self,
            in: contentView,
            containingWindowPoint: pointInWindow,
            where: { $0.onDoubleClick != nil }
        ) else {
            XCTFail("Expected trailing tab bar drag zone")
            return
        }
        XCTAssertEqual(hitView.onDoubleClick?(), false)

        XCTAssertNil(spy.requestedKind)
        XCTAssertNil(spy.requestedPaneId)
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

    func testTabControlShortcutHintPolicyMatchesConfiguredModifiers() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [], defaults: defaults))
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.control, .shift], defaults: defaults))
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.command, .option], defaults: defaults))

            defaults.set(
                shortcutData(
                    key: "1",
                    command: true,
                    shift: false,
                    option: true,
                    control: false
                ),
                forKey: "shortcut.selectSurfaceByNumber"
            )

            let custom = TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)
            XCTAssertEqual(custom?.symbol, "⌥⌘")
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌥⌘"
            )
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌥⌘"
            )
        }
    }

    func testTabControlShortcutHintPolicyCanDisableCommandAndControlHoldHintsIndependently() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(false, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults))
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌃"
            )

            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(false, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults))
        }
    }

    func testTabControlShortcutHintPolicyDefaultsToShowingHoldHints() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.removeObject(forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.removeObject(forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol, "⌃")
            XCTAssertEqual(TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol, "⌃")
        }
    }

    func testTabControlShortcutHintsAreScopedToCurrentKeyWindow() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertTrue(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: 42,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: 7,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: false,
                    eventWindowNumber: 42,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )
        }
    }

    func testTabControlShortcutHintsFallbackToKeyWindowWhenEventWindowMissing() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertTrue(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: nil,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: nil,
                    keyWindowNumber: 7,
                    defaults: defaults
                )
            )
        }
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

    @MainActor
    func testPaneDropOverlayDoesNotResizeHostedContentDuringHover() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let model = DropZoneModel()
        let probeView = LayoutProbeView(frame: .zero)
        let hostingView = NSHostingView(
            rootView: PaneDropInteractionHarness(
                model: model,
                probeView: probeView
            )
        )
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let initialFrame = probeView.frame
        let initialSizeChanges = probeView.sizeChangeCount
        let initialOriginChanges = probeView.originChangeCount

        model.zone = .left
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(probeView.frame, initialFrame)
        XCTAssertEqual(
            probeView.sizeChangeCount,
            initialSizeChanges,
            "Drag-hover overlays must not resize the hosted pane content"
        )
        XCTAssertEqual(
            probeView.originChangeCount,
            initialOriginChanges,
            "Drag-hover overlays must not move the hosted pane content"
        )

        model.zone = .bottom
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(probeView.frame, initialFrame)
        XCTAssertEqual(
            probeView.sizeChangeCount,
            initialSizeChanges,
            "Switching hover targets should keep the hosted pane geometry stable"
        )
        XCTAssertEqual(
            probeView.originChangeCount,
            initialOriginChanges,
            "Switching hover targets should not reposition the hosted pane content"
        )
    }

    @MainActor
    func testTranslucentSplitWrappersStayClear() {
        let appearance = BonsplitConfiguration.Appearance(
            enableAnimations: false,
            chromeColors: .init(backgroundHex: "#11223380")
        )
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        _ = controller.createTab(title: "Base")
        guard let sourcePane = controller.focusedPaneId else {
            XCTFail("Expected focused pane")
            return
        }
        guard controller.splitPane(sourcePane, orientation: .horizontal) != nil else {
            XCTFail("Expected splitPane to create a new pane")
            return
        }

        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { _, _ in
                Color.clear
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        guard let splitView = firstDescendant(ofType: NSSplitView.self, in: hostingView) else {
            XCTFail("Expected split view")
            return
        }
        XCTAssertEqual(splitView.arrangedSubviews.count, 2)

        let dividerBackground = splitView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        XCTAssertNotNil(dividerBackground, "Expected split view to be layer-backed")
        XCTAssertEqual(
            dividerBackground?.alphaComponent ?? 0,
            0,
            accuracy: 0.001,
            "Split root should stay clear so translucent pane chrome is painted only once"
        )

        for container in splitView.arrangedSubviews {
            let background = container.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
            XCTAssertNotNil(background, "Expected arranged subview to be layer-backed")
            XCTAssertEqual(
                background?.alphaComponent ?? -1,
                0,
                accuracy: 0.001,
                "Split-only wrapper containers should stay clear so translucent pane chrome is not composited twice"
            )
        }
    }

    @MainActor
    func testSplitContentAlphaMatchesSinglePane() {
        let appearance = BonsplitConfiguration.Appearance(
            enableAnimations: false,
            chromeColors: .init(backgroundHex: "#11223380")
        )
        let expectedAlpha = CGFloat(128.0 / 255.0)
        let samplePoint = NSPoint(x: 100, y: 100)

        let singlePaneController = BonsplitController(
            configuration: BonsplitConfiguration(appearance: appearance)
        )
        _ = singlePaneController.createTab(title: "Base")

        guard let singlePaneAlpha = renderedAlpha(
            for: singlePaneController,
            samplePoint: samplePoint
        ) else {
            XCTFail("Expected single-pane rendered alpha")
            return
        }
        XCTAssertEqual(
            singlePaneAlpha,
            expectedAlpha,
            accuracy: 0.03,
            "Single-pane content should preserve the configured translucent alpha"
        )

        let splitController = BonsplitController(
            configuration: BonsplitConfiguration(appearance: appearance)
        )
        _ = splitController.createTab(title: "Base")
        guard let sourcePane = splitController.focusedPaneId else {
            XCTFail("Expected focused pane")
            return
        }
        guard splitController.splitPane(sourcePane, orientation: .horizontal) != nil else {
            XCTFail("Expected splitPane to create a new pane")
            return
        }

        guard let splitAlpha = renderedAlpha(
            for: splitController,
            samplePoint: samplePoint
        ) else {
            XCTFail("Expected split rendered alpha")
            return
        }

        XCTAssertEqual(
            splitAlpha,
            singlePaneAlpha,
            accuracy: 0.03,
            "Split mode should render the same content alpha as single-pane mode"
        )
    }

    @MainActor
    func testTabBarDragZoneFocusesInactivePaneInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = false

        var focused = false
        var dragged = false
        view.onSingleClick = {
            focused = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        view.mouseDown(with: event)

        XCTAssertTrue(focused, "Inactive-pane drag zone should focus the pane before starting a window drag")
        XCTAssertFalse(dragged, "Inactive-pane focus click should not immediately begin a window drag")
        XCTAssertFalse(view.mouseDownCanMoveWindow, "Inactive-pane drag zone should not advertise window dragging to AppKit")
    }

    @MainActor
    func testTabBarDragZoneSingleClickDoesNotBlockLaterDoubleClickInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var requestedNewTab = false
        var dragged = false
        view.onDoubleClick = {
            requestedNewTab = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let firstDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let firstUp = try makeMouseEvent(
            type: .leftMouseUp,
            in: view,
            at: NSPoint(x: 20, y: 15),
            clickCount: 1
        )
        let doubleClick = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)

        view.mouseDown(with: firstDown)
        view.mouseUp(with: firstUp)
        view.mouseDown(with: doubleClick)

        XCTAssertTrue(requestedNewTab, "A prior single click must not leave the drag zone unable to handle double-clicks")
        XCTAssertFalse(dragged, "A plain click followed by a double-click should not start a window drag")
    }

    @MainActor
    func testTabBarDragZoneDoubleClickRequestsNewTabInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var requestedNewTab = false
        var dragged = false
        view.onDoubleClick = {
            requestedNewTab = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)
        view.mouseDown(with: event)

        XCTAssertTrue(requestedNewTab, "Minimal-mode drag zone double-click should request the new-tab action")
        XCTAssertFalse(dragged, "Minimal-mode double-click should not start a window drag")
    }

    @MainActor
    func testTabBarDragZoneSingleClickRequestsNewTabInStandardMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = false
        view.isFocusedPane = true

        var newTabCount = 0
        var dragged = false
        view.onDoubleClick = {
            newTabCount += 1
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        view.mouseDown(with: event)

        XCTAssertEqual(newTabCount, 1, "Standard-mode drag zone single click should immediately request a new tab")
        XCTAssertFalse(dragged, "Standard-mode drag zone single click should not begin a window drag")
    }

    @MainActor
    func testTabBarDragZoneStandardModeDoubleClickCreatesOnlyOneTab() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = false
        view.isFocusedPane = true

        var newTabCount = 0
        view.onDoubleClick = {
            newTabCount += 1
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let firstDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let firstUp = try makeMouseEvent(
            type: .leftMouseUp,
            in: view,
            at: NSPoint(x: 20, y: 15),
            clickCount: 1
        )
        let secondDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)

        view.mouseDown(with: firstDown)
        view.mouseUp(with: firstUp)
        view.mouseDown(with: secondDown)

        XCTAssertEqual(newTabCount, 1, "A standard-mode double-click must only create one tab; the clickCount=2 follow-up should be deduped")
    }

    @MainActor
    func testTabBarDragZoneKeepsFocusedPaneWindowDragInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var focused = false
        var dragged = false
        view.onSingleClick = {
            focused = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let dragEvent = try makeMouseEvent(
            type: .leftMouseDragged,
            in: view,
            at: NSPoint(x: 30, y: 15),
            clickCount: 1
        )
        view.mouseDown(with: event)
        view.mouseDragged(with: dragEvent)

        XCTAssertFalse(focused, "Focused-pane drag zone should not bounce through first-click focus")
        XCTAssertTrue(dragged, "Focused-pane drag zone should continue to start window drags in minimal mode")
        XCTAssertFalse(view.mouseDownCanMoveWindow, "Focused-pane drag zone must not advertise window dragging to AppKit or AppKit steals mouseUp and breaks new-tab double-clicks")
    }

    private func withShortcutHintDefaultsSuite(_ body: (UserDefaults) -> Void) {
        let suiteName = "BonsplitShortcutHintPolicyTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func shortcutData(
        key: String,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> Data {
        let payload: [String: Any] = [
            "key": key,
            "command": command,
            "shift": shift,
            "option": option,
            "control": control
        ]
        return try! JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func waitForDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        containingWindowPoint point: NSPoint,
        timeout: TimeInterval = 1.0,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            root.layoutSubtreeIfNeeded()
            if let match = firstDescendant(
                ofType: type,
                in: root,
                containingWindowPoint: point,
                where: predicate
            ) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        return firstDescendant(
            ofType: type,
            in: root,
            containingWindowPoint: point,
            where: predicate
        )
    }

    @MainActor
    private func firstDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        containingWindowPoint point: NSPoint,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        if let match = root as? T {
            let frameInWindow = root.convert(root.bounds, to: nil)
            if frameInWindow.contains(point), predicate(match) {
                return match
            }
        }
        for subview in root.subviews {
            if let match = firstDescendant(
                ofType: type,
                in: subview,
                containingWindowPoint: point,
                where: predicate
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func renderedAlpha(
        for controller: BonsplitController,
        samplePoint: NSPoint,
        size: NSSize = NSSize(width: 800, height: 600)
    ) -> CGFloat? {
        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { _, _ in
                Color.clear
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else { return nil }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        return renderedColor(in: hostingView, at: samplePoint)?.alphaComponent
    }

    @MainActor
    private func renderedColor(in view: NSView, at point: NSPoint) -> NSColor? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        guard x >= 0,
              y >= 0,
              x < bitmap.pixelsWide,
              y < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: x, y: y)
    }

    @MainActor
    private func makeLeftMouseDownEvent(
        in view: NSView,
        at point: NSPoint,
        clickCount: Int
    ) throws -> NSEvent {
        try makeMouseEvent(type: .leftMouseDown, in: view, at: point, clickCount: clickCount)
    }

    @MainActor
    private func makeMouseEvent(
        type: NSEvent.EventType,
        in view: NSView,
        at point: NSPoint,
        clickCount: Int
    ) throws -> NSEvent {
        guard let window = view.window else {
            throw NSError(domain: "BonsplitTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing window"])
        }
        let pointInWindow = view.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ) else {
            throw NSError(domain: "BonsplitTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create mouse event"])
        }
        return event
    }
}
