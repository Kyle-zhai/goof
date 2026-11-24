import Foundation

/// FNV-1a. Swift's `Hasher` is seeded per launch; demo aliases and name colors
/// must stay the same across launches, so they use this instead.
enum StableHash {
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func hex(_ string: String, length: Int = 3) -> String {
        String(String(fnv1a(string), radix: 16).suffix(length))
    }
}

/// Livestream-style anonymous aliases: "Anon Tabby·3f2".
enum AnonymousAlias {
    /// Every alias starts with this.
    static let prefix = "Anon "
    static let animals = ["Tabby", "Shiba", "Otter", "Penguin", "Fox", "Panda", "Seal", "Hamster",
                          "Koala", "Sloth", "Hedgehog", "Raccoon", "Whale", "Octopus", "Parrot", "Alpaca"]

    /// Stable for one seed (for example account + room + day).
    static func make(seed: String) -> String {
        let hash = StableHash.fnv1a(seed)
        let animal = animals[Int(hash % UInt64(animals.count))]
        return "\(prefix)\(animal)·\(StableHash.hex(seed + "#"))"
    }

    static func isAlias(_ name: String) -> Bool { name.hasPrefix(prefix) }

    /// Profile names can't look like an alias.
    static func isReserved(_ name: String) -> Bool { name.lowercased().hasPrefix("anon") }
}
