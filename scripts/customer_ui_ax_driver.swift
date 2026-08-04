import AppKit
import ApplicationServices
import Foundation

private struct Request: Decodable {
    let appName: String
    let bundleID: String?
    let action: String
    let labels: [String]
    let roles: [String]?
    let subroles: [String]?
    let value: String?
    let expected: [[String]]
    let timeoutSeconds: Double?
}

private struct ElementDescription: Codable {
    let role: String
    let label: String
    let identifier: String
}

private struct Response: Codable {
    let status: String
    let control: ElementDescription?
    let action: String
    let observedResult: String
    let matchedReadbacks: [String]
    let performedAt: String
    let error: String?
}

private enum DriverError: LocalizedError {
    case invalidArguments
    case accessibilityDenied
    case appNotRunning(String)
    case controlNotFound([String])
    case actionFailed(String)
    case readbackMissing([[String]])

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "Usage: customer_ui_ax_driver REQUEST.json"
        case .accessibilityDenied:
            "Accessibility permission is required for the AX driver"
        case let .appNotRunning(name):
            "\(name) is not running"
        case let .controlNotFound(labels):
            "No visible AX control matched: \(labels.joined(separator: " | "))"
        case let .actionFailed(action):
            "AX action failed: \(action)"
        case let .readbackMissing(groups):
            "Post-action AX readback missing: \(groups.map { $0.joined(separator: " | ") }.joined(separator: " AND "))"
        }
    }
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return ""
    }
    if let string = value as? String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let attributed = value as? NSAttributedString {
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value as? Bool
}

private func describe(_ element: AXUIElement) -> ElementDescription {
    let role = axString(element, kAXRoleAttribute as String)
    let values = [
        axString(element, kAXTitleAttribute as String),
        axString(element, kAXDescriptionAttribute as String),
        axString(element, kAXValueAttribute as String),
        axString(element, kAXHelpAttribute as String),
        axString(element, "AXPlaceholderValue")
    ].filter { !$0.isEmpty }
    return ElementDescription(
        role: role,
        label: values.first ?? "",
        identifier: axString(element, kAXIdentifierAttribute as String)
    )
}

private func identityStrings(_ element: AXUIElement) -> [String] {
    [
        axString(element, kAXTitleAttribute as String),
        axString(element, kAXDescriptionAttribute as String),
        axString(element, kAXValueAttribute as String),
        axString(element, kAXHelpAttribute as String),
        axString(element, kAXIdentifierAttribute as String),
        axString(element, "AXPlaceholderValue")
    ].filter { !$0.isEmpty }
}

private func descendants(of root: AXUIElement, limit: Int = 8000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    while !queue.isEmpty, result.count < limit {
        let element = queue.removeFirst()
        if axBool(element, kAXHiddenAttribute as String) != true {
            result.append(element)
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return result
}

private func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
        return nil
    }
    return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
}

private func searchableElements(of application: AXUIElement) -> [AXUIElement] {
    let roots = [
        application,
        axElementAttribute(application, kAXMenuBarAttribute as String),
        axElementAttribute(application, kAXExtrasMenuBarAttribute as String)
    ].compactMap { $0 }
    var seen = Set<CFHashCode>()
    return roots.flatMap { descendants(of: $0) }.filter { element in
        seen.insert(CFHash(element)).inserted
    }
}

private func matches(
    _ element: AXUIElement,
    labels: [String],
    roles: [String]?,
    subroles: [String]? = nil
) -> Bool {
    let role = axString(element, kAXRoleAttribute as String)
    if let roles, !roles.isEmpty, !roles.contains(role) {
        return false
    }
    let subrole = axString(element, kAXSubroleAttribute as String)
    if let subroles, !subroles.isEmpty, !subroles.contains(subrole) {
        return false
    }
    let identities = identityStrings(element)
    return labels.contains { wanted in
        identities.contains { actual in
            actual.caseInsensitiveCompare(wanted) == .orderedSame ||
                actual.localizedCaseInsensitiveContains(wanted)
        }
    }
}

private func supportedActions(of element: AXUIElement) -> [String] {
    var value: CFArray?
    guard AXUIElementCopyActionNames(element, &value) == .success,
          let actions = value as? [String]
    else {
        return []
    }
    return actions
}

