//
//  VaultFileBrowserViewController.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import AppKit
import AppKitExtensions
import MarkEditKit

@MainActor
protocol VaultFileBrowserDelegate: AnyObject {
  func fileBrowser(_ browser: VaultFileBrowserViewController, openFile url: URL)
  func fileBrowser(_ browser: VaultFileBrowserViewController, willTrashItem url: URL)
}

/**
 Native file tree for a vault, shown in the window's sidebar.

 Editable files open in the editor with a single click,
 other files open in their default app with a double click.
 */
final class VaultFileBrowserViewController: NSViewController {
  weak var delegate: VaultFileBrowserDelegate?

  private let root: VaultFileNode
  private let outlineView = VaultOutlineView()
  private var watcher: VaultFileWatcher?
  private var expandedURLs = Set<URL>()
  private var selectedURL: URL?

  init(rootURL: URL) {
    self.root = VaultFileNode(url: rootURL, isDirectory: true)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let column = NSTableColumn(identifier: Constants.columnIdentifier)
    column.resizingMask = .autoresizingMask

    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    outlineView.headerView = nil
    outlineView.style = .sourceList
    outlineView.rowSizeStyle = .default
    outlineView.allowsEmptySelection = true
    outlineView.autoresizesOutlineColumn = true
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.target = self
    outlineView.action = #selector(handleClick(_:))
    outlineView.doubleAction = #selector(handleDoubleClick(_:))
    outlineView.keyHandler = { [weak self] event in
      self?.handleKeyDown(event) ?? false
    }

    let menu = NSMenu()
    menu.delegate = self
    outlineView.menu = menu

    let scrollView = NSScrollView()
    scrollView.documentView = outlineView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    view = scrollView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    outlineView.reloadData()

    watcher = VaultFileWatcher(url: root.url) { [weak self] in
      MainActor.assumeIsolated {
        self?.reloadFromDisk()
      }
    }
  }

  /// Expands the ancestors of `url` and selects it, used to follow the active document.
  func reveal(url: URL?) {
    selectedURL = url?.standardizedFileURL
    guard let url, let node = root.node(for: url) else {
      outlineView.deselectAll(nil)
      return
    }

    var ancestors = [VaultFileNode]()
    var current = node.parent
    while let folder = current, folder !== root {
      ancestors.insert(folder, at: 0)
      current = folder.parent
    }

    ancestors.forEach { outlineView.expandItem($0) }
    let row = outlineView.row(forItem: node)
    if row >= 0 {
      outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      outlineView.scrollRowToVisible(row)
    }
  }

  func reloadFromDisk() {
    root.refresh()
    outlineView.reloadData()

    // Restore expansion top-down, children only exist once their parent is expanded
    for url in expandedURLs.sorted(by: { $0.path.count < $1.path.count }) {
      if let node = root.node(for: url) {
        outlineView.expandItem(node)
      } else {
        expandedURLs.remove(url)
      }
    }

    reveal(url: selectedURL)
  }
}

// MARK: - NSOutlineViewDataSource

extension VaultFileBrowserViewController: NSOutlineViewDataSource {
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    node(for: item).children.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    node(for: item).children[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? VaultFileNode)?.isDirectory == true
  }
}

// MARK: - NSOutlineViewDelegate

extension VaultFileBrowserViewController: NSOutlineViewDelegate {
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? VaultFileNode else {
      return nil
    }

    let cell = (outlineView.makeView(withIdentifier: Constants.cellIdentifier, owner: self) as? NSTableCellView) ?? makeCell()
    cell.textField?.stringValue = node.displayName
    cell.textField?.isEditable = false
    cell.textField?.textColor = node.isDirectory || node.isEditable ? .labelColor : .secondaryLabelColor
    cell.imageView?.image = node.icon
    cell.imageView?.contentTintColor = node.isDirectory ? .controlAccentColor : .secondaryLabelColor
    cell.toolTip = node.isDirectory || node.isEditable ? nil : node.name
    return cell
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    if let node = notification.userInfo?["NSObject"] as? VaultFileNode {
      expandedURLs.insert(node.url)
    }
  }

  func outlineViewItemDidCollapse(_ notification: Notification) {
    if let node = notification.userInfo?["NSObject"] as? VaultFileNode {
      expandedURLs.remove(node.url)
    }
  }
}

// MARK: - NSMenuDelegate

extension VaultFileBrowserViewController: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let node = clickedNode

    if let node, !node.isDirectory {
      menu.addItem(withTitle: node.isEditable ? Localized.Vault.open : Localized.Vault.openWithDefaultApp) { [weak self] in
        self?.open(node: node, external: !node.isEditable)
      }

      if node.isEditable {
        menu.addItem(withTitle: Localized.Vault.openWithDefaultApp) { [weak self] in
          self?.open(node: node, external: true)
        }
      }

      menu.addItem(.separator())
    }

    menu.addItem(withTitle: Localized.Vault.newNote) { [weak self] in
      self?.createItem(isFolder: false, in: node)
    }

    menu.addItem(withTitle: Localized.Vault.newFolder) { [weak self] in
      self?.createItem(isFolder: true, in: node)
    }

    guard let node, node !== root else {
      return
    }

    menu.addItem(.separator())
    menu.addItem(withTitle: Localized.Vault.rename) { [weak self] in
      self?.beginRenaming(node: node)
    }

    menu.addItem(withTitle: Localized.Vault.moveToTrash) { [weak self] in
      self?.trash(node: node)
    }

    menu.addItem(.separator())
    menu.addItem(withTitle: Localized.Vault.showInFinder) {
      NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
  }
}

