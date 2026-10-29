//
//  VaultManager.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import AppKit
import MarkEditKit

/**
 Opens folders as vault windows and restores them on the next launch.
 */
@MainActor
final class VaultManager {
  static let shared = VaultManager()

  private var windowControllers = [EditorWindowController]()

  private init() {}

  var hasOpenVaults: Bool {
    !windowControllers.isEmpty
  }

  func showOpenPanel() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = Localized.Vault.openFolderPrompt
    panel.message = Localized.Vault.openFolderMessage

    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else {
        return
      }

      self?.openVault(at: url)
    }
  }

  func openVault(at url: URL, activeFile: URL? = nil) {
    let rootURL = url.standardizedFileURL
    if let existing = windowControllers.first(where: { $0.window?.vaultViewController?.rootURL == rootURL }) {
      existing.window?.makeKeyAndOrderFront(nil)
      return
    }

    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let sceneIdentifier = NSStoryboard.SceneIdentifier("EditorWindowController")
    guard let windowController = storyboard.instantiateController(withIdentifier: sceneIdentifier) as? EditorWindowController,
          let window = windowController.window else {
      return Logger.assertFail("Failed to create the vault window")
    }

    let vaultController = VaultViewController(rootURL: rootURL)
    let initialFrame = window.frame
    windowController.contentViewController = vaultController
    windowController.shouldCascadeWindows = false
    windowController.windowFrameAutosaveName = Constants.frameAutosaveName

    if !window.setFrameUsingName(Constants.frameAutosaveName) {
      // Make room for the sidebar the first time
      var frame = initialFrame
      frame.size.width += 260
      window.setFrame(frame, display: false)
    }

    window.tabbingMode = .disallowed
    window.title = rootURL.lastPathComponent
    window.representedURL = rootURL

    windowControllers.append(windowController)
    windowController.showWindow(nil)
    remember(rootURL: rootURL)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: window
    )

    let fileToOpen = activeFile ?? storedVaults.first { $0.path == rootURL.path }?.activeFile.map(URL.init(fileURLWithPath:))
    if let fileToOpen, FileManager.default.fileExists(atPath: fileToOpen.path) {
      vaultController.openFile(at: fileToOpen)
    }
  }

  func restoreVaults() {
    for vault in storedVaults {
      let url = URL(fileURLWithPath: vault.path, isDirectory: true)
      if FileManager.default.fileExists(atPath: url.path) {
        openVault(at: url)
      } else {
        forget(rootURL: url)
      }
    }
  }

  func noteActiveFile(_ fileURL: URL?, in rootURL: URL) {
    storedVaults = storedVaults.map {
      $0.path == rootURL.path ? StoredVault(path: $0.path, activeFile: fileURL?.path) : $0
    }
  }
}

// MARK: - Private

private extension VaultManager {
  enum Constants {
    static let frameAutosaveName = "Vault"
    static let storageKey = "VaultManager.openVaults"
  }

  struct StoredVault: Codable {
    let path: String
    let activeFile: String?
  }

  var storedVaults: [StoredVault] {
    get {
      guard let data = UserDefaults.standard.data(forKey: Constants.storageKey) else {
        return []
      }

      return (try? JSONDecoder().decode([StoredVault].self, from: data)) ?? []
    }
    set {
      UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Constants.storageKey)
    }
  }

  func remember(rootURL: URL) {
    guard !storedVaults.contains(where: { $0.path == rootURL.path }) else {
      return
    }

    storedVaults.append(StoredVault(path: rootURL.path, activeFile: nil))
  }

  func forget(rootURL: URL) {
    storedVaults.removeAll { $0.path == rootURL.path }
  }

  @objc func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else {
      return
    }

    // Quitting the app doesn't close windows, so vaults closed here are closed on purpose
    if let rootURL = window.vaultViewController?.rootURL {
      forget(rootURL: rootURL)
    }

    NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    windowControllers.removeAll { $0.window === window }
  }
}
