import Foundation

nonisolated enum JEFITExportError: LocalizedError, Equatable {
    case notAJEFITExport
    var errorDescription: String? { "This file is not a JEFIT export: it has no ### sections." }
}

/// A JEFIT CSV export split into named tables (docs/JEFIT_EXPORT.md). Mirrors
/// tools/jefit_parse.py, so the Python reference and the app read the same rows.
nonisolated struct JEFITExport {
    struct Table: Equatable {
        let header: [String]
        var rows: [[String: String]]
    }

    /// Section name ("EXERCISE LOGS") to its tables, in order of first appearance.
    let sections: [String: [Table]]

    init(data: Data) throws {
        var sections: [String: [Table]] = [:]
        var current: String?
        var header: [String]?
        for record in Self.records(in: data) {
            if record.count == 1, let name = Self.sectionName(record[0]) {
                current = name
                sections[name, default: []] = sections[name] ?? []
                header = nil
                continue
            }
            if record.count == 1, !record[0].isEmpty, record[0].allSatisfy({ $0 == "#" }) {
                current = nil
                header = nil
                continue
            }
            guard let section = current else { continue }
            if record.count == 1, record[0].isEmpty {
                header = nil  // a block break: the next record is a header
                continue
            }
            guard let columns = header else {
                header = record
                if !sections[section, default: []].contains(where: { $0.header == record }) {
                    sections[section, default: []].append(Table(header: record, rows: []))
                }
                continue
            }
            var row: [String: String] = [:]
            for (i, column) in columns.enumerated() {
                row[column] = i < record.count ? record[i] : ""
            }
            // ROUTINES repeats its header before every row: identical headers share a table.
            let index = sections[section]!.firstIndex { $0.header == columns }!
            sections[section]![index].rows.append(row)
        }
        guard !sections.isEmpty else { throw JEFITExportError.notAJEFITExport }
        self.sections = sections
    }

    /// The rows of the first table in `section` whose header contains `column`; [] if none.
    func rows(_ section: String, withColumn column: String) -> [[String: String]] {
        sections[section]?.first { $0.header.contains(column) }?.rows ?? []
    }

    private static func sectionName(_ field: String) -> String? {
        guard field.hasPrefix("### "), field.hasSuffix("#") else { return nil }
        let body = field.dropFirst(4)
        guard let end = body.lastIndex(where: { $0 != "#" }) else { return nil }
        let name = body[...end].trimmingCharacters(in: .whitespaces)
        // The name must be followed by at least one space and the run of #s.
        guard !name.isEmpty, body[body.index(after: end)...].allSatisfy({ $0 == "#" }),
              body[end] == " " else { return nil }
        return name
    }

    /// RFC 4180 over the whole file: quoted fields may hold commas, newlines and "" quotes,
    /// which notes and day names do. Splitting into lines first would cut them in half.
    static func records(in data: Data) -> [[String]] {
        let quote = UInt8(ascii: "\""), comma = UInt8(ascii: ","), lf = UInt8(ascii: "\n"), cr = UInt8(ascii: "\r")
        var records: [[String]] = []
        var fields: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        let bytes = [UInt8](data)
        let end = bytes.count
        var i = 0

        func endField() {
            fields.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }
        func endRecord() {
            endField()
            records.append(fields)
            fields.removeAll(keepingCapacity: true)
        }

        while i < end {
            let b = bytes[i]
            if inQuotes {
                if b == quote {
                    if i + 1 < end, bytes[i + 1] == quote {
                        field.append(quote)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(b)
                }
            } else if b == quote {
                inQuotes = true
            } else if b == comma {
                endField()
            } else if b == lf {
                endRecord()
            } else if b != cr {
                field.append(b)
            }
            i += 1
        }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }
}
