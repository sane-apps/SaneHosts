# SaneHosts Best Practices Reference

> Single source of truth for implementation patterns, UX guidelines, and technical decisions.
> Last updated: 2026-01-18

---

## Table of Contents

1. [Download Progress Tracking](#1-download-progress-tracking)
2. [Large File Parsing](#2-large-file-parsing)
3. [Progress UI/UX](#3-progress-uiux)
4. [SwiftUI Observable Patterns](#4-swiftui-observable-patterns)
5. [How Other Apps Do It](#5-how-other-apps-do-it)
6. [Architecture Decisions](#6-architecture-decisions)

---

## 1. Download Progress Tracking

### Use URLSessionDownloadDelegate (NOT AsyncBytes)

**Why:** AsyncBytes processes byte-by-byte, which is **500% slower** when updating UI. URLSessionDownloadDelegate is purpose-built for downloads.

```swift
@MainActor
@Observable
class DownloadManager: NSObject, URLSessionDownloadDelegate {
    var progress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var statusMessage: String = ""

    func download(from url: URL) async throws -> URL {
        statusMessage = "Connecting..."

        let (downloadURL, response) = try await URLSession.shared.download(
            from: url,
            delegate: self
        )

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.badResponse
        }

        return downloadURL
    }

    // Called frequently during download - this is where progress comes from
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite

            if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown {
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let mb = Double(totalBytesWritten) / 1_000_000
                self.statusMessage = String(format: "Downloading... %.1f MB (%.0f%%)", mb, self.progress * 100)
            } else {
                let mb = Double(totalBytesWritten) / 1_000_000
                self.statusMessage = String(format: "Downloading... %.1f MB", mb)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Required by protocol - actual handling done in async method
    }
}
```

### Handle Unknown Content-Length

When server doesn't provide Content-Length, `totalBytesExpectedToWrite` equals `NSURLSessionTransferSizeUnknown` (-1).

```swift
var isIndeterminate: Bool {
    totalBytes == NSURLSessionTransferSizeUnknown || totalBytes <= 0
}

// In UI: show spinner if indeterminate, progress bar if determinate
if isIndeterminate {
    ProgressView()  // Spinner
    Text("Downloaded: \(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file))")
} else {
    ProgressView(value: progress)  // Bar
    Text("\(Int(progress * 100))%")
}
```

---

## 2. Large File Parsing

### Stream Parse - NEVER Load All Into Memory

**Why:** Loading 80k+ lines into memory causes crashes and UI freezes.

```swift
// GOOD: Stream with URL.lines
func parseHostsFile(at url: URL) async throws -> [HostEntry] {
    var entries: [HostEntry] = []
    entries.reserveCapacity(10000)  // Pre-allocate for performance

    var lineNumber = 0
    for try await line in url.lines {
        lineNumber += 1

        // Skip comments and empty lines
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

        if let entry = parseLine(trimmed, lineNumber: lineNumber) {
            entries.append(entry)
        }

        // Yield every 1000 lines to keep UI responsive
        if lineNumber % 1000 == 0 {
            await Task.yield()
        }
    }

    return entries
}
```

### Use Task.detached for CPU-Heavy Work

```swift
@MainActor
class ParsingService {
    var progress: Double = 0
    var statusMessage: String = ""

    func parseRemoteFile(localURL: URL, estimatedLines: Int) async throws -> [HostEntry] {
        statusMessage = "Parsing entries..."

        // Detached task runs OFF the main thread
        let entries = try await Task.detached(priority: .userInitiated) {
            var results: [HostEntry] = []
            results.reserveCapacity(min(estimatedLines, 10000))

            var lineNumber = 0
            var batch: [HostEntry] = []

            for try await line in localURL.lines {
                lineNumber += 1

                if let entry = Self.parseLine(line, number: lineNumber) {
                    batch.append(entry)
                }

                // Report progress every 500 lines
                if lineNumber % 500 == 0 {
                    let currentBatch = batch
                    let currentLine = lineNumber
                    batch.removeAll(keepingCapacity: true)

                    await MainActor.run { [weak self] in
                        self?.progress = Double(currentLine) / Double(estimatedLines)
                        self?.statusMessage = "Parsed \(currentLine.formatted()) entries..."
                    }

                    results.append(contentsOf: currentBatch)
                    await Task.yield()  // Allow cancellation
                }
            }

            results.append(contentsOf: batch)
            return results
        }.value

        statusMessage = "Found \(entries.count.formatted()) entries"
        return entries
    }

    // Static/nonisolated to avoid MainActor overhead
    nonisolated static func parseLine(_ line: String, number: Int) -> HostEntry? {
        // Pure parsing logic here
    }
}
```

### Batch UI Updates

**Rule:** Never update UI on every line. Batch every 500-1000 items.

```swift
// BAD - updates UI 80,000 times
for line in lines {
    await MainActor.run { progress = Double(i) / Double(total) }
}

// GOOD - updates UI ~160 times
if lineNumber % 500 == 0 {
    await MainActor.run { progress = Double(lineNumber) / Double(total) }
}
```

---

## 3. Progress UI/UX

### When to Use Each Progress Type

| Duration | Progress Type | Example |
|----------|--------------|---------|
| < 1 second | None | Button state change only |
| 1-2 seconds | Button feedback | Disabled state, slight animation |
| 2-9 seconds | Indeterminate | Spinner |
| 10+ seconds | Determinate | Progress bar with percentage |

### Hybrid Approach (Recommended)

Start indeterminate, switch to determinate once total is known:

```swift
struct ImportProgressView: View {
    let downloadProgress: Double
    let parseProgress: Double
    let statusMessage: String
    let phase: ImportPhase

    enum ImportPhase {
        case connecting
        case downloading
        case parsing
        case saving
    }

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .connecting:
                ProgressView()
                Text("Connecting...")

            case .downloading:
                if downloadProgress > 0 {
                    ProgressView(value: downloadProgress)
                    Text("\(Int(downloadProgress * 100))%")
                } else {
                    ProgressView()
                }
                Text(statusMessage)

            case .parsing:
                ProgressView(value: parseProgress)
                Text(statusMessage)

            case .saving:
                ProgressView()
                Text("Saving...")
            }

            Button("Cancel") { /* cancel */ }
        }
    }
}
```

### Keep Animation Moving

**Critical:** Users interpret ANY pause as a freeze. Even at 99%, keep something moving.

```swift
// Add subtle pulse animation during indeterminate phases
@State private var isPulsing = false

Circle()
    .scaleEffect(isPulsing ? 1.1 : 1.0)
    .opacity(isPulsing ? 0.8 : 1.0)
    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
    .onAppear { isPulsing = true }
```

### Always Include Cancel

```swift
struct ImportSheet: View {
    @State private var importTask: Task<Void, Never>?

    func startImport() {
        importTask = Task {
            do {
                for try await update in importService.import(url: url) {
                    // Check for cancellation
                    try Task.checkCancellation()
                    handleUpdate(update)
                }
            } catch is CancellationError {
                // Clean up gracefully
                await importService.cleanup()
            }
        }
    }

    func cancel() {
        importTask?.cancel()
        dismiss()
    }
}
```

---

## 4. SwiftUI Observable Patterns

### Observing Singletons

**Wrong:** Using @State with singleton creates a copy
```swift
// BAD - creates a copy, won't observe changes
@State private var service = RemoteSyncService.shared
```

**Right:** Computed property or @Environment
```swift
// GOOD - always references the singleton
var service: RemoteSyncService { RemoteSyncService.shared }

// BETTER - inject via environment
@Environment(RemoteSyncService.self) private var service
```

### @MainActor for UI-Bound Services

```swift
@MainActor
@Observable
class ImportService {
    var progress: Double = 0
    var statusMessage: String = ""
    var isImporting: Bool = false

    // All property updates automatically on main thread
    func startImport() async {
        isImporting = true
        // ...
    }
}
```

### Background Work Pattern

```swift
@MainActor
@Observable
class DataService {
    var results: [Item] = []
    var isLoading = false

    func loadData() async {
        isLoading = true

        // Heavy work on background thread
        let items = await Task.detached(priority: .userInitiated) {
            // CPU-intensive work here
            return processItems()
        }.value

        // Back on MainActor automatically
        results = items
        isLoading = false
    }
}
```

---

## 5. How Other Apps Do It

### Pi-hole (Industry Standard)
- **Stream parsing** with shell utilities
- **SQLite database** for storage (not in-memory arrays)
- **ETag caching** to skip unchanged files
- **Checksums** to detect changes
- **Graceful cancellation** with cleanup
- **10 backup rotation**

### Apple Finder
- **Non-modal** - operations don't block the app
- **Discoverable detail** - click to see per-file progress
- **Resume support** - partial downloads can continue

### Key Patterns from Real Apps

1. **Two-phase processing:**
   - Download to temp file
   - Validate/parse
   - Only then write to final location

2. **Checksum-based change detection:**
   - MD5/SHA1 to skip unchanged imports
   - ETag headers for HTTP caching

3. **Managed sections with markers:**
   ```
   # ---- SaneHosts Managed Start ----
   ... entries ...
   # ---- SaneHosts Managed End ----
   ```

4. **No hard entry limits** - but warn at 50k+

---

## 6. Architecture Decisions

### File Download + Parse Pipeline

```
1. CONNECT    → Show spinner, "Connecting..."
2. DOWNLOAD   → Show progress bar, "Downloading... X MB (Y%)"
3. PARSE      → Show progress bar, "Parsing... X entries"
4. VALIDATE   → Show spinner, "Validating..."
5. SAVE       → Show spinner, "Saving..."
6. COMPLETE   → Dismiss, show success
```

### Error Handling

```swift
enum ImportError: LocalizedError {
    case networkError(underlying: Error)
    case invalidFormat
    case noValidEntries
    case cancelled

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Download failed: \(error.localizedDescription)"
        case .invalidFormat:
            return "The file format is not recognized"
        case .noValidEntries:
            return "No valid host entries found in the file"
        case .cancelled:
            return "Import was cancelled"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again"
        case .invalidFormat, .noValidEntries:
            return "Make sure the URL points to a valid hosts file"
        case .cancelled:
            return nil
        }
    }
}
```

### Memory Management

```swift
// Pre-allocate arrays when size is known
var entries: [HostEntry] = []
entries.reserveCapacity(estimatedCount)

// Use autoreleasepool for Objective-C interop
for chunk in chunks {
    autoreleasepool {
        processChunk(chunk)
    }
}

// Yield periodically to allow cancellation and prevent blocking
if lineNumber % 1000 == 0 {
    await Task.yield()
}
```

---

## Quick Reference Card

| Problem | Solution |
|---------|----------|
| Download progress | `URLSessionDownloadDelegate`, NOT `AsyncBytes` |
| Large file parsing | `URL.lines` stream, NOT `String(contentsOf:)` |
| UI updates | Batch every 500-1000 items |
| Background work | `Task.detached` + `MainActor.run` |
| Singleton observation | Computed property, NOT `@State` |
| Progress unknown | Indeterminate spinner + status text |
| Progress known | Determinate bar + percentage |
| Long operations | Always include Cancel button |
| Cancellation | `Task.checkCancellation()` + cleanup |

---

## Sources

- Apple HIG: Progress Indicators
- WWDC23: Discover Observation in SwiftUI
- WWDC24: Analyze Heap Memory
- Pi-hole gravity.sh implementation
- StevenBlack/hosts updateHostsFile.py
- Swift Forums: Large file parsing discussions
- Nielsen Norman Group: Progress indicators research
