import Foundation

/// Handles auth.* JSON-RPC methods for biometric / device-owner authentication.
public final class AuthHandler: MethodHandler {
    private let provider: AuthProvider

    public var methods: [String] {
        ["auth.available", "auth.authenticate"]
    }

    public init(provider: AuthProvider = AppleAuthProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "auth.available":
            return try handleAvailable(request)
        case "auth.authenticate":
            return try handleAuthenticate(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        let (available, _) = provider.biometricAvailable()
        // auth.authenticate works even without biometrics (falls back to password),
        // but auth.available reports the biometric hardware state.
        switch method {
        case "auth.available":
            return MethodCapability(available: true)
        case "auth.authenticate":
            return MethodCapability(
                available: true,
                note: available ? nil : "Biometrics unavailable, will use device password"
            )
        default:
            return MethodCapability(available: false)
        }
    }

    // MARK: - Method Implementations

    private func handleAvailable(_ request: JsonRpcRequest) throws -> Any {
        let (available, biometryType) = provider.biometricAvailable()
        return [
            "available": available,
            "biometry_type": biometryType,
        ] as [String: Any]
    }

    private func handleAuthenticate(_ request: JsonRpcRequest) throws -> Any {
        let reason = request.string("reason") ?? "Stik wants to access locked notes"
        let success = try provider.authenticate(reason: reason)
        return ["success": success]
    }
}
