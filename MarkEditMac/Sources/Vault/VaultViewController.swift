//
//  VaultViewController.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import AppKit
import MarkEditKit

/**
 Content of a vault window: the file tree in the sidebar and the active editor next to it.

 The window keeps one `EditorWindowController`, which is handed from document to document
 when another file is opened, so all regular editor behaviors keep working.
 */
final class VaultViewController: NSSplitViewController {
  let rootURL: URL
  private(set) var activeEditor: EditorViewController?

  private let browser: VaultFileBrowserViewController
  private let editorContainer = VaultEditorContainerViewController()
  private var openingURL: URL?

  init(rootURL: URL) {
    self.rootURL = rootURL.standardizedFileURL
    self.browser = VaultFileBrowserViewController(rootURL: rootURL)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var activeDocument: EditorDocument? {
    activeEditor?.document
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    splitView.autosaveName = "VaultSplitView"
    browser.delegate = self

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: browser)
    sidebarItem.minimumThickness = 180
    sidebarItem.maximumThickness = 420
    sidebarItem.canCollapse = true

    let contentItem = NSSplitViewItem(viewController: editorContainer)
    contentItem.minimumThickness = 320

    addSplitViewItem(sidebarItem)
    addSplitViewItem(contentItem)
  }

  func openFile(at url: URL) {
    Task {
      await open(url: url.standardizedFileURL)
    }
  }

  /// Hands the window over to `document`, embedding a fresh editor for it.
  func show(document: EditorDocument) {
    guard let windowController = view.window?.windowController as? EditorWindowController else {
      return Logger.assertFail("Vault window must be managed by EditorWindowController")
    }

    let editor = document.attachToVault(windowController: windowController)
    activeEditor = editor
    editorContainer.embed(editor)

    browser.reveal(url: document.fileURL)
    VaultManager.shared.noteActiveFile(document.fileURL, in: rootURL)
  }
}

// MARK: - VaultFileBrowserDelegate

extension VaultViewController: VaultFileBrowserDelegate {
  func fileBrowser(_ browser: VaultFileBrowserViewController, openFile url: URL) {
    openFile(at: url)
  }

  func fileBrowser(_ browser: VaultFileBrowserViewController, willTrashItem url: URL) {
    guard let fileURL = activeDocument?.fileURL?.standardizedFileURL else {
      return
    }

    // Close the editor when its file, or a folder containing it, goes away
    if fileURL == url.standardizedFileURL || fileURL.path.hasPrefix(url.standardizedFileURL.path + "/") {
      Task {
        await detachActiveDocument()
      }
    }
  }
}

// MARK: - Private

private extension VaultViewController {
  func open(url: URL) async {
    guard activeDocument?.fileURL?.standardizedFileURL != url, openingURL != url else {
      return
    }

    // Opened in a regular window elsewhere, bring that one up instead of stealing it
    let controller = NSDocumentController.shared
    if let existing = controller.document(for: url), existing !== activeDocument, !existing.windowControllers.isEmpty {
      existing.showWindows()
      return
    }

    openingURL = url
    defer { openingURL = nil }

    let document: EditorDocument? = await withCheckedContinuation { continuation in
      controller.openDocument(withContentsOf: url, display: false) { document, _, error in
        if let error {
          NSApp.presentError(error)
        }

        continuation.resume(returning: document as? EditorDocument)
      }
    }

    guard let document else {
      return
    }

    await detachActiveDocument()
    show(document: document)
  }

  func detachActiveDocument() async {
    guard let document = activeDocument, let windowController = view.window?.windowController else {
      return
    }

    if document.isOutdated || document.isDocumentEdited {
      await document.waitUntilSaveCompleted(delay: 0.1)
    }

    editorContainer.embed(nil)
    activeEditor = nil

    // Remove the window controller first, closing a document also closes its windows
    document.removeWindowController(windowController)
    document.skipsClosedTabHistory = true
    document.close()
  }
}

// MARK: - VaultEditorContainerViewController

/**
 Hosts the active editor, or a placeholder when no file is open.
 */
private final class VaultEditorContainerViewController: NSViewController {
  private let placeholder = NSTextField(labelWithString: Localized.Vault.noFileOpen)

  override func loadView() {
    view = NSView()
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    placeholder.textColor = .tertiaryLabelColor
    placeholder.font = .systemFont(ofSize: NSFont.systemFontSize + 2)
    view.addSubview(placeholder)

    NSLayoutConstraint.activate([
      placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  func embed(_ editor: EditorViewController?) {
    children.forEach {
      $0.view.removeFromSuperview()
      $0.removeFromParent()
    }

    placeholder.isHidden = editor != nil
    guard let editor else {
      return
    }

    addChild(editor)
    editor.view.frame = view.bounds
    editor.view.autoresizingMask = [.width, .height]
    view.addSubview(editor.view)
  }
}

// MARK: - NSWindow

extension NSWindow {
  /// The editor shown in this window, for both regular and vault windows.
  var editorViewController: EditorViewController? {
    if let editor = contentViewController as? EditorViewController {
      return editor
    }

    return (contentViewController as? VaultViewController)?.activeEditor
  }

  var vaultViewController: VaultViewController? {
    contentViewController as? VaultViewController
  }
}
