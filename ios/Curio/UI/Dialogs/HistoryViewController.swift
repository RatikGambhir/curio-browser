import UIKit

/// Recent history, newest first. Tapping a page opens it in a new tab.
final class HistoryViewController: UIViewController, UICollectionViewDelegate {
    private let history: HistoryStore
    private var entries: [HistoryEntry] = []
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let empty = EmptyStateView(title: "No history yet.", description: "Pages you visit show up here.", icon: .history)
    var onOpen: ((String) -> Void)?
    var onCleared: (() -> Void)?

    init(history: HistoryStore) {
        self.history = history
        super.init(nibName: nil, bundle: nil)
        title = "History"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeCenter.shared.theme.surface.uiColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Clear All History", primaryAction: UIAction { [weak self] _ in
            self?.confirmClear()
        })
        navigationItem.leftBarButtonItem?.tintColor = ThemeCenter.shared.theme.danger.uiColor
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.backgroundColor = .clear
        list.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            empty.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            empty.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let registration = UICollectionView.CellRegistration<PageRowCell, String> { [weak self] cell, indexPath, _ in
            guard let self, entries.indices.contains(indexPath.item) else { return }
            let entry = entries[indexPath.item]
            let host = Curio.displayHost(entry.url)
            cell.configure(title: entry.title.isEmpty ? host : entry.title, subtitle: entry.url, faviconLabel: host, favicon: nil)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
        reload()
    }

    private func reload() {
        entries = history.recent(limit: 300)
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(entries.map(\.url))
        dataSource.apply(snapshot, animatingDifferences: false)
        empty.isHidden = !entries.isEmpty
        navigationItem.leftBarButtonItem?.isEnabled = !entries.isEmpty
    }

    private func confirmClear() {
        let alert = UIAlertController(title: "Clear all history?", message: "Every page you visited will be removed from history and address bar suggestions.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear History", style: .destructive) { [weak self] _ in
            self?.history.clear()
            self?.reload()
            self?.onCleared?()
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard entries.indices.contains(indexPath.item) else { return }
        let url = entries[indexPath.item].url
        dismiss(animated: true) { [onOpen] in onOpen?(url) }
    }
}
