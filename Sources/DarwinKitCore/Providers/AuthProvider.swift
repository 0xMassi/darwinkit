import Foundation
import LocalAuthentication

/// Protocol for biometric / device-owner authentication.
public protocol AuthProvider {
    /// Whether biometric authentication (Touch ID / Apple Watch) is available.
    func biometricAvailable() -> (available: Bool, biometryType: String)

    /// Evaluate device-owner authentication (Touch ID → password fallback).
    /// Blocks until the user responds. Returns true on success, throws on failure.
    func authenticate(reason: String) throws -> Bool
}

/// Real implementation using LAContext (LocalAuthentication framework).
public final class AppleAuthProvider: AuthProvider {

    public init() {}

    public func biometricAvailable() -> (available: Bool, biometryType: String) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        )

        let typeName: String
        switch context.biometryType {
        case .touchID: typeName = "touchID"
        case .opticID: typeName = "opticID"
        default: typeName = "none"
        }

        return (available, typeName)
    }

    public func authenticate(reason: String) throws -> Bool {
        let context = LAContext()

        // Use deviceOwnerAuthentication — tries biometric first, falls back to password.
        // This ensures the prompt always works, even on Macs without Touch ID.
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let msg = error?.localizedDescription ?? "Authentication not available"
            throw JsonRpcError.frameworkUnavailable(msg)
        }

        // LAContext.evaluatePolicy is async — bridge to sync with semaphore
        let semaphore = DispatchSemaphore(value: 0)
        var result: Bool = false
        var authError: Error?

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        ) { success, err in
            result = success
            authError = err
            semaphore.signal()
        }

        semaphore.wait()

        if let authError = authError as? LAError {
            switch authError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw JsonRpcError.operationCancelled
            case .userFallback:
                // User chose password fallback — this shouldn't happen with
                // .deviceOwnerAuthentication since it handles fallback natively
                throw JsonRpcError.operationCancelled
            default:
                throw JsonRpcError.permissionDenied(authError.localizedDescription)
            }
        }

        return result
    }
}
