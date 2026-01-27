import Foundation

/// A curated blocklist source
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

/// Categories for organizing blocklists
public enum BlocklistCategory: String, CaseIterable, Sendable {
    case recommended = "Recommended"
    case adsTrackers = "Ads & Trackers"
    case malwareSecurity = "Malware & Security"
    case privacy = "Privacy"
    case socialMedia = "Social Media"
    case gambling = "Gambling"
    case fakeNews = "Fake News"
    case adult = "Adult Content"
    case annoyances = "Annoyances"
    case regional = "Regional"

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
        case .annoyances: return "bell.slash.fill"
        case .regional: return "globe"
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
        case .annoyances: return "cyan"
        case .regional: return "indigo"
        }
    }
}

/// Curated catalog of popular blocklists
public enum BlocklistCatalog {

    /// All available blocklists organized by category
    public static let all: [BlocklistSource] = [
        // MARK: - Recommended (Balanced defaults for most users)
        BlocklistSource(
            id: "steven-black-unified",
            name: "Steven Black Unified",
            description: "Comprehensive ad & malware blocking. Best for most users.",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
            category: .recommended,
            estimatedEntries: "170K",
            maintainer: "Steven Black",
            isRecommended: true
        ),
        BlocklistSource(
            id: "hagezi-light",
            name: "Hagezi Light",
            description: "Balanced blocking with minimal false positives",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/light.txt",
            category: .recommended,
            estimatedEntries: "70K",
            maintainer: "Hagezi",
            isRecommended: true
        ),
        BlocklistSource(
            id: "peter-lowe",
            name: "Peter Lowe's List",
            description: "Lightweight, well-maintained ad & tracker list",
            url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0",
            category: .recommended,
            estimatedEntries: "3K",
            maintainer: "Peter Lowe",
            isRecommended: true
        ),

        // MARK: - Ads & Trackers
        BlocklistSource(
            id: "adaway",
            name: "AdAway Default",
            description: "Popular Android ad blocking list, works everywhere",
            url: "https://adaway.org/hosts.txt",
            category: .adsTrackers,
            estimatedEntries: "6K",
            maintainer: "AdAway Team"
        ),
        BlocklistSource(
            id: "anudeep-ads",
            name: "anudeepND Ads",
            description: "Curated advertising domains, tested before adding",
            url: "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt",
            category: .adsTrackers,
            estimatedEntries: "45K",
            maintainer: "anudeepND"
        ),
        BlocklistSource(
            id: "easylist-hosts",
            name: "EasyList (Hosts)",
            description: "Classic EasyList converted to hosts format",
            url: "https://v.firebog.net/hosts/Easylist.txt",
            category: .adsTrackers,
            estimatedEntries: "25K",
            maintainer: "EasyList Team"
        ),
        BlocklistSource(
            id: "adguard-dns",
            name: "AdGuard DNS Filter",
            description: "AdGuard's DNS-level ad blocking list",
            url: "https://v.firebog.net/hosts/AdguardDNS.txt",
            category: .adsTrackers,
            estimatedEntries: "50K",
            maintainer: "AdGuard"
        ),
        BlocklistSource(
            id: "goodbye-ads",
            name: "GoodbyeAds",
            description: "Strict ad blocking, regularly updated",
            url: "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt",
            category: .adsTrackers,
            estimatedEntries: "200K",
            maintainer: "jerryn70"
        ),
        BlocklistSource(
            id: "notracking-ads",
            name: "NoTracking Ads",
            description: "Optimized ad blocking, auto-updated",
            url: "https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt",
            category: .adsTrackers,
            estimatedEntries: "100K",
            maintainer: "notracking"
        ),

        // MARK: - Malware & Security
        BlocklistSource(
            id: "malware-domains",
            name: "Malware Domain List",
            description: "Known malware distribution domains",
            url: "https://v.firebog.net/hosts/Prigent-Malware.txt",
            category: .malwareSecurity,
            estimatedEntries: "15K",
            maintainer: "Fabrice Prigent"
        ),
        BlocklistSource(
            id: "urlhaus",
            name: "URLhaus Malware",
            description: "Real-time malware URL blocking from abuse.ch",
            url: "https://urlhaus.abuse.ch/downloads/hostfile/",
            category: .malwareSecurity,
            estimatedEntries: "10K",
            maintainer: "abuse.ch"
        ),
        BlocklistSource(
            id: "phishing-army",
            name: "Phishing Army",
            description: "Phishing domains from multiple sources",
            url: "https://phishing.army/download/phishing_army_blocklist_extended.txt",
            category: .malwareSecurity,
            estimatedEntries: "90K",
            maintainer: "Phishing Army"
        ),
        BlocklistSource(
            id: "ransomware-tracker",
            name: "Ransomware Tracker",
            description: "Known ransomware C&C servers",
            url: "https://v.firebog.net/hosts/Prigent-Crypto.txt",
            category: .malwareSecurity,
            estimatedEntries: "5K",
            maintainer: "Fabrice Prigent"
        ),
        BlocklistSource(
            id: "someonewhocares",
            name: "Dan Pollock's List",
            description: "Classic hosts file, ads + malware + annoyances",
            url: "https://someonewhocares.org/hosts/hosts",
            category: .malwareSecurity,
            estimatedEntries: "15K",
            maintainer: "Dan Pollock"
        ),

        // MARK: - Privacy
        BlocklistSource(
            id: "easyprivacy",
            name: "EasyPrivacy (Hosts)",
            description: "Tracker blocking from EasyPrivacy list",
            url: "https://v.firebog.net/hosts/Easyprivacy.txt",
            category: .privacy,
            estimatedEntries: "20K",
            maintainer: "EasyList Team"
        ),
        BlocklistSource(
            id: "cname-cloaking",
            name: "CNAME Cloaking Block",
            description: "Blocks CNAME-cloaked trackers that bypass normal blocking",
            url: "https://raw.githubusercontent.com/nextdns/cname-cloaking-blocklist/master/domains",
            category: .privacy,
            estimatedEntries: "1K",
            maintainer: "NextDNS"
        ),
        BlocklistSource(
            id: "windows-telemetry",
            name: "Windows Telemetry",
            description: "Block Windows telemetry and tracking",
            url: "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt",
            category: .privacy,
            estimatedEntries: "400",
            maintainer: "CrazyMax"
        ),
        BlocklistSource(
            id: "smart-tv",
            name: "Smart TV Blocklist",
            description: "Block smart TV telemetry & ads",
            url: "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt",
            category: .privacy,
            estimatedEntries: "700",
            maintainer: "Perflyst"
        ),
        BlocklistSource(
            id: "anudeep-tracking",
            name: "anudeepND Tracking",
            description: "Comprehensive tracking domain list",
            url: "https://raw.githubusercontent.com/anudeepND/blacklist/master/CoinMiner.txt",
            category: .privacy,
            estimatedEntries: "3K",
            maintainer: "anudeepND"
        ),

        // MARK: - Social Media
        BlocklistSource(
            id: "steven-black-social",
            name: "Social Media Block",
            description: "Facebook, Twitter, Instagram, TikTok, etc.",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social/hosts",
            category: .socialMedia,
            estimatedEntries: "175K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "facebook-zero",
            name: "Facebook Zero",
            description: "Complete Facebook/Meta blocking",
            url: "https://raw.githubusercontent.com/jmdugan/blocklists/master/corporations/facebook/all",
            category: .socialMedia,
            estimatedEntries: "5K",
            maintainer: "jmdugan"
        ),
        BlocklistSource(
            id: "tiktok-block",
            name: "TikTok Block",
            description: "Block TikTok and ByteDance domains",
            url: "https://raw.githubusercontent.com/jmdugan/blocklists/master/corporations/tiktok/all",
            category: .socialMedia,
            estimatedEntries: "200",
            maintainer: "jmdugan"
        ),

        // MARK: - Gambling
        BlocklistSource(
            id: "steven-black-gambling",
            name: "Gambling Sites",
            description: "Block gambling and betting websites",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts",
            category: .gambling,
            estimatedEntries: "175K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "sinfonietta-gambling",
            name: "Sinfonietta Gambling",
            description: "Curated gambling domain list",
            url: "https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/gambling-hosts",
            category: .gambling,
            estimatedEntries: "3K",
            maintainer: "Sinfonietta"
        ),

        // MARK: - Fake News
        BlocklistSource(
            id: "steven-black-fakenews",
            name: "Fake News Sites",
            description: "Block known fake news and misinformation sources",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts",
            category: .fakeNews,
            estimatedEntries: "175K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "marktron-fakenews",
            name: "Fake News Extended",
            description: "Additional fake news sources",
            url: "https://raw.githubusercontent.com/marktron/fakenews/master/fakenews",
            category: .fakeNews,
            estimatedEntries: "2K",
            maintainer: "marktron"
        ),

        // MARK: - Adult Content
        BlocklistSource(
            id: "steven-black-porn",
            name: "Adult Content Block",
            description: "Block adult/NSFW websites",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts",
            category: .adult,
            estimatedEntries: "240K",
            maintainer: "Steven Black"
        ),
        BlocklistSource(
            id: "antiporn-hosts",
            name: "Anti-Porn HOSTS",
            description: "Comprehensive adult content blocking list",
            url: "https://raw.githubusercontent.com/4skinSkywalker/Anti-Porn-HOSTS-File/master/HOSTS.txt",
            category: .adult,
            estimatedEntries: "400K",
            maintainer: "4skinSkywalker"
        ),
        BlocklistSource(
            id: "sinfonietta-porn",
            name: "Sinfonietta Adult",
            description: "Curated adult domain list",
            url: "https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/pornography-hosts",
            category: .adult,
            estimatedEntries: "15K",
            maintainer: "Sinfonietta"
        ),

        // MARK: - Annoyances
        BlocklistSource(
            id: "fanboy-annoyances",
            name: "Fanboy Annoyances",
            description: "Cookie notices, social widgets, newsletter popups",
            url: "https://v.firebog.net/hosts/static/w3kbl.txt",
            category: .annoyances,
            estimatedEntries: "5K",
            maintainer: "Fanboy"
        ),
        BlocklistSource(
            id: "anudeep-coinminer",
            name: "Crypto Miners",
            description: "Block browser-based cryptocurrency miners",
            url: "https://raw.githubusercontent.com/anudeepND/blacklist/master/CoinMiner.txt",
            category: .annoyances,
            estimatedEntries: "3K",
            maintainer: "anudeepND"
        ),

        // MARK: - Regional
        BlocklistSource(
            id: "no-google",
            name: "No Google",
            description: "Block all Google services and tracking",
            url: "https://raw.githubusercontent.com/nickspaargaren/no-google/master/pihole-google.txt",
            category: .regional,
            estimatedEntries: "3K",
            maintainer: "nickspaargaren"
        ),
    ]

    /// Get sources by category
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
