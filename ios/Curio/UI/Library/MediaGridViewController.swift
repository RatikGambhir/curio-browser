import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class MediaGridViewController: UIViewController, UICollectionViewDelegate, PHPhotoLibraryChangeObserver,
                                     UIDocumentPickerDelegate, ThemeObserving {
    private let downloadURLs: () -> [URL]
    private let previewFile: (MediaExport) -> Void
    private let thumbnails = MediaThumbnails()
    private let accessNotice = UILabel()
    private let accessButton = UIButton(configuration: .tinted())
    private let accessStack = UIStackView()
    private let collection: UICollectionView
    private lazy var dataSource = makeDataSource()

    private var active = false
    private var authorization: PHAuthorizationStatus = .notDetermined
    private var authorizationTask: Task<Void, Never>?
    private var scan: Task<Void, Never>?
    private var needsScan = false
    private var items: [MediaItem] = []
    private var displayedItems: [MediaItem] = []
    private var query = ""
    private var preparingFile: Task<Void, Never>?
    private var documentExport: MediaExport?

    init(allowsThreeColumns: Bool, downloadURLs: @escaping () -> [URL], previewFile: @escaping (MediaExport) -> Void) {
        collection = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout(allowsThreeColumns: allowsThreeColumns))
        self.downloadURLs = downloadURLs
        self.previewFile = previewFile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        collection.alwaysBounceVertical = true
        _ = dataSource

        accessNotice.font = .preferredFont(forTextStyle: .footnote)
        accessNotice.adjustsFontForContentSizeCategory = true
        accessNotice.numberOfLines = 0
        accessButton.addAction(UIAction { [weak self] _ in self?.managePhotosAccess() }, for: .primaryActionTriggered)
        accessStack.addArrangedSubview(accessNotice)
        accessStack.addArrangedSubview(accessButton)
        accessStack.axis = .vertical
        accessStack.alignment = .leading
        accessStack.spacing = 4
        accessStack.isLayoutMarginsRelativeArrangement = true
        accessStack.directionalLayoutMargins = .init(top: 0, leading: 8, bottom: 8, trailing: 10)
        NSLayoutConstraint.activate([accessButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            .withPriority(.defaultHigh)])

        let stack = UIStackView(arrangedSubviews: [accessStack, collection])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        ThemeCenter.shared.observe(self)
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            reload()
            requestPhotosAccess()
        } else {
            if canReadPhotos { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
            authorization = .notDetermined
            needsScan = false
            scan?.cancel()
            preparingFile?.cancel()
            thumbnails.reset()
            items.removeAll()
            updateGrid()
        }
    }

    func setQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        updateGrid()
        collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        reload()
    }

    func reload() {
        guard active else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status != authorization {
            if canReadPhotos { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
            authorization = status
            if canReadPhotos { PHPhotoLibrary.shared().register(self) }
            // Access may have been revoked in Settings while Curio was in the background.
            items.removeAll(where: \.isFromPhotos)
            thumbnails.removePhotos()
            scan?.cancel()
            preparingFile?.cancel()
        }
        needsScan = true
        startScan()
        updateGrid()
    }

    private func startScan() {
        guard active, needsScan, scan == nil else { return }
        needsScan = false
        let includePhotos = canReadPhotos
        let downloads = downloadURLs()
        scan = Task { [weak self] in
            let result = await MediaLibrary.load(includePhotos: includePhotos, extraDownloads: downloads)
            guard let self else { return }
            scan = nil
            if active, !Task.isCancelled { items = result }
            startScan()
            updateGrid()
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.reload() }
    }

    private var canReadPhotos: Bool { authorization == .authorized || authorization == .limited }

    private func requestPhotosAccess() {
        guard authorization == .notDetermined, authorizationTask == nil else { return }
        authorizationTask = Task { [weak self] in
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            self?.authorizationTask = nil
            self?.reload()
        }
    }

    private func managePhotosAccess() {
        switch authorization {
        case .limited:
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: parent ?? self)
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        default:
            break
        }
    }

    private func updateGrid() {
        guard isViewLoaded else { return }
        let words = query.split(whereSeparator: \.isWhitespace)
        let visible = active ? (words.isEmpty ? items : items.filter { $0.matches(words) }) : []
        if displayedItems != visible {
            displayedItems = visible
            var snapshot = NSDiffableDataSourceSnapshot<Int, MediaItem>()
            snapshot.appendSections([0])
            snapshot.appendItems(visible)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        updateStatus()
    }

    private func updateStatus() {
        let theme = ThemeCenter.shared.theme
        let (notice, action): (String?, String?) = switch authorization {
        case .limited: ("Showing the photos and videos you’ve shared with Curio.", "Manage Photos Access")
        case .denied: ("Photos access is off. Allow access in Settings to see your Photos library.", "Open Settings")
        case .restricted: ("Photos access is restricted on this device.", nil)
        default: (nil, nil)
        }
        accessStack.isHidden = notice == nil
        accessNotice.text = notice
        accessNotice.textColor = theme.textMuted.uiColor
        accessButton.isHidden = action == nil
        accessButton.configuration?.title = action
        accessButton.tintColor = theme.accentText.uiColor

        guard active, displayedItems.isEmpty else {
            collection.backgroundView = nil
            return
        }
        var state = UIContentUnavailableConfiguration.empty()
        if items.isEmpty && scan != nil {
            state = .loading()
            state.text = "Looking for images and videos…"
        } else if !query.isEmpty {
            state.image = Icon.search.image(28)
            state.text = "No results"
            state.secondaryText = "Nothing in Media matches “\(query)”."
        } else {
            state.image = Icon.media.image(28)
            let copy = LibrarySection.media.emptyCopy
            state.text = copy.title
            state.secondaryText = copy.description
        }
        state.imageProperties.tintColor = theme.textFaint.uiColor
        state.textProperties.color = theme.text.uiColor
        state.secondaryTextProperties.color = theme.textMuted.uiColor
        collection.backgroundView = UIContentUnavailableView(configuration: state)
    }

    func themeDidChange(_ theme: CurioTheme) {
        updateStatus()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        thumbnails.clearCache()
    }

    private static func makeLayout(allowsThreeColumns: Bool) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let libraryWidth = environment.container.effectiveContentSize.width + LibraryViewController.railWidth
            let columns = allowsThreeColumns && libraryWidth > 420 ? 3 : 2
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / Double(columns)),
                                                                heightDimension: .estimated(190)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(190)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(8)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = .init(top: 0, leading: 4, bottom: 10, trailing: 10)
            return section
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Int, MediaItem> {
        let registration = UICollectionView.CellRegistration<MediaTileCell, MediaItem> { cell, _, item in
            cell.configure(item)
        }
        return UICollectionViewDiffableDataSource(collectionView: collection) { collection, indexPath, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        if active { (cell as? MediaTileCell)?.loadThumbnail(using: thumbnails) }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? MediaTileCell)?.stopThumbnail()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        withFile(item) { grid, file in grid.previewFile(file) }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.withFile(item) { $0.share($1) }
                },
                UIAction(title: "Save to Files", image: UIImage(systemName: "folder")) { _ in
                    self?.withFile(item) { $0.save($1) }
                },
                UIAction(title: "Copy", image: UIImage(systemName: "document.on.document")) { _ in
                    self?.withFile(item) { $0.copy($1) }
                },
            ])
        }
    }

    private func withFile(_ item: MediaItem, perform: @escaping (MediaGridViewController, MediaExport) -> Void) {
        guard active, preparingFile == nil else { return }
        preparingFile = Task { [weak self] in
            defer { self?.preparingFile = nil }
            do {
                let file = try await MediaExport.prepare(item)
                guard let self, active, !Task.isCancelled, view.window != nil else { return }
                perform(self, file)
            } catch {
                guard let self, active, !Task.isCancelled, view.window != nil else { return }
                let message = item.isFromPhotos
                    ? "Open this item in Photos and make sure it’s downloaded to this device, then try again."
                    : "The file may have been moved or deleted."
                let alert = UIAlertController(title: "Couldn’t Open Media", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                (parent ?? self).present(alert, animated: true)
            }
        }
    }

    private func share(_ file: MediaExport) {
        let share = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = collection
        share.popoverPresentationController?.sourceRect = collection.bounds
        share.completionWithItemsHandler = { _, _, _, _ in withExtendedLifetime(file) {} }
        (parent ?? self).present(share, animated: true)
    }

    private func save(_ file: MediaExport) {
        let picker = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
        documentExport = file
        picker.delegate = self
        (parent ?? self).present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        documentExport = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        documentExport = nil
    }

    private func copy(_ file: MediaExport) {
        let type = UTType(filenameExtension: file.url.pathExtension) ?? .data
        let provider = NSItemProvider()
        provider.suggestedName = file.url.deletingPathExtension().lastPathComponent
        provider.registerFileRepresentation(for: type, visibility: .all) { completion in
            completion(file.url, false, nil)
            return nil
        }
        UIPasteboard.general.setItemProviders([provider], localOnly: true, expirationDate: nil)
    }
}
