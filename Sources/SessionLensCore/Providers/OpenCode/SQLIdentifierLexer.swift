public enum SQLIdentifierLexer {
    public static func identifiers(in sql: String) -> Set<String> {
        var result = Set<String>()
        var current = ""
        var isInsideStringLiteral = false
        var index = sql.startIndex

        func recordCurrent() {
            guard !current.isEmpty else { return }
            result.insert(current)
            current.removeAll(keepingCapacity: true)
        }

        while index < sql.endIndex {
            let character = sql[index]

            if isInsideStringLiteral {
                if character == "'" {
                    let next = sql.index(after: index)
                    if next < sql.endIndex, sql[next] == "'" {
                        index = next
                    } else {
                        isInsideStringLiteral = false
                    }
                }
            } else if character == "'" {
                recordCurrent()
                isInsideStringLiteral = true
            } else if character.isLetter || character == "_"
                || (!current.isEmpty && character.isNumber)
            {
                current.append(contentsOf: character.lowercased())
            } else {
                recordCurrent()
            }

            index = sql.index(after: index)
        }

        recordCurrent()
        return result
    }
}
