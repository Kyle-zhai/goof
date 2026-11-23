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

/// Livestream-style anonymous aliases: "匿名 · 橘猫·3f2".
enum AnonymousAlias {
    static let animals = ["橘猫", "柴犬", "水獭", "企鹅", "狐狸", "熊猫", "海豹", "仓鼠",
                          "考拉", "树懒", "刺猬", "浣熊", "鲸鱼", "章鱼", "鹦鹉", "羊驼"]

    /// Stable for one seed (for example account + room + day).
    static func make(seed: String) -> String {
        let hash = StableHash.fnv1a(seed)
        let animal = animals[Int(hash % UInt64(animals.count))]
        return "匿名 · \(animal)·\(StableHash.hex(seed + "#"))"
    }
}
