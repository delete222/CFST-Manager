import Foundation

public enum CSVParser {
    public static func parseSpeedTestResults(csvText: String) throws -> [SpeedTestResult] {
        let rows = parseRows(csvText)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard let header = rows.first else {
            return []
        }

        let headerMap = Dictionary(uniqueKeysWithValues: header.enumerated().map { index, name in
            (name.normalizedCSVHeaderName, index)
        })

        func index(_ name: String) throws -> Int {
            guard let value = headerMap[name] else {
                throw CFSTError.missingColumn(name)
            }
            return value
        }

        func optionalIndex(_ names: [String]) -> Int? {
            for name in names {
                if let value = headerMap[name] {
                    return value
                }
            }
            return nil
        }

        let ipIndex = try index("IP 地址")
        let sentIndex = try index("已发送")
        let receivedIndex = try index("已接收")
        let lossIndex = try index("丢包率")
        let latencyIndex = try index("平均延迟")
        let speedIndex = try optionalIndex(["下载速度(MB/s)", "下载速度 (MB/s)", "下载速度"])
            ?? index("下载速度(MB/s)")
        let coloIndex = optionalIndex(["地区码", "数据中心", "区域"])

        return try rows.dropFirst().enumerated().compactMap { rowNumber, row in
            let requiredMaxIndex = [ipIndex, sentIndex, receivedIndex, lossIndex, latencyIndex, speedIndex].max() ?? 0
            guard row.count > requiredMaxIndex else {
                throw CFSTError.invalidCSV("第 \(rowNumber + 2) 行列数不足")
            }

            let ip = row[ipIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard IPAddress.recordType(for: ip) != nil else {
                throw CFSTError.invalidIPAddress(ip)
            }

            return SpeedTestResult(
                ipAddress: ip,
                sent: Int(row[sentIndex].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                received: Int(row[receivedIndex].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                lossRate: parseDouble(row[lossIndex]),
                averageLatency: parseDouble(row[latencyIndex]),
                downloadSpeed: parseDouble(row[speedIndex]),
                colo: value(at: coloIndex, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "N/A",
                selected: true
            )
        }
    }

    public static func parseSpeedTestResults(fileURL: URL) throws -> [SpeedTestResult] {
        let data = try Data(contentsOf: fileURL)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .gb18030)
            ?? String(data: data, encoding: .shiftJIS)
            ?? ""
        return try parseSpeedTestResults(csvText: text)
    }

    private static func parseDouble(_ value: String) -> Double {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        return Double(trimmed) ?? 0
    }

    private static func value(at index: Int?, in row: [String]) -> String? {
        guard let index, row.indices.contains(index) else {
            return nil
        }
        return row[index]
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if isQuoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            isQuoted = false
                            if next == "," {
                                row.append(field)
                                field = ""
                            } else if next == "\n" {
                                row.append(field)
                                rows.append(row)
                                row = []
                                field = ""
                            } else if next == "\r" {
                                row.append(field)
                                rows.append(row)
                                row = []
                                field = ""
                                _ = iterator.next()
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isQuoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                    _ = iterator.next()
                default:
                    field.append(character)
                }
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedCSVHeaderName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
    }
}

private extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
