import UIKit

/// A site icon: the favicon when it loads, otherwise a colored letter tile
/// (stable per site), or a spinner while the page loads.
final class FaviconView: UIView, ThemeObserving {
    private struct Request: Equatable {
        let pageURL: String?
        let iconURL: String?
    }

    private let imageView = UIImageView()
    private let letterLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let loader: FaviconLoader
    private var size: CGFloat
    private var sizeConstraints: [NSLayoutConstraint] = []
    private var loadTask: Task<Void, Never>?
    private var currentRequest: Request?

    init(size: CGFloat = 16, loader: FaviconLoader = .shared) {
        self.size = size
        self.loader = loader
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        for view in [letterLabel, imageView, spinner] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: centerXAnchor),
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: widthAnchor),
            imageView.heightAnchor.constraint(equalTo: heightAnchor),
            letterLabel.widthAnchor.constraint(equalTo: widthAnchor),
            letterLabel.heightAnchor.constraint(equalTo: heightAnchor),
        ])
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 3
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        letterLabel.textAlignment = .center
        letterLabel.textColor = .white
        letterLabel.clipsToBounds = true
        letterLabel.layer.cornerCurve = .continuous
        spinner.hidesWhenStopped = true
        applySize()
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        loadTask?.cancel()
    }

    func setSize(_ size: CGFloat) {
        self.size = size
        applySize()
    }

    private func applySize() {
        NSLayoutConstraint.deactivate(sizeConstraints)
        sizeConstraints = [widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)]
        NSLayoutConstraint.activate(sizeConstraints)
        letterLabel.font = .systemFont(ofSize: size * 0.62, weight: .bold)
        letterLabel.layer.cornerRadius = size * 0.28
        spinner.transform = CGAffineTransform(scaleX: size / 22, y: size / 22)
    }

    func themeDidChange(_ theme: CurioTheme) {
        spinner.color = theme.accent.uiColor
    }

    /// Shows the declared or conventional site icon, or the letter for `label`.
    func configure(label: String, url: String?, pageURL: String? = nil, loading: Bool = false) {
        letterLabel.text = Self.initial(label)
        letterLabel.backgroundColor = Self.letterColor(label)
        if loading {
            guard !spinner.isAnimating else { return }
            prepareForReuse()
            spinner.startAnimating()
            letterLabel.isHidden = true
            return
        }
        spinner.stopAnimating()
        let request = Request(pageURL: pageURL, iconURL: url)
        guard request != currentRequest else { return }
        currentRequest = request
        loadTask?.cancel()
        loadTask = nil
        let candidates = FaviconLoader.candidates(declared: url, pageURL: pageURL)
        if let image = loader.cachedImage(for: candidates) {
            show(image)
            return
        }
        showLetter()
        guard !candidates.isEmpty else { return }
        loadTask = Task { [weak self, loader] in
            let image = await loader.image(for: candidates)
            guard !Task.isCancelled, let self, currentRequest == request else { return }
            loadTask = nil
            if let image { show(image) }
        }
    }

    /// Resets state before a reused cell shows another site.
    func prepareForReuse() {
        loadTask?.cancel()
        loadTask = nil
        currentRequest = nil
        spinner.stopAnimating()
        showLetter()
    }

    private func show(_ image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        letterLabel.isHidden = true
    }

    private func showLetter() {
        imageView.image = nil
        imageView.isHidden = true
        letterLabel.isHidden = false
    }

    /// The first letter or digit, uppercased, or a bullet.
    static func initial(_ label: String) -> String {
        label.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
    }

    /// A stable color per label (same hash as the desktop).
    static func letterColor(_ seed: String) -> UIColor {
        var hash: UInt32 = 0
        for byte in seed.utf8 { hash = hash &* 31 &+ UInt32(byte) }
        return HSLA(Double(hash % 360) / 360, 0.55, 0.55).uiColor
    }
}
