import Foundation
import LocalAuthentication
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "Auth")

// MARK: - Authentication Service

/// Handles biometric (Touch ID) and password authentication for privileged operations.
/// Uses LocalAuthentication framework for Touch ID with fallback to system password.
@MainActor
@Observable
public final class AuthenticationService {

    // MARK: - Properties

    /// Whether Touch ID is available on this device
    public var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The type of biometric available (Touch ID on Mac)
    public var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Human-readable name for the biometric type
    public var biometricName: String {
        switch biometricType {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    /// Whether we're currently authenticating
    public private(set) var isAuthenticating = false

    /// Last authentication error
    public private(set) var lastError: AuthError?

    // MARK: - Debug Mode

    #if DEBUG
    /// In debug mode, skip authentication for testing
    /// Use nonisolated(unsafe) since this is only modified at app startup
    public nonisolated(unsafe) static var debugBypassEnabled = false
    #endif

    // MARK: - Initialization

    public init() {}

    // MARK: - Authentication

    /// Authenticate user with Touch ID or password for a privileged operation.
    /// - Parameter reason: The reason shown to user in the auth prompt
    /// - Returns: True if authentication succeeded
    public func authenticate(reason: String) async -> Bool {
        #if DEBUG
        if Self.debugBypassEnabled {
            logger.debug(" Bypassing authentication")
            return true
        }
        #endif

        isAuthenticating = true
        lastError = nil

        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // First try biometrics, then fall back to password
        let policy: LAPolicy = isBiometricAvailable
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if success {
                logger.info(" Authentication successful")
                return true
            } else {
                logger.info(" Authentication returned false")
                lastError = .failed("Authentication was not successful")
                return false
            }
        } catch let error as LAError {
            lastError = mapLAError(error)
            let errorDesc = lastError?.localizedDescription ?? "unknown"
            logger.info("LAError: \(errorDesc)")

            // Only fall back to password for specific cases where it makes sense
            if policy == .deviceOwnerAuthenticationWithBiometrics {
                switch error.code {
                case .biometryLockout:
                    // Too many failed attempts — password is the only option
                    logger.info("Biometry locked out, falling back to password")
                    return await authenticateWithPassword(reason: reason)
                case .userFallback:
                    // User explicitly tapped "Enter Password"
                    logger.info("User requested password fallback")
                    return await authenticateWithPassword(reason: reason)
                case .userCancel:
                    // User cancelled — do NOT show another dialog
                    logger.info("User cancelled authentication")
                    return false
                default:
                    // All other errors (sensor failure, etc.) — do not chain to password
                    logger.info("Biometric error, not falling back to password")
                    return false
                }
            }

            return false
        } catch {
            lastError = .failed(error.localizedDescription)
            logger.info(" Error: \(error.localizedDescription)")
            return false
        }
    }

    /// Authenticate with device password only (no biometrics)
    private func authenticateWithPassword(reason: String) async -> Bool {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success
        } catch {
            lastError = .failed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Error Mapping

    private func mapLAError(_ error: LAError) -> AuthError {
        switch error.code {
        case .userCancel:
            return .cancelled
        case .userFallback:
            return .userRequestedFallback
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLockout
        case .authenticationFailed:
            return .failed("Authentication failed")
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Auth Errors

public enum AuthError: LocalizedError {
    case cancelled
    case userRequestedFallback
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case passcodeNotSet
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authentication was cancelled"
        case .userRequestedFallback:
            return "User requested password fallback"
        case .biometryNotAvailable:
            return "Touch ID is not available on this device"
        case .biometryNotEnrolled:
            return "Touch ID is not set up. Please enable it in System Settings."
        case .biometryLockout:
            return "Touch ID is locked due to too many failed attempts. Please use your password."
        case .passcodeNotSet:
            return "No password is set on this device"
        case .failed(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .biometryNotEnrolled:
            return "Go to System Settings > Touch ID & Password to set up Touch ID."
        case .biometryLockout:
            return "Enter your password to unlock Touch ID."
        default:
            return nil
        }
    }
}
