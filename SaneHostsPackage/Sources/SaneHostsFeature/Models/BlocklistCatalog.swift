import Foundation

public struct BlocklistSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let url: URL
    public let category: BlocklistCategory
    public let estimatedEntries: String // "85K", "150K", etc.
    public let maintainer: String
    public let isRecommended: Bool

    public init(
        id: String,
        name: String,
        description: String,
        url: String,
        category: BlocklistCategory,
        estimatedEntries: String,
        maintainer: String,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        guard let parsedURL = URL(string: url) else {
            fatalError("Invalid blocklist URL for '\(name)': \(url)")
        }
        self.url = parsedURL
        self.category = category
        self.estimatedEntries = estimatedEntries
        self.maintainer = maintainer
        self.isRecommended = isRecommended
    }
}

public enum BlocklistCategory: String, CaseIterable, Sendable {
    case recommended = "Recommended"
    case adsTrackers = "Ads & Trackers"
    case malwareSecurity = "Malware & Security"
    case privacy = "Privacy"
    case socialMedia = "Social Media"
    case gambling = "Gambling"
    case fakeNews = "Fake News"
    case adult = "Adult Content"

    public var icon: String {
        switch self {
        case .recommended: return "star.fill"
        case .adsTrackers: return "eye.slash"
        case .malwareSecurity: return "shield.fill"
        case .privacy: return "hand.raised.fill"
        case .socialMedia: return "bubble.left.and.bubble.right.fill"
        case .gambling: return "dice.fill"
        case .fakeNews: return "newspaper.fill"
        case .adult: return "exclamationmark.triangle.fill"
        }
    }

    public var color: String {
        switch self {
        case .recommended: return "orange"
        case .adsTrackers: return "blue"
        case .malwareSecurity: return "red"
        case .privacy: return "mint"
        case .socialMedia: return "purple"
        case .gambling: return "yellow"
        case .fakeNews: return "pink"
        case .adult: return "gray"
        }
    }
}

