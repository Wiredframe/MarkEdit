//
//  VaultFileWatcher.swift
//  MarkEditMac
//
//  Created by Wiredframe on 10/29/26.
//

import Foundation

/**
 Watches a folder recursively with FSEvents and reports coalesced changes on the main queue.
 */
final class VaultFileWatcher {
  private let handler: () -> Void
  private var stream: FSEventStreamRef?

  init(url: URL, handler: @escaping () -> Void) {
    self.handler = handler

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )

    let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
      guard let info else {
        return
      }

      Unmanaged<VaultFileWatcher>.fromOpaque(info).takeUnretainedValue().handler()
    }

    stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      callback,
      &context,
      [url.path] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      0.3,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
    )

    if let stream {
      FSEventStreamSetDispatchQueue(stream, .main)
      FSEventStreamStart(stream)
    }
  }

  deinit {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
  }
}
