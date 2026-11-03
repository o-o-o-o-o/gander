import Foundation

// Encodable reply payloads (what `--json` prints). Field names are part of the automation
// contract — scripts and Alfred workflows read them — so change them deliberately.

enum BrowseAddress {
    /// Canonical address of a site: `ur-browse://<pot>/site/<id>`. The pot is always spelled
    /// out (even "default") so the address means the same thing from anywhere.
    static func site(pot: String, id: String) -> String {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return "ur-browse://\(pot)/site/\(escaped)"
    }
}

struct SiteInfo: Encodable, Equatable {
    let id: String
    let name: String
    let url: String
    let shortcut: Int?
    let temporary: Bool
    let open: Bool       // has a live session (web view) in this pot
    let active: Bool     // the session currently in front
    let address: String
}

struct CurrentInfo: Encodable, Equatable {
    let pot: String
    let site: String?    // id of the active site
    let name: String?
    let url: String?     // the page actually loaded, which may be deeper than the site's url
    let title: String?
    let visible: Bool
    let address: String?
}

struct PotInfo: Encodable {
    let pot: String
    let app: String
    let version: String
    let glaze: String?
    let visible: Bool
    let sites: Int
    let slip: [String]
    let config: String
}

struct SlipInfo: Encodable, Equatable {
    let file: String
    let name: String
    let kind: String
    let matches: [String]
    let excludes: [String]
    let runAt: String
    let allFrames: Bool
}