private func showMenu(on element: AXUIElement) -> AXError {
    let actions = supportedActions(of: element)
    if actions.contains(kAXShowMenuAction as String) {
        let result = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        if result == .success {
            return result
        }
    }
    if actions.contains(kAXPressAction as String) {
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
    return AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
}

private func appleScriptLiteral(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func systemClick(request: Request) -> AXError {
    guard let bundleID = request.bundleID, let label = request.labels.first else {
        return .illegalArgument
    }
    let script = """
    tell application "System Events"
      set appProcess to first application process whose bundle identifier is "\(appleScriptLiteral(bundleID))"
      tell appProcess to click first button of sheet 1 of window 1 whose description is "\(appleScriptLiteral(label))"
    end tell
    """
    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else { return .failure }
    appleScript.executeAndReturnError(&error)
    return error == nil ? .success : .failure
}

private func targetElement(for request: Request, in elements: [AXUIElement]) -> AXUIElement? {
    let candidates = elements.filter {
        matches(
            $0,
            labels: request.labels,
            roles: request.roles,
            subroles: request.subroles
        ) && axBool($0, kAXEnabledAttribute as String) != false
    }
    let exactCandidates = candidates.filter { element in
        let identities = identityStrings(element)
        return request.labels.contains { wanted in
            identities.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
        }
    }
    let orderedCandidates = exactCandidates + candidates.filter { candidate in
        !exactCandidates.contains { CFEqual($0, candidate) }
    }
    if request.action == "press" || request.action == "pick" || request.action == "system_click" {
        let requestedAction = request.action == "pick" ? kAXPickAction as String : kAXPressAction as String
        let actionCandidates = orderedCandidates.filter {
            supportedActions(of: $0).contains(requestedAction)
        }
        let semanticRoles = ["AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton"]
        return actionCandidates.first(where: {
            semanticRoles.contains(axString($0, kAXRoleAttribute as String))
        }) ?? actionCandidates.first ?? orderedCandidates.first
    }
    guard request.action == "show_menu" else {
        return orderedCandidates.first
    }
    if let showMenuCandidate = orderedCandidates.first(where: {
        supportedActions(of: $0).contains(kAXShowMenuAction as String)
    }) {
        return showMenuCandidate
    }
    let allowsPressFallback = request.subroles?.contains("AXMenuExtra") == true
    guard allowsPressFallback else { return nil }
    return orderedCandidates.first(where: {
        supportedActions(of: $0).contains(kAXPressAction as String)
    })
}

private func runningApplication(for request: Request) throws -> NSRunningApplication {
    if let bundleID = request.bundleID,
       let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
        return app
    }
    if let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName?.caseInsensitiveCompare(request.appName) == .orderedSame
    }) {
        return app
    }
    throw DriverError.appNotRunning(request.appName)
}

private func waitForElements(
    root: AXUIElement,
    groups: [[String]],
    timeout: Double
) throws -> [String] {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let elements = searchableElements(of: root)
        let matchedLabels = groups.compactMap { group -> String? in
            for label in group where elements.contains(where: { matches($0, labels: [label], roles: nil) }) {
                return label
            }
            return nil
        }
        if matchedLabels.count == groups.count {
            return matchedLabels
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    throw DriverError.readbackMissing(groups)
}

private func perform(_ request: Request) throws -> Response {
    guard AXIsProcessTrusted() else {
        throw DriverError.accessibilityDenied
    }
    guard !request.expected.isEmpty else {
        throw DriverError.readbackMissing([])
    }

    let app = try runningApplication(for: request)
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let timeout = max(1, request.timeoutSeconds ?? 12)
    var control: ElementDescription?

    if request.action != "read" {
        let deadline = Date().addingTimeInterval(timeout)
        var target: AXUIElement?
        repeat {
            target = targetElement(for: request, in: searchableElements(of: root))
            if target == nil {
                Thread.sleep(forTimeInterval: 0.2)
            }
        } while target == nil && Date() < deadline

        guard let target else {
            throw DriverError.controlNotFound(request.labels)
        }
        control = describe(target)

        let result: AXError
        switch request.action {
        case "press":
            result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        case "pick":
            result = AXUIElementPerformAction(target, kAXPickAction as CFString)
        case "system_click":
            result = systemClick(request: request)
        case "show_menu":
            result = showMenu(on: target)
        case "set_value":
            guard let value = request.value else {
                throw DriverError.actionFailed("set_value requires value")
            }
            result = AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, value as CFTypeRef)
        default:
            throw DriverError.actionFailed("unsupported action \(request.action)")
        }
        let menuOpenedWithoutSynchronousCompletion = request.action == "show_menu" && result == .cannotComplete
        guard result == .success || menuOpenedWithoutSynchronousCompletion else {
            throw DriverError.actionFailed("\(request.action) returned \(result.rawValue)")
        }
    }

    let readbacks = try waitForElements(root: root, groups: request.expected, timeout: timeout)
    return Response(
        status: "passed",
        control: control,
        action: request.action,
        observedResult: readbacks.joined(separator: " | "),
        matchedReadbacks: readbacks,
        performedAt: ISO8601DateFormatter().string(from: Date()),
        error: nil
    )
}

private func emit(_ response: Response) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! encoder.encode(response)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw DriverError.invalidArguments
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let request = try JSONDecoder().decode(Request.self, from: data)
    try emit(perform(request))
} catch {
    emit(Response(
        status: "failed",
        control: nil,
        action: "none",
        observedResult: "",
        matchedReadbacks: [],
        performedAt: ISO8601DateFormatter().string(from: Date()),
        error: error.localizedDescription
    ))
    exit(1)
}
