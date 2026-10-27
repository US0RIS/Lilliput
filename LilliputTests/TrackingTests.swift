import XCTest
@testable import Lilliput

final class WindowRegistryTests: XCTestCase {
    private func input(_ id: WindowID, _ rect: CGRect) -> WindowRegistry.Input {
        WindowRegistry.Input(id: id, pid: 42, frame: rect, bundleID: "com.example.app")
    }

    func testOpenedOnlyAfterGeometryStabilises() {
        let r = WindowRegistry()
        let f = CGRect(x: 100, y: 100, width: 400, height: 300)
        var out = r.reconcile([input(1, f)], now: 0, animated: true, checkHidden: true) { _ in true }
        XCTAssertTrue(out.events.isEmpty)
        // Still animating open: frame changes, so not yet stable.
        out = r.reconcile([input(1, f.insetBy(dx: -10, dy: -10))], now: 0.15, animated: true, checkHidden: true) { _ in true }
        XCTAssertTrue(out.events.isEmpty)
        out = r.reconcile([input(1, f.insetBy(dx: -10, dy: -10))], now: 0.3, animated: true, checkHidden: true) { _ in true }
        XCTAssertTrue(out.events.isEmpty)
        out = r.reconcile([input(1, f.insetBy(dx: -10, dy: -10))], now: 0.45, animated: true, checkHidden: true) { _ in true }
        XCTAssertEqual(out.events.count, 1)
        guard case .opened(let s, true)? = out.events.first else { return XCTFail() }
        XCTAssertEqual(s.id, 1)
        XCTAssertEqual(out.stacking.map(\.id), [1])
    }

    private func openedRegistry(_ f: CGRect) -> WindowRegistry {
        let r = WindowRegistry()
        _ = r.reconcile([input(7, f)], now: 0, animated: true, checkHidden: true) { _ in true }
        _ = r.reconcile([input(7, f)], now: 1, animated: true, checkHidden: true) { _ in true }
        return r
    }

    func testMoveEmitsChanged() {
        let f = CGRect(x: 0, y: 0, width: 300, height: 200)
        let r = openedRegistry(f)
        let out = r.reconcile([input(7, f.offsetBy(dx: 30, dy: 0))], now: 2, animated: true, checkHidden: true) { _ in true }
        guard case .changed(let s)? = out.events.first else { return XCTFail() }
        XCTAssertEqual(s.frame.minX, 30)
    }

    func testSubPointJitterIgnored() {
        let f = CGRect(x: 0, y: 0, width: 300, height: 200)
        let r = openedRegistry(f)
        let out = r.reconcile([input(7, f.offsetBy(dx: 0.2, dy: 0))], now: 2, animated: true, checkHidden: true) { _ in true }
        XCTAssertTrue(out.events.isEmpty)
    }

    func testMinimizeThenRestore() {
        let f = CGRect(x: 0, y: 0, width: 300, height: 200)
        let r = openedRegistry(f)
        var out = r.reconcile([], now: 2, animated: true, checkHidden: true) { _ in true }
        XCTAssertEqual(out.events, [.hidden(7, animated: true)])
        out = r.reconcile([input(7, f)], now: 3, animated: true, checkHidden: true) { _ in true }
        guard case .restored(let s, true)? = out.events.first else { return XCTFail() }
        XCTAssertEqual(s.id, 7)
    }

    func testCloseWhenWindowNoLongerExists() {
        let f = CGRect(x: 0, y: 0, width: 300, height: 200)
        let r = openedRegistry(f)
        let out = r.reconcile([], now: 2, animated: true, checkHidden: true) { _ in false }
        XCTAssertEqual(out.events, [.closed(7)])
        XCTAssertTrue(r.states.isEmpty)
    }

    func testHiddenWindowLaterClosed() {
        let f = CGRect(x: 0, y: 0, width: 300, height: 200)
        let r = openedRegistry(f)
        _ = r.reconcile([], now: 2, animated: true, checkHidden: true) { _ in true }
        var out = r.reconcile([], now: 3, animated: true, checkHidden: false) { _ in false }
        XCTAssertTrue(out.events.isEmpty, "hidden windows are only re-checked when asked")
        out = r.reconcile([], now: 4, animated: true, checkHidden: true) { _ in false }
        XCTAssertEqual(out.events, [.closed(7)])
    }

    func testStackingOrderFollowsInput() {
        let r = WindowRegistry()
        let a = input(1, CGRect(x: 0, y: 0, width: 300, height: 200))
        let b = input(2, CGRect(x: 50, y: 50, width: 300, height: 200))
        _ = r.reconcile([a, b], now: 0, animated: true, checkHidden: true) { _ in true }
        var out = r.reconcile([a, b], now: 1, animated: true, checkHidden: true) { _ in true }
        XCTAssertEqual(out.stacking.map(\.id), [1, 2])
        out = r.reconcile([b, a], now: 2, animated: true, checkHidden: true) { _ in true }
        XCTAssertTrue(out.stackingChanged)
        XCTAssertEqual(out.stacking.map(\.id), [2, 1])
    }
}

