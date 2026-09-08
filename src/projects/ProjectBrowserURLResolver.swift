import Foundation

enum ProjectBrowserURLResolver {
    static func supports(_ bundle: String?) -> Bool {
        bundle == "com.apple.Safari" || bundle == "com.google.Chrome"
    }

    static func normalized(_ raw: String?) -> String? {
        guard let raw, var url = URLComponents(string: raw),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        url.scheme = scheme
        url.host = host
        url.user = nil
        url.password = nil
        if (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) { url.port = nil }
        if url.path.isEmpty { url.path = "/" }
        let ephemeral = Set(["code", "state", "nonce", "access_token", "id_token", "refresh_token", "session_state", "samlresponse", "samlrequest"])
        if let items = url.queryItems {
            let stable = items.filter { !ephemeral.contains($0.name.lowercased()) }
            url.queryItems = stable.isEmpty ? nil : stable
        }
        if let fragment = url.fragment, fragment.contains("access_token=") || fragment.contains("id_token=") { url.fragment = nil }
        return url.string
    }
}
