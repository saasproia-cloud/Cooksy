import Foundation
import OSLog
import Supabase

enum SupabaseClientProvider {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "SupabaseClient")

    static let shared: SupabaseClient = {
        do {
            let url = try AppConfiguration.supabaseURL
            let anonKey = try AppConfiguration.supabaseAnonKey
            logger.debug("Supabase client initialized for host=\(url.host ?? "(nil)", privacy: .public)")

            // Opt into the new auth behaviour where the locally-stored session
            // is emitted as the initial event regardless of expiry. This
            // silences the Supabase deprecation warning we see at launch and
            // matches what `SessionStore.refreshSession()` already expects.
            let options = SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
            return SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)
        } catch {
            logger.fault("Failed to initialize Supabase client: \(error.localizedDescription, privacy: .public)")
            fatalError("Supabase misconfigured: \(error.localizedDescription)")
        }
    }()
}
