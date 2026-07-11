import Foundation

/// Docker-style "adjective_noun" names for first launch, so nobody shows up
/// as a generic "iPhone".
enum NameGenerator {
    private static let adjectives = [
        "brave", "sunny", "fuzzy", "swift", "cosmic", "mellow", "dizzy", "neon",
        "wild", "sleepy", "funky", "shiny", "sassy", "groovy", "spicy", "chill",
        "lucky", "rowdy", "dreamy", "sparkly", "loud", "smooth", "electric", "golden",
        "misty", "bouncy", "crispy", "velvet", "turbo", "cozy", "feral", "glowing",
    ]
    private static let nouns = [
        "otter", "falcon", "panda", "tiger", "walrus", "gecko", "badger", "koala",
        "raven", "dolphin", "llama", "fox", "moose", "hedgehog", "lynx", "puffin",
        "narwhal", "wombat", "ferret", "ibex", "heron", "beaver", "marmot", "toucan",
        "yak", "quokka", "manatee", "ocelot", "pelican", "stoat", "capybara", "bison",
    ]

    static func random() -> String {
        "\(adjectives.randomElement()!)_\(nouns.randomElement()!)"
    }
}
