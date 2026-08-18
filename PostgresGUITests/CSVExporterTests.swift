//
//  CSVExporterTests.swift
//  PostgresGUITests
//
//  Unit tests for CSVExporter.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("CSVExporter")
struct CSVExporterTests {

    // MARK: - Basic Export Tests

    @Suite("Basic Export")
    struct BasicExportTests {

        @Test func returnsEmptyStringForEmptyRows() {
            let result = CSVExporter.toCSV(rows: [])
            #expect(result == "")
        }

        @Test func exportsHeaderRow() {
            let rows = [
                TableRow(values: ["name": "Alice", "age": "30"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "age"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.first == "name,age")
        }

        @Test func exportsDataRow() {
            let rows = [
                TableRow(values: ["name": "Alice", "age": "30"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "age"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.count == 2)
            #expect(lines[1] == "Alice,30")
        }

        @Test func exportsMultipleRows() {
            let rows = [
                TableRow(values: ["name": "Alice", "age": "30"]),
                TableRow(values: ["name": "Bob", "age": "25"]),
                TableRow(values: ["name": "Charlie", "age": "35"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "age"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.count == 4)
            #expect(lines[0] == "name,age")
            #expect(lines[1] == "Alice,30")
            #expect(lines[2] == "Bob,25")
            #expect(lines[3] == "Charlie,35")
        }

        @Test func usesSpecifiedColumnOrder() {
            let rows = [
                TableRow(values: ["b": "2", "a": "1", "c": "3"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["c", "a", "b"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[0] == "c,a,b")
            #expect(lines[1] == "3,1,2")
        }

        @Test func usesSortedColumnsWhenNotSpecified() {
            let rows = [
                TableRow(values: ["z": "3", "a": "1", "m": "2"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: nil)
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[0] == "a,m,z")
            #expect(lines[1] == "1,2,3")
        }
    }

    // MARK: - Null Handling Tests

    @Suite("Null Handling")
    struct NullHandlingTests {

        @Test func handlesNilValues() {
            let rows = [
                TableRow(values: ["name": "Alice", "email": nil])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "email"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "Alice,")
        }

        @Test func handlesMissingColumns() {
            let rows = [
                TableRow(values: ["name": "Alice"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "missing"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "Alice,")
        }

        @Test func handlesAllNilRow() {
            let rows = [
                TableRow(values: ["a": nil, "b": nil])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["a", "b"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == ",")
        }
    }

    // MARK: - RFC 4180 Compliance Tests

    @Suite("RFC 4180 Compliance")
    struct RFC4180ComplianceTests {

        @Test func escapesCommas() {
            let rows = [
                TableRow(values: ["address": "123 Main St, Apt 4"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["address"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "\"123 Main St, Apt 4\"")
        }

        @Test func escapesDoubleQuotes() {
            let rows = [
                TableRow(values: ["quote": "He said \"hello\""])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["quote"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "\"He said \"\"hello\"\"\"")
        }

        @Test func escapesNewlines() {
            let rows = [
                TableRow(values: ["text": "Line 1\nLine 2"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["text"])
            let lines = result.components(separatedBy: "\n")
            // Header + wrapped value spanning multiple lines
            #expect(lines[0] == "text")
            #expect(lines[1] == "\"Line 1")
            #expect(lines[2] == "Line 2\"")
        }

        @Test func escapesCarriageReturns() {
            let rows = [
                TableRow(values: ["text": "Line 1\rLine 2"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["text"])
            #expect(result.contains("\"Line 1\rLine 2\""))
        }

        @Test func escapesMultipleSpecialChars() {
            let rows = [
                TableRow(values: ["complex": "Hello, \"World\"\nNew line"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["complex"])
            #expect(result.contains("\"Hello, \"\"World\"\""))
        }

        @Test func doesNotEscapeRegularText() {
            let rows = [
                TableRow(values: ["name": "Alice"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "Alice")
        }

        @Test func escapesHeaderWithComma() {
            let rows = [
                TableRow(values: ["field,name": "value"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["field,name"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[0] == "\"field,name\"")
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func handlesEmptyStringValues() {
            let rows = [
                TableRow(values: ["name": "", "age": "30"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "age"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == ",30")
        }

        @Test func handlesSingleColumn() {
            let rows = [
                TableRow(values: ["id": "1"]),
                TableRow(values: ["id": "2"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["id"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[0] == "id")
            #expect(lines[1] == "1")
            #expect(lines[2] == "2")
        }

        @Test func handlesUnicodeCharacters() {
            let rows = [
                TableRow(values: ["name": "日本語", "emoji": "🎉"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "emoji"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "日本語,🎉")
        }

        @Test func handlesLongStrings() {
            let longString = String(repeating: "a", count: 10000)
            let rows = [
                TableRow(values: ["data": longString])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["data"])
            #expect(result.contains(longString))
        }

        @Test func handlesNumericStrings() {
            let rows = [
                TableRow(values: ["int": "42", "float": "3.14", "scientific": "1.23e-4"])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["int", "float", "scientific"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines[1] == "42,3.14,1.23e-4")
        }

        @Test func returnsEmptyForEmptyColumns() {
            let rows = [
                TableRow(values: [:])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: [])
            #expect(result == "")
        }
    }

    // MARK: - Selection Tests

    @Suite("Selection")
    struct SelectionTests {

        @Test func copiesOnlySelectedRowsInGivenOrder() {
            let grace = TableRow(values: ["name": "Grace", "age": "22"])
            let eve = TableRow(values: ["name": "Eve", "age": "29"])
            let alice = TableRow(values: ["name": "Alice", "age": "30"])
            let frank = TableRow(values: ["name": "Frank", "age": "38"])
            let bob = TableRow(values: ["name": "Bob", "age": "25"])
            let dave = TableRow(values: ["name": "Dave", "age": "45"])
            let carol = TableRow(values: ["name": "Carol", "age": "41"])

            // Rows arrive in display order (already sorted/filtered by the view),
            // and the selection is an unordered Set. 5 of the 7 rows are selected
            // (120 possible orderings of the selected IDs), with two unselected
            // rows interspersed (Grace at the start, Bob in the middle) — an
            // implementation that iterated the Set instead of filtering `rows`
            // would both include the unselected rows and get the order wrong
            // almost certainly, rather than by coincidence.
            let result = CSVExporter.csvForSelection(
                rows: [grace, eve, alice, frank, bob, dave, carol],
                selectedIDs: [eve.id, alice.id, frank.id, dave.id, carol.id],
                columns: ["name", "age"]
            )

            #expect(result == "name,age\nEve,29\nAlice,30\nFrank,38\nDave,45\nCarol,41")
        }

        @Test func returnsEmptyStringWhenNothingIsSelected() {
            let alice = TableRow(values: ["name": "Alice", "age": "30"])

            let result = CSVExporter.csvForSelection(
                rows: [alice],
                selectedIDs: [],
                columns: ["name", "age"]
            )

            #expect(result == "")
        }

        @Test func ignoresSelectedIDsForRowsNoLongerPresentInRows() {
            let alice = TableRow(values: ["name": "Alice", "age": "30"])
            let bob = TableRow(values: ["name": "Bob", "age": "25"])
            // Simulates a row the user selected before narrowing the search
            // filter — it's no longer in the displayed `rows` array, but its ID
            // is still in `selectedIDs` until the selection is explicitly cleared.
            let phantom = TableRow(values: ["name": "Phantom", "age": "99"])

            let result = CSVExporter.csvForSelection(
                rows: [alice, bob],
                selectedIDs: [alice.id, phantom.id, bob.id],
                columns: ["name", "age"]
            )

            #expect(result == "name,age\nAlice,30\nBob,25")
        }
    }

    // MARK: - Real-world Scenarios

    @Suite("Real-world Scenarios")
    struct RealWorldScenarios {

        @Test func exportsTypicalDatabaseTable() {
            let rows = [
                TableRow(values: [
                    "id": "1",
                    "name": "John Doe",
                    "email": "john@example.com",
                    "created_at": "2024-01-15 10:30:00"
                ]),
                TableRow(values: [
                    "id": "2",
                    "name": "Jane Smith",
                    "email": "jane@example.com",
                    "created_at": "2024-01-16 14:45:00"
                ])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["id", "name", "email", "created_at"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

            #expect(lines.count == 3)
            #expect(lines[0] == "id,name,email,created_at")
            #expect(lines[1] == "1,John Doe,john@example.com,2024-01-15 10:30:00")
            #expect(lines[2] == "2,Jane Smith,jane@example.com,2024-01-16 14:45:00")
        }

        @Test func exportsWithAddressContainingComma() {
            let rows = [
                TableRow(values: [
                    "name": "ACME Corp",
                    "address": "123 Business St, Suite 100, City, ST 12345"
                ])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["name", "address"])
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

            #expect(lines[0] == "name,address")
            #expect(lines[1] == "ACME Corp,\"123 Business St, Suite 100, City, ST 12345\"")
        }

        @Test func exportsJSONData() {
            let rows = [
                TableRow(values: [
                    "id": "1",
                    "config": "{\"key\": \"value\", \"nested\": {\"a\": 1}}"
                ])
            ]
            let result = CSVExporter.toCSV(rows: rows, columns: ["id", "config"])
            // JSON with commas and quotes should be properly escaped
            #expect(result.contains("\"\"key\"\""))
        }
    }
}
