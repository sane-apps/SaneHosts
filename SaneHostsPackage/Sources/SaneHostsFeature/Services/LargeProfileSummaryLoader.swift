import Foundation

/// Loads a lightweight summary of a large profile JSON file without decoding
/// the full entry payload. The profile filename UUID is canonical identity:
/// the stored top-level `id` must match it (customer reports #1139/#1141 were
/// caused by matching the first nested `entries[].id` instead).
enum LargeProfileSummaryLoader {
    private struct ValueBox<T: Decodable>: Decodable {
        let value: T
    }

    static func loadSummary(from url: URL, previewEntryLimit: Int) throws -> Profile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty else {
            throw ProfileStoreError.loadFailed("Profile file is empty")
        }
        guard let canonicalID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
            throw ProfileStoreError.invalidProfileIdentity("Profile filename is not a UUID")
        }
        guard let storedID = decodeValue(UUID.self, key: "id", in: data) else {
            throw ProfileStoreError.invalidProfileIdentity("Profile payload is missing a top-level ID")
        }
        guard storedID == canonicalID else {
            throw ProfileStoreError.invalidProfileIdentity("Stored profile ID does not match its filename")
        }

        let previewEntries = try decodePreviewEntries(from: data, limit: previewEntryLimit)
        let counts = countEnabledStates(in: data)
        let enabledCount = counts.enabled
        let disabledCount = counts.disabled
        let entryCount = max(enabledCount + disabledCount, previewEntries.count)

        return Profile(
            id: canonicalID,
            name: decodeValue(String.self, key: "name", in: data) ?? "Untitled Profile",
            entries: previewEntries,
            isActive: decodeValue(Bool.self, key: "isActive", in: data) ?? false,
            createdAt: decodeValue(Date.self, key: "createdAt", in: data) ?? Date(),
            modifiedAt: decodeValue(Date.self, key: "modifiedAt", in: data) ?? decodeValue(Date.self, key: "createdAt", in: data) ?? Date(),
            source: decodeValue(ProfileSource.self, key: "source", in: data) ?? .local,
            colorTag: decodeValue(ProfileColor.self, key: "colorTag", in: data) ?? .gray,
            sortOrder: decodeValue(Int.self, key: "sortOrder", in: data) ?? 0,
            entryCountOverride: entryCount,
            enabledCountOverride: enabledCount,
            disabledCountOverride: disabledCount
        )
    }

    private static func decodePreviewEntries(from data: Data, limit: Int) throws -> [HostEntry] {
        guard limit > 0,
              let entriesStart = findArrayStart(forKey: "entries", in: data)
        else {
            return []
        }

        let ranges = data.withUnsafeBytes { rawBuffer -> [Range<Int>] in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var ranges: [Range<Int>] = []
            var index = entriesStart
            var objectStart: Int?
            var depth = 0
            var inString = false
            var isEscaped = false

            while index < bytes.count, ranges.count < limit {
                let byte = bytes[index]

                if inString {
                    if isEscaped {
                        isEscaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        isEscaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                } else {
                    switch byte {
                    case UInt8(ascii: "\""):
                        inString = true
                    case UInt8(ascii: "{"):
                        if depth == 0 {
                            objectStart = index
                        }
                        depth += 1
                    case UInt8(ascii: "}"):
                        depth -= 1
                        if depth == 0, let start = objectStart {
                            ranges.append(start ..< index + 1)
                            objectStart = nil
                        }
                    case UInt8(ascii: "]"):
                        if depth == 0 {
                            return ranges
                        }
                    default:
                        break
                    }
                }

                index += 1
            }
            return ranges
        }

        guard !ranges.isEmpty else { return [] }

        var previewJSON = Data()
        previewJSON.append(UInt8(ascii: "["))
        for (index, range) in ranges.enumerated() {
            if index > 0 {
                previewJSON.append(UInt8(ascii: ","))
            }
            previewJSON.append(contentsOf: data[range])
        }
        previewJSON.append(UInt8(ascii: "]"))
        return try JSONDecoder().decode([HostEntry].self, from: previewJSON)
    }

    private static func findArrayStart(forKey key: String, in data: Data) -> Int? {
        guard let valueStart = findValueStart(forKey: key, in: data) else { return nil }
        return data.withUnsafeBytes { rawBuffer -> Int? in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard valueStart < bytes.count, bytes[valueStart] == UInt8(ascii: "[") else { return nil }
            return valueStart + 1
        }
    }

    private static func decodeValue<T: Decodable>(_: T.Type, key: String, in data: Data) -> T? {
        guard let range = findValueRange(forKey: key, in: data) else { return nil }
        var wrapped = Data(#"{"value":"#.utf8)
        wrapped.append(contentsOf: data[range])
        wrapped.append(UInt8(ascii: "}"))
        return try? JSONDecoder().decode(ValueBox<T>.self, from: wrapped).value
    }

    private static func findValueRange(forKey key: String, in data: Data) -> Range<Int>? {
        guard let start = findValueStart(forKey: key, in: data) else { return nil }
        return data.withUnsafeBytes { rawBuffer -> Range<Int>? in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard start < bytes.count else { return nil }

            switch bytes[start] {
            case UInt8(ascii: "\""):
                var index = start + 1
                var isEscaped = false
                while index < bytes.count {
                    let byte = bytes[index]
                    if isEscaped {
                        isEscaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        isEscaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        return start ..< index + 1
                    }
                    index += 1
                }
                return nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                let open = bytes[start]
                let close = open == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                var index = start
                var depth = 0
                var inString = false
                var isEscaped = false
                while index < bytes.count {
                    let byte = bytes[index]
                    if inString {
                        if isEscaped {
                            isEscaped = false
                        } else if byte == UInt8(ascii: "\\") {
                            isEscaped = true
                        } else if byte == UInt8(ascii: "\"") {
                            inString = false
                        }
                    } else if byte == UInt8(ascii: "\"") {
                        inString = true
                    } else if byte == open {
                        depth += 1
                    } else if byte == close {
                        depth -= 1
                        if depth == 0 {
                            return start ..< index + 1
                        }
                    }
                    index += 1
                }
                return nil
            default:
                var index = start
                while index < bytes.count,
                      bytes[index] != UInt8(ascii: ","),
                      bytes[index] != UInt8(ascii: "}"),
                      bytes[index] != UInt8(ascii: "]") {
                    index += 1
                }
                return start ..< index
            }
        }
    }

    private static func findValueStart(forKey key: String, in data: Data) -> Int? {
        let expectedKey = Array(key.utf8)
        return data.withUnsafeBytes { rawBuffer -> Int? in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var index = 0
            var objectDepth = 0
            var arrayDepth = 0

            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "{"):
                    objectDepth += 1
                    index += 1
                case UInt8(ascii: "}"):
                    objectDepth -= 1
                    index += 1
                case UInt8(ascii: "["):
                    arrayDepth += 1
                    index += 1
                case UInt8(ascii: "]"):
                    arrayDepth -= 1
                    index += 1
                case UInt8(ascii: "\""):
                    let stringStart = index + 1
                    var cursor = stringStart
                    var isEscaped = false
                    while cursor < bytes.count {
                        let byte = bytes[cursor]
                        if isEscaped {
                            isEscaped = false
                        } else if byte == UInt8(ascii: "\\") {
                            isEscaped = true
                        } else if byte == UInt8(ascii: "\"") {
                            break
                        }
                        cursor += 1
                    }
                    guard cursor < bytes.count else { return nil }

                    if objectDepth == 1,
                       arrayDepth == 0,
                       cursor - stringStart == expectedKey.count,
                       expectedKey.indices.allSatisfy({ bytes[stringStart + $0] == expectedKey[$0] }) {
                        var valueStart = cursor + 1
                        while valueStart < bytes.count, isWhitespace(bytes[valueStart]) {
                            valueStart += 1
                        }
                        if valueStart < bytes.count, bytes[valueStart] == UInt8(ascii: ":") {
                            valueStart += 1
                            while valueStart < bytes.count, isWhitespace(bytes[valueStart]) {
                                valueStart += 1
                            }
                            return valueStart
                        }
                    }
                    index = cursor + 1
                default:
                    index += 1
                }
            }
            return nil
        }
    }

    private static func countEnabledStates(in data: Data) -> (enabled: Int, disabled: Int) {
        let keyData = Data(#""isEnabled""#.utf8)
        var enabled = 0
        var disabled = 0
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let keyRange = data.range(of: keyData, options: [], in: searchStart ..< data.endIndex) {
            var cursor = keyRange.upperBound
            while cursor < data.endIndex, isWhitespace(data[cursor]) {
                cursor += 1
            }
            if cursor < data.endIndex, data[cursor] == UInt8(ascii: ":") {
                cursor += 1
                while cursor < data.endIndex, isWhitespace(data[cursor]) {
                    cursor += 1
                }
                if matchesASCII("true", in: data, at: cursor) {
                    enabled += 1
                } else if matchesASCII("false", in: data, at: cursor) {
                    disabled += 1
                }
            }
            searchStart = keyRange.upperBound
        }

        return (enabled, disabled)
    }

    private static func matchesASCII(_ string: String, in data: Data, at index: Int) -> Bool {
        let pattern = Array(string.utf8)
        guard index + pattern.count <= data.endIndex else { return false }
        return pattern.indices.allSatisfy { data[index + $0] == pattern[$0] }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") ||
            byte == UInt8(ascii: "\n") ||
            byte == UInt8(ascii: "\r") ||
            byte == UInt8(ascii: "\t")
    }
}