final class GeometryTests: XCTestCase {
    func testCGToAppKitConversionRoundTrips() {
        let cg = CGRect(x: 100, y: 50, width: 400, height: 300)
        let ak = ScreenGeometry.appKitRect(fromCG: cg, primaryHeight: 1000)
        XCTAssertEqual(ak, CGRect(x: 100, y: 650, width: 400, height: 300))
        XCTAssertEqual(ScreenGeometry.cgRect(fromAppKit: ak, primaryHeight: 1000), cg)
    }

    func testSecondaryDisplayAboveAndLeft() {
        // Secondary display positioned above-left of the primary (negative x, y > primary height).
        let secondary = CGRect(x: -1920, y: 1000, width: 1920, height: 1080)
        let cg = CGRect(x: -1500, y: -900, width: 600, height: 400) // CG y is negative above the primary
        let ak = ScreenGeometry.appKitRect(fromCG: cg, primaryHeight: 1000)
        XCTAssertTrue(secondary.contains(ak))
        let scene = ScreenGeometry.sceneRect(fromAppKit: ak, displayFrame: secondary)
        XCTAssertEqual(scene.minX, 420)
        XCTAssertEqual(scene.minY, ak.minY - 1000)
    }

    func testBestDisplayUsesBottomEdge() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let straddling = CGRect(x: 800, y: 100, width: 500, height: 300) // midX = 1050
        XCTAssertEqual(ScreenGeometry.bestDisplayIndex(for: straddling, displays: displays), 1)
        XCTAssertNil(ScreenGeometry.bestDisplayIndex(for: CGRect(x: 5000, y: 5000, width: 10, height: 10), displays: displays))
    }

    func testOcclusionFrontWindowHidesBack() {
        let back = CGRect(x: 0, y: 0, width: 400, height: 300)
        let front = CGRect(x: -50, y: -50, width: 600, height: 500)
        let info = Occlusion.compute(frontToBack: [(2, front), (1, back)], targets: [1, 2])
        XCTAssertEqual(info[2]?.occluders.count, 0)
        XCTAssertEqual(info[1]?.occluders.count, 1)
        XCTAssertLessThan(info[1]!.visibleFraction, 0.3)
        let side = CGRect(x: 1000, y: 0, width: 300, height: 300)
        let clear = Occlusion.compute(frontToBack: [(3, side), (1, back)], targets: [1])
        XCTAssertEqual(clear[1]?.visibleFraction, 1)
        XCTAssertEqual(clear[1]?.occluders.count, 0)
    }
}

final class CoreTests: XCTestCase {
    func testRNGIsDeterministic() {
        var a = SplitMix64(seed: 99)
        var b = SplitMix64(seed: 99)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = SplitMix64(seed: 1)
        for _ in 0..<1000 {
            let u = c.unit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
        }
        XCTAssertNil(c.weightedIndex([0, 0]))
        XCTAssertEqual(c.weightedIndex([0, 5, 0]), 1)
    }

    func testSpringSettles() {
        var s = Spring2D()
        s.velocity = CGVector(dx: 20, dy: -10)
        for _ in 0..<600 { s.step(dt: 1.0 / 60, drive: .zero) }
        XCTAssertTrue(s.isSettled)
    }

    func testPendulumSwingsAgainstAcceleration() {
        var p = Pendulum()
        for _ in 0..<10 { p.step(dt: 1.0 / 60, length: 20, accelX: 2000) }
        XCTAssertLessThan(p.angle, 0, "hook should lag behind the acceleration")
        for _ in 0..<1200 { p.step(dt: 1.0 / 60, length: 20, accelX: 0) }
        XCTAssertLessThan(abs(p.angle), 0.02)
    }

    func testCrewSizeRespectsLimit() {
        var s = SimSettings()
        s.density = .busy
        s.maxWorkersPerSite = 2
        XCTAssertEqual(s.crewSize, 2)
        s.maxWorkersPerSite = 6
        XCTAssertEqual(s.crewSize, ConstructionDensity.busy.crewSize)
    }

    func testWorkerSizesMatchSpec() {
        // Worker art is 12 px from boots to hat; spec asks for ~18–26 pt.
        for size in WorkerSize.allCases {
            let pt = 12 * size.pixelScale
            XCTAssertGreaterThanOrEqual(pt, 18)
            XCTAssertLessThanOrEqual(pt, 26)
        }
    }
}
