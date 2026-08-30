import CoreFoundation
import Foundation

enum JSONValue: Equatable, Sendable {
    typealias Object = [String: JSONValue]

    case object(Object)
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(any value: Any) throws {
        switch value {
        case let object as [String: Any]:
            self = .object(try object.mapValues(JSONValue.init(any:)))
        case let array as [Any]:
            self = .array(try array.map(JSONValue.init(any:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            throw JSONValueError.unsupportedValue
        }
    }

    var foundationValue: Any {
        switch self {
        case let .object(object):
            object.mapValues(\.foundationValue)
        case let .array(array):
            array.map(\.foundationValue)
        case let .string(string):
            string
        case let .number(number):
            number
        case let .bool(bool):
            bool
        case .null:
            NSNull()
        }
    }

    var objectValue: Object? {
        guard case let .object(object) = self else {
            return nil
        }
        return object
    }

    var stringValue: String? {
        guard case let .string(string) = self else {
            return nil
        }
        return string
    }

    var integralInt64Value: Int64? {
        guard case let .number(number) = self, number.isFinite else {
            return nil
        }
        let rounded = number.rounded(.towardZero)
        guard
            rounded == number,
            number >= Double(Int64.min),
            number < Double(Int64.max)
        else {
            return nil
        }
        return Int64(number)
    }
}

enum JSONValueError: Error {
    case unsupportedValue
}
