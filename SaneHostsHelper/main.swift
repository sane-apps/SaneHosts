import Foundation

/// SaneHostsHelper - Privileged helper daemon for SaneHosts
///
/// This helper runs as a LaunchDaemon with root privileges.
/// It handles operations that require elevated permissions:
/// - Writing to /etc/hosts
/// - Flushing DNS cache
///
/// Communication happens via XPC from the main SaneHosts app.

// MARK: - XPC Listener Delegate

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate the connection is from our main app
        // In production, verify code signing requirements here

        newConnection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        newConnection.exportedObject = HostsHelperService()

        newConnection.invalidationHandler = {
            print("[Helper] Connection invalidated")
        }

        newConnection.interruptionHandler = {
            print("[Helper] Connection interrupted")
        }

        newConnection.resume()
        print("[Helper] Accepted new connection")
        return true
    }
}

// MARK: - Helper Service Implementation

class HostsHelperService: NSObject, HostsHelperProtocol {

    private let hostsPath = "/etc/hosts"

    func writeHostsFile(content: String, reply: @escaping (Bool, String?) -> Void) {
        print("[Helper] writeHostsFile called, content length: \(content.count)")

        do {
            // Create backup first
            let backupPath = "/etc/hosts.sanehosts.backup"
            if FileManager.default.fileExists(atPath: hostsPath) {
                try? FileManager.default.removeItem(atPath: backupPath)
                try FileManager.default.copyItem(atPath: hostsPath, toPath: backupPath)
            }

            // Write new content
            try content.write(toFile: hostsPath, atomically: true, encoding: .utf8)

            // Set proper permissions (644)
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644,
                .ownerAccountName: "root",
                .groupOwnerAccountName: "wheel"
            ], ofItemAtPath: hostsPath)

            print("[Helper] Successfully wrote hosts file")
            reply(true, nil)
        } catch {
            print("[Helper] Failed to write hosts file: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func flushDNSCache(reply: @escaping (Bool, String?) -> Void) {
        print("[Helper] flushDNSCache called")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            // Also kill mDNSResponder for good measure
            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProcess.arguments = ["-HUP", "mDNSResponder"]
            try? killProcess.run()
            killProcess.waitUntilExit()

            if process.terminationStatus == 0 {
                print("[Helper] Successfully flushed DNS cache")
                reply(true, nil)
            } else {
                reply(false, "dscacheutil returned status \(process.terminationStatus)")
            }
        } catch {
            print("[Helper] Failed to flush DNS: \(error)")
            reply(false, error.localizedDescription)
        }
    }

    func readHostsFile(reply: @escaping (String?, String?) -> Void) {
        print("[Helper] readHostsFile called")

        do {
            let content = try String(contentsOfFile: hostsPath, encoding: .utf8)
            reply(content, nil)
        } catch {
            print("[Helper] Failed to read hosts file: \(error)")
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

// MARK: - Protocol (duplicated here for standalone compilation)

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

print("[Helper] SaneHostsHelper v\(HelperConstants.version) started")
print("[Helper] Listening on \(HelperConstants.machServiceName)")

RunLoop.main.run()
