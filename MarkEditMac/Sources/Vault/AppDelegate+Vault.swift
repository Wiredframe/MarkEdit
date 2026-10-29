//
//  AppDelegate+Vault.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import AppKit

@MainActor
extension AppDelegate {
  @objc func openVaultFolder(_ sender: Any?) {
    VaultManager.shared.showOpenPanel()
  }

  /// Adds "Open Folder…" below "Open…" and "Show Sidebar" next to the full screen toggle.
  func installVaultMenuItems() {
    if let fileMenu = mainFileMenu {
      let index = fileMenu.items.firstIndex { $0.action == #selector(NSDocumentController.openDocument(_:)) } ?? 0
      let item = NSMenuItem(title: Localized.Vault.openFolder, action: #selector(openVaultFolder(_:)), keyEquivalent: "o")
      item.keyEquivalentModifierMask = [.control, .command]
      item.target = self
      item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
      fileMenu.insertItem(item, at: index + 1)
    }

    let viewMenu = NSApp.mainMenu?.items
      .compactMap(\.submenu)
      .first { menu in menu.items.contains { $0.action == #selector(NSWindow.toggleFullScreen(_:)) } }

    if let viewMenu {
      // NSSplitViewController retitles this to "Show Sidebar" or "Hide Sidebar"
      let item = NSMenuItem(title: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
      item.keyEquivalentModifierMask = [.control, .command]
      item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
      viewMenu.insertItem(item, at: 0)
    }
  }
}
