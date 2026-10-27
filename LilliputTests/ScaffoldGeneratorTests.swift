import XCTest
@testable import Lilliput

final class ScaffoldGeneratorTests: XCTestCase {
    private func layout(_ w: Int, _ h: Int, _ d: ConstructionDensity = .normal, bounds: PxRect = .unbounded, locked: ScaffoldTopology? = nil) -> ScaffoldLayout? {
        ScaffoldGenerator.layout(ScaffoldParams(width: w, height: h, density: d, bounds: bounds, locked: locked))
    }

    func testTinyWindowsGetNoScaffold() {
        XCTAssertNil(layout(20, 100))
        XCTAssertNil(layout(200, 10))
    }

    func testBaysCoverDeckContiguously() throws {
        let L = try XCTUnwrap(layout(400, 300))
        XCTAssertEqual(L.bays.first?.x0, L.deckL)
        XCTAssertEqual(L.bays.last?.x1, L.deckR)
        for (a, b) in zip(L.bays, L.bays.dropFirst()) { XCTAssertEqual(a.x1, b.x0) }
        XCTAssertLessThanOrEqual(L.bays.count, ScaffoldGenerator.maxBays)
        XCTAssertTrue(L.bays.allSatisfy { $0.width >= ScaffoldGenerator.minBayWidth })
    }

    func testTowersStayOutsideWindowAndAwayFromTrafficLights() throws {
        let L = try XCTUnwrap(layout(400, 300, .busy))
        let left = try XCTUnwrap(L.left)
        let right = try XCTUnwrap(L.right)
        XCTAssertLessThan(left.x1, 0, "left tower must be outside the window")
        XCTAssertGreaterThan(right.x0, L.width, "right tower must be outside the window")
        // Nothing reaches the top-left title-bar area (traffic lights).
        XCTAssertLessThanOrEqual(left.topY + ScaffoldGenerator.railHeight, L.height)
    }

    func testDensityScalesComplexity() throws {
        let sparse = try XCTUnwrap(layout(400, 300, .sparse))
        let busy = try XCTUnwrap(layout(400, 300, .busy))
        XCTAssertLessThan(sparse.elements.count, busy.elements.count)
        XCTAssertNil(sparse.left)
        XCTAssertNotNil(busy.crane)
    }

    func testTowersDroppedWhenOffScreen() throws {
        // Window flush against the left screen edge: no room for a left tower.
        let L = try XCTUnwrap(layout(400, 300, .busy, bounds: PxRect(minX: 0, maxX: 1000, minY: -50, maxY: 600)))
        XCTAssertNil(L.left)
        XCTAssertNotNil(L.right)
        XCTAssertGreaterThanOrEqual(L.deckL, 0)
    }

    func testTrussClippedAtScreenBottom() throws {
        let L = try XCTUnwrap(layout(300, 200, .normal, bounds: PxRect(minX: -500, maxX: 900, minY: -4, maxY: 600)))
        XCTAssertLessThanOrEqual(L.trussDepth, 2)
    }

    func testLockedTopologyKeepsBayCount() throws {
        let base = try XCTUnwrap(layout(300, 200))
        let stretched = try XCTUnwrap(layout(420, 200, locked: base.topology))
        XCTAssertEqual(base.bays.count, stretched.bays.count)
        let settled = try XCTUnwrap(layout(420, 200))
        XCTAssertGreaterThan(settled.bays.count, base.bays.count)
    }

    func testRequirementsReferToExistingElements() throws {
        for d in ConstructionDensity.allCases {
            let L = try XCTUnwrap(layout(500, 320, d))
            let keys = Set(L.elements.map(\.key))
            for e in L.elements {
                for r in e.requires { XCTAssertTrue(keys.contains(r), "\(e.key) requires missing \(r)") }
                XCTAssertNotNil(L.surface(e.work.surface), "\(e.key) has unreachable work spot")
            }
            // Requirements always point at earlier elements, so construction can't deadlock.
            let order = Dictionary(uniqueKeysWithValues: L.elements.map { ($0.key, $0.order) })
            for e in L.elements { for r in e.requires { XCTAssertLessThan(order[r]!, e.order) } }
        }
    }
}

final class NavigationTests: XCTestCase {
    func testPathFromDeckToTopOfTowerClimbsEachLadder() throws {
        let L = try XCTUnwrap(ScaffoldGenerator.layout(ScaffoldParams(width: 400, height: 300, density: .busy)))
        let t = try XCTUnwrap(L.right)
        let top = t.surfaceID(level: t.levels)
        let path = L.path(from: NavPoint(surface: Surface.deckID, x: 10), to: NavPoint(surface: top, x: CGFloat(t.centerX)))
        let climbs = path.filter { if case .climb = $0 { return true } else { return false } }
        XCTAssertEqual(climbs.count, t.levels)
    }

    func testPathBetweenTowersGoesThroughDeck() throws {
        let L = try XCTUnwrap(ScaffoldGenerator.layout(ScaffoldParams(width: 400, height: 300, density: .busy)))
        let l = try XCTUnwrap(L.left), r = try XCTUnwrap(L.right)
        let path = L.path(from: NavPoint(surface: l.surfaceID(level: 2), x: CGFloat(l.centerX)),
                          to: NavPoint(surface: r.surfaceID(level: 1), x: CGFloat(r.centerX)))
        let climbs = path.compactMap { step -> Int? in if case .climb(_, _, let to) = step { return to } else { return nil } }
        XCTAssertTrue(climbs.contains(Surface.deckID))
        XCTAssertEqual(climbs.last, r.surfaceID(level: 1))
    }

    func testWalkTargetsAreClampedToSurface() throws {
        let L = try XCTUnwrap(ScaffoldGenerator.layout(ScaffoldParams(width: 300, height: 200, density: .normal)))
        let path = L.path(from: NavPoint(surface: Surface.deckID, x: 0), to: NavPoint(surface: Surface.deckID, x: 10_000))
        guard case .walk(_, let x)? = path.last else { return XCTFail("expected a walk") }
        XCTAssertEqual(x, L.deck.maxX)
    }

    func testFallbackSurfaceForRemovedLevel() throws {
        let L = try XCTUnwrap(ScaffoldGenerator.layout(ScaffoldParams(width: 400, height: 300, density: .normal)))
        let t = try XCTUnwrap(L.right)
        let gone = t.surfaceID(level: t.levels + 2)
        XCTAssertEqual(L.fallbackSurface(for: gone).id, t.surfaceID(level: t.levels))
    }
}
