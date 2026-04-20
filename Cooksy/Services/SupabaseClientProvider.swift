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
            return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        } catch {
            logger.fault("Failed to initialize Supabase client: \(error.localizedDescription, privacy: .public)")
            fatalError("Supabase misconfigured: \(error.localizedDescription)")
        }
    }()
}
