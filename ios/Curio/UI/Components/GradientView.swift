import UIKit

/// Painted space themes. `CAGradientLayer` blends in sRGB and can't draw the
/// soft glows, so each theme is painted once (see `GradientSpec.renderRGBA`)
/// into a small bitmap and stretched to fit. The gradients are smooth and
/// dithered, so scaling keeps them clean at any size.
enum GradientImages {
    /// Bitmap shapes. Window bitmaps match the window's orientation so the
    /// glows stay round. `sidebar` is the left fifth of a landscape window,
    /// which is what the desktop sidebar shows. Swatches are for small
    /// previews such as the picker.
    enum Shape: Hashable {
        case landscape
        case portrait
        case sidebar
        case swatch

        var pixels: (width: Int, height: Int) {
            switch self {
            case .landscape: (480, 300)
            case .portrait: (300, 480)
            case .sidebar: (96, 300)
            case .swatch: (96, 60)
            }
        }
    }

    private struct Key: Hashable {
        let gradient: SpaceGradient
        let shape: Shape
    }

    /// At most 20 themes × 3 shapes, about 600 KB each at window size.
    private static var cache: [Key: UIImage] = [:]

    /// The bitmap for `gradient`, painting it on first use.
    static func image(_ gradient: SpaceGradient, _ shape: Shape) -> UIImage {
        let key = Key(gradient: gradient, shape: shape)
        if let image = cache[key] { return image }
        let image = paint(gradient, shape)
        cache[key] = image
        return image
    }

    private static func paint(_ gradient: SpaceGradient, _ shape: Shape) -> UIImage {
        if shape == .sidebar {
            let (width, height) = shape.pixels
            let window = image(gradient, .landscape)
            guard let slice = window.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) else { return window }
            return UIImage(cgImage: slice, scale: 1, orientation: .up)
        }
        let (width, height) = shape.pixels
        let pixels = gradient.spec.renderRGBA(width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return UIImage() }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}

/// Fills itself with a space theme, cross-fading when the theme changes.
/// Resizing only stretches the bitmap; a window backdrop switches to a
/// portrait bitmap when the view is taller than it is wide.
final class GradientView: UIView {
    enum Style {
        /// The whole window's gradient.
        case window
        /// The slice the desktop sidebar shows, for the tabs drawer.
        case sidebar
        /// The small bitmap, for previews.
        case swatch
    }

    private let imageView = UIImageView()
    private var gradient: SpaceGradient?
    private var shape: GradientImages.Shape?
    var style = Style.window {
        didSet { refreshImage() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if currentShape != shape { refreshImage() }
    }

    /// Shows `gradient`, fading it in over the previous one across
    /// `duration` when it is positive.
    func setGradient(_ gradient: SpaceGradient, duration: TimeInterval = 0) {
        guard gradient != self.gradient else { return }
        let hadImage = self.gradient != nil
        self.gradient = gradient
        if duration > 0, hadImage {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer.add(fade, forKey: "space-theme")
        }
        refreshImage()
    }

    private var currentShape: GradientImages.Shape {
        switch style {
        case .sidebar: .sidebar
        case .swatch: .swatch
        case .window: bounds.height > bounds.width ? .portrait : .landscape
        }
    }

    private func refreshImage() {
        guard let gradient else { return }
        shape = currentShape
        imageView.image = GradientImages.image(gradient, currentShape)
    }
}
