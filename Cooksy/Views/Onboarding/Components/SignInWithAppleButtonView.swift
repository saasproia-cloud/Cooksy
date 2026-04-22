import AuthenticationServices
import CryptoKit
import OSLog
import SwiftUI

/// Drop-in "Sign in with Apple" button that handles nonce generation, credential
/// extraction and Supabase sign-in through `SessionStore.signInWithApple`.
/// Fails silently (toast via SessionStore.lastErrorMessage) if the Apple
/// capability isn't enabled on the target — the app still builds and runs.
struct SignInWithAppleButtonView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "AppleSignIn")
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(
            .signUp,
            onRequest: { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = Self.sha256(nonce)
            },
            onCompletion: { result in
                handle(result)
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Result handler

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let idToken = String(data: identityTokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                logger.error("Apple auth succeeded but no identity token / nonce available")
                sessionStore.lastErrorMessage = "Connexion Apple indisponible."
                return
            }
            Task { await sessionStore.signInWithApple(idToken: idToken, nonce: nonce) }

        case .failure(let error):
            // User-cancel is fine; other errors surface via SessionStore.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            logger.error("Apple auth failed: \(error.localizedDescription, privacy: .public)")
            sessionStore.lastErrorMessage = "Connexion Apple a échoué : \(error.localizedDescription)"
        }
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }

            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
