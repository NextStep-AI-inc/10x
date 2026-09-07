import XCTest
import ComputerKit

final class JSONValueTests: XCTestCase {
    func test_roundTrip_preservesStructure() throws {
        let value: JSONValue = .object([
            "name": .string("computer_act"),
            "ok": .bool(true),
            "n": .number(42),
            "nothing": .null,
            "list": .array([.number(1), .string("two")]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_accessors() {
        let value: JSONValue = .object(["x": .number(3)])
        XCTAssertEqual(value["x"]?.doubleValue, 3)
        XCTAssertNil(value["missing"])
        XCTAssertNil(JSONValue.string("s")["x"])
    }

    func test_wireDecode_separatesTypesAndGuardsInt() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"t":true,"zero":0,"one":1,"frac":1.5}"#.utf8))
        XCTAssertEqual(decoded["t"], .bool(true))
        XCTAssertEqual(decoded["zero"], .number(0))
        XCTAssertEqual(decoded["one"]?.intValue, 1)
        XCTAssertNil(decoded["frac"]?.intValue) // non-integer must not truncate
        XCTAssertEqual(decoded["frac"]?.doubleValue, 1.5)
        XCTAssertNil(decoded["t"]?.intValue) // bool is not an int
    }
}
