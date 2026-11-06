//
//  SourceListsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 4/20/22.
//

import UIKit

class SourceListsViewController: UITableViewController {

    var sourceLists: [URL] = SourceManager.shared.sourceLists

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SOURCE_LISTS", comment: "")
        let note = UILabel()
        note.text = "Separate manga sources, library, and history. This section supports legacy .aix sources. New Aidoku 0.7+ source packages are not compatible. The legacy community list is unmaintained, so some providers may no longer work."
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        let add = UIButton(type: .system)
        var configuration = UIButton.Configuration.glass()
        configuration.title = "Add legacy community list"
        add.configuration = configuration
        add.addTarget(self, action: #selector(addCompatibleList), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [note, add])
        stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 350, height: 220))
        footer.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 18)])
        tableView.tableFooterView = footer

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSourceList))

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateSourceLists"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let previousLists = self.sourceLists
                self.sourceLists = SourceManager.shared.sourceLists
                if previousLists.count == self.sourceLists.count {
                    self.tableView.reloadData()
                } else {
                    self.tableView.performBatchUpdates {
                        if previousLists.count > self.sourceLists.count { // remove
                            for (i, url) in previousLists.enumerated() where !self.sourceLists.contains(url) {
                                self.tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .fade)
                            }
                        } else { // add
                            for (i, url) in self.sourceLists.enumerated() where !previousLists.contains(url) {
                                self.tableView.insertRows(at: [IndexPath(row: i, section: 0)], with: .automatic)
                            }
                        }
                    }
                }
            }
        })
    }

    @objc private func addCompatibleList() {
        let url = URL(string: "https://raw.githubusercontent.com/Skittyblock/aidoku-community-sources/gh-pages/")!
        guard !SourceManager.shared.sourceLists.contains(url) else { return }
        Task {
            let success = await SourceManager.shared.addSourceList(url: url)
            if !success {
                let alert = UIAlertController(title: "Couldn’t load source list", message: "Please check your connection and try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                present(alert, animated: true)
            }
        }
    }

    @objc func addSourceList() {
        let alert = UIAlertController(
            title: NSLocalizedString("SOURCE_LIST_ADD", comment: ""),
            message: NSLocalizedString("SOURCE_LIST_ADD_TEXT", comment: ""),
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("SOURCE_LIST_URL", comment: "")
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.keyboardType = .URL
            textField.returnKeyType = .done
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            guard let textField = alert.textFields?.first else { return }
            if let urlString = textField.text,
               let url = URL(string: urlString) {
                Task {
                    let success = await SourceManager.shared.addSourceList(url: url)
                    if !success {
                        let alert = UIAlertController(
                            title: NSLocalizedString("SOURCE_LIST_ADD_FAIL", comment: ""),
                            message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT", comment: ""),
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                        self.present(alert, animated: true)
                    }
                }
            }
        })

        self.present(alert, animated: true)
    }
}

// MARK: - Table View Data Source
extension SourceListsViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sourceLists.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
        }

        cell?.textLabel?.text = sourceLists[indexPath.row].absoluteString
        cell?.selectionStyle = .none

        return cell!
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            SourceManager.shared.removeSourceList(url: sourceLists[indexPath.row])
        }
    }
}
