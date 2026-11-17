import UIKit
import XCTest
@testable import Curio

final class BottomBarSnapshotTests: XCTestCase {
    @MainActor
    func testNarrowLightNewTab() async throws {
        try assertSnapshot("BottomBar-NarrowLight", width: 320, gradient: .default, nav: PageNav())
    }

    @MainActor
    func testWideDarkPageWithZoom() async throws {
        let nav = PageNav(canGoBack: true, secure: true, zoom: 1.25,
                          page: .init(url: "https://curio.test", host: "curio.test", title: "Curio"))
        try assertSnapshot("BottomBar-WideDark", width: 430, gradient: .midnightIndigo, nav: nav)
    }

    @MainActor
    private func assertSnapshot(_ name: String, width: CGFloat, gradient: SpaceGradient, nav: PageNav,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "The compact bar baselines use iPhone rendering")
        #if targetEnvironment(simulator)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        try XCTSkipUnless(os.majorVersion == 26 && os.minorVersion == 2, "Snapshot baselines use iOS 26.2 system fonts and symbols")
        #else
        throw XCTSkip("Snapshot baselines use Simulator rendering")
        #endif

        let oldGradient = ThemeCenter.shared.theme.gradient
        defer { ThemeCenter.shared.apply(gradient: oldGradient) }
        ThemeCenter.shared.apply(gradient: gradient)

        let style: UIUserInterfaceStyle = gradient.tone == .light ? .light : .dark
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = .large
            traits.displayScale = 1
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: 50)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var image: UIImage?
        traits.performAsCurrent {
            let bar = BottomBarView()
            bar.frame = bounds
            bar.traitOverrides.userInterfaceStyle = style
            bar.traitOverrides.preferredContentSizeCategory = .large
            bar.traitOverrides.displayScale = 1
            bar.backgroundColor = ThemeCenter.shared.theme.chromeBottom.uiColor
            bar.update(nav, assistantOpen: false)
            for button in [bar.sidebarButton, bar.backButton, bar.forwardButton, bar.pill.trailingButton,
                           bar.assistantButton, bar.moreButton] {
                button.updateConfiguration()
            }
            bar.layoutIfNeeded()
            image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
                bar.layer.render(in: context.cgContext)
            }
        }

        let actual = try XCTUnwrap(image)
        let bundle = Bundle(for: Self.self)
        let expected = bundle.url(forResource: name, withExtension: "png")
            .flatMap { UIImage(contentsOfFile: $0.path) }
        if let expected, expected.size == actual.size,
           let expectedPixels = pixels(expected), expectedPixels == pixels(actual) {
            return
        }

        addAttachment(actual, name: "\(name)-actual")
        if let expected { addAttachment(expected, name: "\(name)-expected") }
        XCTFail(expected == nil ? "Missing \(name).png baseline" : "\(name) differs from the baseline", file: file, line: line)
    }

    private func addAttachment(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Normalize the rendered and PNG-decoded images to the same sRGB format.
    private func pixels(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let stride = width * 4
        var bytes = Data(count: stride * height)
        let rendered = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: stride, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? bytes : nil
    }
}