// MARK: - NSTextFieldDelegate

extension VaultFileBrowserViewController: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField else {
      return
    }

    textField.isEditable = false
    let row = outlineView.row(for: textField)
    guard let node = outlineView.item(atRow: row) as? VaultFileNode else {
      return
    }

    let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !newName.isEmpty, newName != node.displayName, !newName.contains("/") else {
      textField.stringValue = node.displayName
      return
    }

    // Keep the hidden extension of markdown files
    let fileName = node.displayName == node.name ? newName : "\(newName).\(node.url.pathExtension)"
    let destination = node.url.deletingLastPathComponent().appending(path: fileName)

    do {
      try FileManager.default.moveItem(at: node.url, to: destination)
      if selectedURL == node.url {
        selectedURL = destination.standardizedFileURL
      }

      reloadFromDisk()
    } catch {
      textField.stringValue = node.displayName
      _ = presentError(error)
    }
  }
}

// MARK: - Private

private extension VaultFileBrowserViewController {
  enum Constants {
    static let columnIdentifier = NSUserInterfaceItemIdentifier("VaultFileColumn")
    static let cellIdentifier = NSUserInterfaceItemIdentifier("VaultFileCell")
  }

  var clickedNode: VaultFileNode? {
    outlineView.item(atRow: outlineView.clickedRow) as? VaultFileNode
  }

  var selectedNode: VaultFileNode? {
    outlineView.item(atRow: outlineView.selectedRow) as? VaultFileNode
  }

  func node(for item: Any?) -> VaultFileNode {
    (item as? VaultFileNode) ?? root
  }

  func makeCell() -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = Constants.cellIdentifier

    let imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyDown

    let textField = NSTextField(labelWithString: "")
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.lineBreakMode = .byTruncatingMiddle
    textField.delegate = self

    cell.addSubview(imageView)
    cell.addSubview(textField)
    cell.imageView = imageView
    cell.textField = textField

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      imageView.widthAnchor.constraint(equalToConstant: 16),
      imageView.heightAnchor.constraint(equalToConstant: 16),
      textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
      textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])

    return cell
  }

  @objc func handleClick(_ sender: Any?) {
    guard let node = clickedNode else {
      return
    }

    if node.isDirectory {
      toggleExpansion(of: node)
    } else if node.isEditable {
      open(node: node, external: false)
    }
  }

  @objc func handleDoubleClick(_ sender: Any?) {
    guard let node = clickedNode, !node.isDirectory, !node.isEditable else {
      return
    }

    open(node: node, external: true)
  }

  /// Returns true when the key event was consumed.
  func handleKeyDown(_ event: NSEvent) -> Bool {
    guard let node = selectedNode else {
      return false
    }

    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch (event.keyCode, modifiers) {
    case (36, []), (76, []): // Return, Enter
      if node.isDirectory {
        toggleExpansion(of: node)
      } else {
        open(node: node, external: !node.isEditable)
      }
      return true
    case (51, [.command]): // Cmd-Delete
      trash(node: node)
      return true
    default:
      return false
    }
  }

  func toggleExpansion(of node: VaultFileNode) {
    if outlineView.isItemExpanded(node) {
      outlineView.animator().collapseItem(node)
    } else {
      outlineView.animator().expandItem(node)
    }
  }

  func open(node: VaultFileNode, external: Bool) {
    if external {
      NSWorkspace.shared.open(node.url)
    } else {
      delegate?.fileBrowser(self, openFile: node.url)
    }
  }

  func createItem(isFolder: Bool, in target: VaultFileNode?) {
    let folder = target.map { $0.isDirectory ? $0 : ($0.parent ?? root) } ?? root
    let baseName = isFolder ? Localized.Vault.untitledFolder : Localized.Vault.untitledNote
    let fileExtension = isFolder ? "" : ".\(AppPreferences.General.newFilenameExtension.rawValue)"

    var url = folder.url.appending(path: baseName + fileExtension)
    var counter = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = folder.url.appending(path: "\(baseName) \(counter)\(fileExtension)")
      counter += 1
    }

    do {
      if isFolder {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      } else {
        try Data().write(to: url, options: .withoutOverwriting)
      }
    } catch {
      _ = presentError(error)
      return
    }

    if folder !== root {
      expandedURLs.insert(folder.url)
    }

    reloadFromDisk()
    guard let node = root.node(for: url) else {
      return
    }

    if !isFolder {
      open(node: node, external: false)
    }

    reveal(url: url)
    beginRenaming(node: node)
  }

  func beginRenaming(node: VaultFileNode) {
    let row = outlineView.row(forItem: node)
    guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
          let textField = cell.textField else {
      return
    }

    textField.isEditable = true
    view.window?.makeFirstResponder(textField)
    textField.currentEditor()?.selectAll(nil)
  }

  func trash(node: VaultFileNode) {
    delegate?.fileBrowser(self, willTrashItem: node.url)

    do {
      try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
      reloadFromDisk()
    } catch {
      _ = presentError(error)
    }
  }
}

// MARK: - VaultOutlineView

private final class VaultOutlineView: NSOutlineView {
  var keyHandler: ((NSEvent) -> Bool)?

  override func keyDown(with event: NSEvent) {
    if keyHandler?(event) != true {
      super.keyDown(with: event)
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    // Right-clicking empty space targets the vault root
    let row = self.row(at: convert(event.locationInWindow, from: nil))
    if row < 0 {
      deselectAll(nil)
    }

    return super.menu(for: event)
  }
}
