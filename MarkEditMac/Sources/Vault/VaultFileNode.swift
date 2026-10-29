//
//  VaultFileNode.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import AppKit

/**
 One entry of the vault file tree.

 Children are listed lazily on first access and kept across refreshes,
 so expanded folders survive file system changes.
 */
@MainActor
final class VaultFileNode {
  let url: URL
  let isDirectory: Bool
  weak var parent: VaultFileNode?

  private var cachedChildren: [VaultFileNode]?

  init(url: URL, isDirectory: Bool, parent: VaultFileNode? = nil) {
    self.url = url.standardizedFileURL
    self.isDirectory = isDirectory
    self.parent = parent
  }

  var name: String {
    url.lastPathComponent
  }

  /// Files we edit in-app, everything else is handed to its default app.
  var isEditable: Bool {
    !isDirectory && Self.editableExtensions.contains(url.pathExtension.lowercased())
  }

  /// Markdown files are shown without extension, like in Obsidian.
  var displayName: String {
    isEditable && url.pathExtension.lowercased() != "textbundle" ? url.deletingPathExtension().lastPathComponent : name
  }

  var icon: NSImage? {
    if isDirectory {
      return NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
    }

    if isEditable {
      return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
    }

    return NSWorkspace.shared.icon(forFile: url.path)
  }

  var children: [VaultFileNode] {
    if let cachedChildren {
      return cachedChildren
    }

    let children = listChildren(reusing: [:])
    cachedChildren = children
    return children
  }

  var hasLoadedChildren: Bool {
    cachedChildren != nil
  }

  /// Re-reads loaded folders from disk, keeping node identity for entries that still exist.
  func refresh() {
    guard isDirectory, let cachedChildren else {
      return
    }

    let existing = Dictionary(cachedChildren.map { ($0.url, $0) }) { first, _ in first }
    let children = listChildren(reusing: existing)
    self.cachedChildren = children
    children.forEach { $0.refresh() }
  }

  func node(for url: URL) -> VaultFileNode? {
    let target = url.standardizedFileURL
    if target == self.url {
      return self
    }

    guard isDirectory, target.path.hasPrefix(self.url.path + "/") else {
      return nil
    }

    for child in children {
      if let match = child.node(for: target) {
        return match
      }
    }

    return nil
  }
}

// MARK: - Private

private extension VaultFileNode {
  static let editableExtensions: Set<String> = Set(NewFilenameExtension.allCases.map(\.rawValue) + ["mdown", "mkd", "mkdn", "textbundle"])

  func listChildren(reusing existing: [URL: VaultFileNode]) -> [VaultFileNode] {
    guard isDirectory else {
      return []
    }

    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )) ?? []

    let nodes = urls.map { childURL in
      let values = try? childURL.resourceValues(forKeys: Set(keys))
      let isDirectory = values?.isDirectory == true && values?.isPackage != true
      if let node = existing[childURL.standardizedFileURL], node.isDirectory == isDirectory {
        return node
      }

      return VaultFileNode(url: childURL, isDirectory: isDirectory, parent: self)
    }

    // Folders first, then Finder-like ordering
    return nodes.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory
      }

      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }
}
