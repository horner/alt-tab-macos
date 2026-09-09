import Foundation

enum Endpoints {
    static let domain = Bundle.main.object(forInfoDictionaryKey: "Domain") as! String
    static let apiDomain = Bundle.main.object(forInfoDictionaryKey: "ApiDomain") as! String
    static let website = "https://\(domain)"
    static let appcastUrl = "\(website)/appcast.xml"
    #if PROJECTS_DISTRIBUTION
    static let supportUrl = "https://github.com/horner/alt-tab-macos"
    #else
    static let supportUrl = "\(website)/support"
    #endif
    static let checkoutUrl = "\(website)/pricing"
    static let accountUrl = "\(website)/my-account"
    static let licenseApiBaseUrl = "https://\(apiDomain)/v1/license"
    static let feedbackUrl = "https://\(apiDomain)/v1/feedback"
}
