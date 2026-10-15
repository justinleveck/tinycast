import Foundation

/// A typed term holding `*` or `?`, matched against the whole filename the way a shell glob is.
struct FileSearchPattern: Sendable, Equatable {
    let term: String
    let bytes: [UInt8]
    private let characters: [Character]

    init?(_ term: String) {
        guard term.contains(where: Self.isWildcard) else { return nil }
        self.term = term
        let folded = FileSearchQuery.fold(term)
        bytes = Array(folded.utf8)
        characters = Array(folded)
    }

    static func isWildcard(_ character: Character) -> Bool {
        character == "*" || character == "?"
    }

    /// Takes a name as `FileSearchQuery.score` holds it: raw ASCII, or already folded.
    func matches(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
        guard name.contains(where: { $0 >= 0x80 }) else {
            return Self.glob(bytes, matches: name, star: 0x2A, any: 0x3F) {
                $0 == FileSearchQuery.lower($1)
            }
        }
        // A `?` is one Character, so `中` or `👍🏽` cannot be walked byte by byte.
        let name = Array(String(decoding: name, as: UTF8.self))
        return Self.glob(characters, matches: name, star: "*", any: "?", ==)
    }

    private static func glob<Element: Equatable, Name: RandomAccessCollection<Element>>(
        _ glob: [Element], matches name: Name, star: Element, any: Element,
        _ same: (Element, Element) -> Bool
    ) -> Bool where Name.Index == Int {
        var globIndex = 0
        var nameIndex = name.startIndex
        var lastStar: (glob: Int, name: Int)?
        while nameIndex < name.endIndex {
            if globIndex < glob.count, glob[globIndex] == star {
                lastStar = (globIndex, nameIndex)
                globIndex += 1
            } else if globIndex < glob.count,
                glob[globIndex] == any || same(glob[globIndex], name[nameIndex])
            {
                globIndex += 1
                nameIndex += 1
            } else if let star = lastStar {
                lastStar = (star.glob, star.name + 1)
                globIndex = star.glob + 1
                nameIndex = star.name + 1
            } else {
                return false
            }
        }
        return glob[globIndex...].allSatisfy { $0 == star }
    }
}
