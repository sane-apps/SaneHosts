import Foundation
import os

/// SaneHostsHelper - Privileged helper daemon for SaneHosts
///
/// This helper runs as a LaunchDaemon with root privileges.
/// It handles operations that require elevated permissions:
/// - Writing to /etc/hosts
/// - Flushing DNS cache
///
/// Communication happens via XPC from the main SaneHosts app.
/// Registered via SMAppService.daemon on macOS 14+.

private let logger = Logger(subsystem: "com.mrsane.SaneHostsHelper", category: "Helper")

// MARK: - XPC Listener Delegate

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Team identifier that must match the connecting app's code signature.
    /// WARNING: This MUST match the DEVELOPMENT_TEAM in Helper.xcconfig.
    private let requiredTeamID = "M78L6FXD48"
    /// Bundle identifier for valid connecting app
    private let requiredBundleID = "com.mrsane.SaneHosts"

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate the connection is from our main app via code signing
        guard validateConnection(newConnection) else {
            logger.error("Rejected connection: code signing validation failed")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        newConnection.exportedObject = HostsHelperService()

        newConnection.invalidationHandler = {
            logger.info("Connection invalidated")
        }

        newConnection.interruptionHandler = {
            logger.warning("Connection interrupted")
        }

        newConnection.resume()
        logger.info("Accepted new connection")
        return true
    }

    /// Validate that the connecting process is signed by our team
    private func validateConnection(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // Get the code object for the connecting process
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let secCode = code else {
            logger.error("Failed to get SecCode for PID \(pid)")
            return false
        }

        // Verify the code signature matches our team ID and bundle ID
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(requiredTeamID)\" and identifier \"\(requiredBundleID)\""
        var secRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
              let req = secRequirement else {
            logger.error("Failed to create security requirement")
            return false
        }

        let result = SecCodeCheckValidity(secCode, [], req)
        if result != errSecSuccess {
            logger.error("Code signing validation failed for PID \(pid): \(result)")
            return false
        }

        logger.info("Code signing validated for PID \(pid)")
        return true
    }
}

// MARK: - Helper Service Implementation

class HostsHelperService: NSObject, HostsHelperProtocol {

    private let hostsPath = "/etc/hosts"

    func writeHostsFile(content: String, reply: @escaping (Bool, String?) -> Void) {
        logger.info("writeHostsFile called, content length: \(content.count)")

        do {
            // Create backup ONLY if it doesn't exist (preserve original system state)
            let backupPath = "/etc/hosts.sanehosts.backup"
            if !FileManager.default.fileExists(atPath: backupPath) && FileManager.default.fileExists(atPath: hostsPath) {
                try? FileManager.default.copyItem(atPath: hostsPath, toPath: backupPath)
                logger.info("Created pristine system backup at \(backupPath)")
            }

            // Write new content
            try content.write(toFile: hostsPath, atomically: true, encoding: .utf8)

            // Set proper permissions (644)
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644,
                .ownerAccountName: "root",
                .groupOwnerAccountName: "wheel"
            ], ofItemAtPath: hostsPath)

            logger.info("Successfully wrote hosts file")
            reply(true, nil)
        } catch {
            logger.error("Failed to write hosts file: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func flushDNSCache(reply: @escaping (Bool, String?) -> Void) {
        logger.info("flushDNSCache called")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            // Also signal mDNSResponder to flush its cache
            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProcess.arguments = ["-HUP", "mDNSResponder"]
            try? killProcess.run()
            killProcess.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.info("Successfully flushed DNS cache")
                reply(true, nil)
            } else {
                reply(false, "dscacheutil returned status \(process.terminationStatus)")
            }
        } catch {
            logger.error("Failed to flush DNS: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func readHostsFile(reply: @escaping (String?, String?) -> Void) {
        logger.info("readHostsFile called")

        do {
            let content = try String(contentsOfFile: hostsPath, encoding: .utf8)
            reply(content, nil)
        } catch {
            logger.error("Failed to read hosts file: \(error)")
            reply(nil, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }
}

// MARK: - Constants

enum HelperConstants {
    static let version = "1.0.0"
    static let machServiceName = "com.mrsane.SaneHostsHelper"
}

// MARK: - Protocol (duplicated for standalone compilation)
// This must match HostsHelperProtocol in the main app's SaneHostsFeature package.

@objc(HostsHelperProtocol)
protocol HostsHelperProtocol {
    func writeHostsFile(content: String, reply: @escaping (Bool, String?) -> Void)
    func flushDNSCache(reply: @escaping (Bool, String?) -> Void)
    func readHostsFile(reply: @escaping (String?, String?) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
}

// MARK: - Main

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

logger.info("SaneHostsHelper v\(HelperConstants.version) started, listening on \(HelperConstants.machServiceName)")

RunLoop.main.run()
