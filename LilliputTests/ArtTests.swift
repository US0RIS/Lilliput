import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Lilliput

final class ArtTests: XCTestCase {
    static let allPoses: [Pose] = [
        .stand(blink: false), .stand(blink: true), .walk(0), .walk(1), .walk(2), .walk(3),
        .carry(0), .carry(1), .carryBox(0), .hammer(up: true), .hammer(up: false), .climb(0), .climb(1),
        .sit, .stretch, .sleep, .brace, .hang, .cheer(0), .cheer(1), .thumbsUp,
        .blueprint(look: false), .blueprint(look: true), .wrench(0), .wrench(1), .signal(0), .signal(1),
        .clipboard(0), .clipboard(1), .crouch, .stumble, .point, .scratchHead,
    ]

    func testEveryPoseDrawsAFigureStandingOnTheGround() {
        let styles = WorkerStyle.crew + [WorkerStyle.supervisor]
        for style in styles {
            for pose in Self.allPoses {
                let c = WorkerArt.draw(style, pose)
                XCTAssertEqual(c.width, 16)
                XCTAssertEqual(c.height, 16)
                let opaque = (0..<16).flatMap { y in (0..<16).map { x in c.isOpaque(x, y) } }.filter { $0 }.count
                XCTAssertGreaterThan(opaque, 30, "\(pose) looks empty")
                if case .hang = pose { continue }
                let bottomRow = (0..<16).contains { c.isOpaque($0, 15) }
                XCTAssertTrue(bottomRow, "\(pose) should touch the ground row")
            }
        }
    }

    func testHatIsAlwaysPresent() {
        let style = WorkerStyle.crew[0]
        for pose in Self.allPoses {
            let c = WorkerArt.draw(style, pose)
            let hasHat = (0..<16).contains { y in (0..<16).contains { x in c.color(x, y) == style.hat } }
            XCTAssertTrue(hasHat, "\(pose) lost its hard hat")
        }
    }

    func testPropsAndEmotesRender() {
        for kind in PropKind.allCases {
            let c = PropArt.canvas(kind)
            XCTAssertGreaterThan(c.width, 0)
            XCTAssertNotNil(c.makeImage(), "\(kind)")
        }
        for e in Emote.allCases { XCTAssertNotNil(PropArt.emote(e).makeImage()) }
        XCTAssertEqual(PropArt.menuBarIcon().width, 18)
    }

    /// Writes a contact sheet of all art to $LILLIPUT_ART_OUT (used by CI for visual review).
    func testExportContactSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["LILLIPUT_ART_OUT"], !out.isEmpty else {
            throw XCTSkip("Set LILLIPUT_ART_OUT to export the art contact sheet")
        }
        let styles = WorkerStyle.crew + [WorkerStyle.supervisor]
        let cell = 18
        var sheet = PixelCanvas(width: cell * Self.allPoses.count, height: cell * (styles.count + 2))
        let bg = RGBA(0xE9E4D8)
        sheet.fill(0, 0, sheet.width, sheet.height, bg)
        for (row, style) in styles.enumerated() {
            for (col, pose) in Self.allPoses.enumerated() {
                let c = WorkerArt.draw(style, pose)
                blit(c, into: &sheet, x: col * cell + 1, y: row * cell + 1)
            }
        }
        var x = 1
        let propRow = styles.count * cell + 2
        for kind in PropKind.allCases {
            let c = PropArt.canvas(kind)
            blit(c, into: &sheet, x: x, y: propRow)
            x += c.width + 3
        }
        for e in Emote.allCases {
            let c = PropArt.emote(e)
            blit(c, into: &sheet, x: x, y: propRow)
            x += c.width + 3
        }
        let scaled = sheet.scaled(by: 6)
        let image = try XCTUnwrap(scaled.makeImage())
        let url = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func blit(_ c: PixelCanvas, into sheet: inout PixelCanvas, x: Int, y: Int) {
        for yy in 0..<c.height {
            for xx in 0..<c.width {
                let px = c.color(xx, yy)
                if px.a > 0 { sheet.set(x + xx, y + yy, px) }
            }
        }
    }
}
