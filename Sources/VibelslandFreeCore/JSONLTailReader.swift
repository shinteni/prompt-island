import Foundation

package enum JSONLTailReader {
    package static func readTailData(from url: URL, maxBytes: Int) throws -> (data: Data, startsAtBeginning: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let readBytes = UInt64(max(1, maxBytes))
        let offset = fileSize > readBytes ? fileSize - readBytes : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return (data, offset == 0)
    }

    package static func tailLines(from data: Data, startsAtBeginning: Bool) -> [Data] {
        var bytes = data
        if !startsAtBeginning {
            guard let firstNewline = bytes.firstIndex(where: { $0 == 10 || $0 == 13 }) else {
                return []
            }
            bytes.removeSubrange(bytes.startIndex...firstNewline)
            while let first = bytes.first, first == 10 || first == 13 {
                bytes.removeFirst()
            }
        }

        var lines: [Data] = []
        var lineStart = bytes.startIndex
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 10 || byte == 13 {
                if lineStart < index {
                    lines.append(bytes[lineStart..<index])
                }
                index = bytes.index(after: index)
                while index < bytes.endIndex, bytes[index] == 10 || bytes[index] == 13 {
                    index = bytes.index(after: index)
                }
                lineStart = index
            } else {
                index = bytes.index(after: index)
            }
        }

        if lineStart < bytes.endIndex {
            lines.append(bytes[lineStart..<bytes.endIndex])
        }
        return lines
    }
}