public enum BlocklistCatalog {
    /// Every list is checked for liveness, size and freshness by
    /// scripts/check_blocklist_catalog.py. Keep lists updated within the last year.
    public static let all: [BlocklistSource] = [
        BlocklistSource(
            id: "steven-black-unified",
            name: "Steven Black Unified",
            description: "Ads and malware from several trusted sources. Best for most users.",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
            category: .recommended,
            estimatedEntries: "78K",
            maintainer: "Steven Black",
            isRecommended: true
        ),
        BlocklistSource(
            id: "hagezi-light",
            name: "Hagezi Light",
            description: "Ads, trackers and telemetry with very few false positives",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/light.txt",
            category: .recommended,
            estimatedEntries: "160K",
            maintainer: "Hagezi",
            isRecommended: true
        ),
        BlocklistSource(
            id: "peter-lowe",
            name: "Peter Lowe's List",
            description: "Small, long-running ad and tracker list",
            url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0",
            category: .recommended,
            estimatedEntries: "3.5K",
            maintainer: "Peter Lowe",
            isRecommended: true
        ),
        BlocklistSource(
            id: "adaway",
            name: "AdAway Default",
            description: "The AdAway app's ad list, works on any device",
            url: "https://adaway.org/hosts.txt",
            category: .adsTrackers,
            estimatedEntries: "6.5K",
            maintainer: "AdAway"
        ),
        BlocklistSource(
            id: "anudeep-ads",
            name: "anudeepND Ads",
            description: "Ad servers, each tested before it is added",
            url: "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt",
            category: .adsTrackers,
            estimatedEntries: "42K",
            maintainer: "anudeepND"
        ),
        BlocklistSource(
            id: "easylist-hosts",
            name: "EasyList (Hosts)",
            description: "EasyList ad rules converted to hosts format by Firebog",
            url: "https://v.firebog.net/hosts/Easylist.txt",
            category: .adsTrackers,
            estimatedEntries: "52K",
            maintainer: "EasyList via Firebog"
        ),
        BlocklistSource(
            id: "adguard-dns",
            name: "AdGuard DNS Filter",
            description: "AdGuard's DNS ad and tracker filter, converted by Firebog",
            url: "https://v.firebog.net/hosts/AdguardDNS.txt",
            category: .adsTrackers,
            estimatedEntries: "190K",
            maintainer: "AdGuard via Firebog"
        ),
        BlocklistSource(
            id: "hagezi-multi",
            name: "Hagezi Multi Normal",
            description: "Broad ads, trackers, telemetry and badware blocking",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/multi.txt",
            category: .adsTrackers,
            estimatedEntries: "430K",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "malware-domains",
            name: "UT1 Malware",
            description: "Malware sites from the University of Toulouse blacklist",
            url: "https://v.firebog.net/hosts/Prigent-Malware.txt",
            category: .malwareSecurity,
            estimatedEntries: "240K",
            maintainer: "Fabrice Prigent (UT1)"
        ),
        BlocklistSource(
            id: "urlhaus",
            name: "URLhaus Malware",
            description: "Active malware download sites reported to abuse.ch",
            url: "https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-hosts.txt",
            category: .malwareSecurity,
            estimatedEntries: "2K",
            maintainer: "abuse.ch / malware-filter"
        ),
        BlocklistSource(
            id: "phishing-army",
            name: "Phishing Army",
            description: "Phishing domains gathered from several feeds",
            url: "https://phishing.army/download/phishing_army_blocklist_extended.txt",
            category: .malwareSecurity,
            estimatedEntries: "145K",
            maintainer: "Phishing Army"
        ),
        BlocklistSource(
            id: "crypto-jacking",
            name: "UT1 Cryptojacking",
            description: "Sites that mine cryptocurrency in your browser",
            url: "https://v.firebog.net/hosts/Prigent-Crypto.txt",
            category: .malwareSecurity,
            estimatedEntries: "11K",
            maintainer: "Fabrice Prigent (UT1)"
        ),
        BlocklistSource(
            id: "someonewhocares",
            name: "Dan Pollock's List",
            description: "Classic hosts file: ads, trackers and malware",
            url: "https://someonewhocares.org/hosts/hosts",
            category: .malwareSecurity,
            estimatedEntries: "13K",
            maintainer: "Dan Pollock"
        ),
        BlocklistSource(
            id: "wally3k",
            name: "WaLLy3K Blocklist",
            description: "Hand-checked suspicious and malicious domains",
            url: "https://v.firebog.net/hosts/static/w3kbl.txt",
            category: .malwareSecurity,
            estimatedEntries: "350",
            maintainer: "WaLLy3K"
        ),
        BlocklistSource(
            id: "easyprivacy",
            name: "EasyPrivacy (Hosts)",
            description: "EasyPrivacy tracker rules converted to hosts format by Firebog",
            url: "https://v.firebog.net/hosts/Easyprivacy.txt",
            category: .privacy,
            estimatedEntries: "43K",
            maintainer: "EasyList via Firebog"
        ),
        BlocklistSource(
            id: "cname-cloaking",
            name: "CNAME Cloaking Trackers",
            description: "Tracker domains known for CNAME cloaking",
            url: "https://raw.githubusercontent.com/AdguardTeam/cname-trackers/master/data/combined_original_trackers_justdomains.txt",
            category: .privacy,
            estimatedEntries: "100",
            maintainer: "AdGuard"
        ),
        BlocklistSource(
            id: "windows-telemetry",
            name: "Windows & Office Telemetry",
            description: "Microsoft Windows and Office tracking",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/native.winoffice.txt",
            category: .privacy,
            estimatedEntries: "700",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "smart-tv",
            name: "Smart TV Blocklist",
            description: "Ads and tracking on smart TVs",
            url: "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt",
            category: .privacy,
            estimatedEntries: "500",
            maintainer: "Perflyst"
        ),
        BlocklistSource(
            id: "samsung-tracking",
            name: "Samsung Tracking",
            description: "Samsung phone and TV tracking",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/native.samsung.txt",
            category: .privacy,
            estimatedEntries: "270",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "lg-webos-tracking",
            name: "LG webOS Tracking",
            description: "LG smart TV tracking and ads",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/native.lgwebos.txt",
            category: .privacy,
            estimatedEntries: "2K",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "amazon-tracking",
            name: "Amazon Device Tracking",
            description: "Amazon Echo, Fire TV and Kindle tracking",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/native.amazon.txt",
            category: .privacy,
            estimatedEntries: "740",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "no-google",
            name: "No Google",
            description: "Google services, ads and tracking. Breaks Google sites.",
            url: "https://raw.githubusercontent.com/nickspaargaren/no-google/master/pihole-google.txt",
            category: .privacy,
            estimatedEntries: "6.8K",
            maintainer: "nickspaargaren"
        ),
        BlocklistSource(
            id: "steven-black-social",
            name: "Social Media Block",
            description: "Steven Black Unified plus Facebook, Instagram, TikTok, X and more",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social/hosts",
            category: .socialMedia,
            estimatedEntries: "82K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "tiktok-block",
            name: "TikTok Block",
            description: "TikTok and ByteDance domains",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/main/hosts/native.tiktok.txt",
            category: .socialMedia,
            estimatedEntries: "550",
            maintainer: "Hagezi"
        ),
        BlocklistSource(
            id: "steven-black-gambling",
            name: "Gambling Sites",
            description: "Steven Black Unified plus gambling and betting sites",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts",
            category: .gambling,
            estimatedEntries: "85K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "sinfonietta-gambling",
            name: "Sinfonietta Gambling",
            description: "Hand-curated gambling sites",
            url: "https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/gambling-hosts",
            category: .gambling,
            estimatedEntries: "2.7K",
            maintainer: "Sinfonietta"
        ),
        BlocklistSource(
            id: "steven-black-fakenews",
            name: "Fake News Sites",
            description: "Steven Black Unified plus known fake news sites",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts",
            category: .fakeNews,
            estimatedEntries: "81K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "steven-black-porn",
            name: "Adult Content Block",
            description: "Steven Black Unified plus adult sites",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts",
            category: .adult,
            estimatedEntries: "155K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "antiporn-hosts",
            name: "Anti-Porn HOSTS",
            description: "Large adult-site list",
            url: "https://raw.githubusercontent.com/4skinSkywalker/Anti-Porn-HOSTS-File/master/HOSTS.txt",
            category: .adult,
            estimatedEntries: "70K",
            maintainer: "4skinSkywalker"
        ),
        BlocklistSource(
            id: "sinfonietta-porn",
            name: "Sinfonietta Adult",
            description: "Hand-curated adult sites",
            url: "https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/pornography-hosts",
            category: .adult,
            estimatedEntries: "61K",
            maintainer: "Sinfonietta"
        )
    ]

    public static func sources(for category: BlocklistCategory) -> [BlocklistSource] {
        all.filter { $0.category == category }
    }

    /// Get recommended sources (pre-selected for new users)
    public static var recommended: [BlocklistSource] {
        all.filter { $0.isRecommended }
    }

    /// Get all categories that have at least one source
    public static var availableCategories: [BlocklistCategory] {
        let categoriesWithSources = Set(all.map { $0.category })
        return BlocklistCategory.allCases.filter { categoriesWithSources.contains($0) }
    }
}
