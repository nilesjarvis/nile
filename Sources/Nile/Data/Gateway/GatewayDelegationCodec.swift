import Foundation

func delegationCleanString(_ value: JSONValue?) -> String? {
    guard let string = value?.stringValue else {
        return nil
    }
    let clean = string.strippingANSI()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
}

func delegationCleanStrings(_ value: JSONValue?) -> [String] {
    value?.arrayValue?.compactMap(delegationCleanString) ?? []
}

func delegationOptionalNonNegativeInt(_ value: JSONValue?) -> Int? {
    guard case let .number(number)? = value,
          number.isFinite,
          number >= 0,
          number.rounded(.towardZero) == number,
          number <= Double(Int.max) else {
        return nil
    }
    return Int(number)
}

func delegationOptionalFiniteNonNegativeDouble(
    _ value: JSONValue?
) -> Double? {
    guard case let .number(number)? = value,
          number.isFinite,
          number >= 0 else {
        return nil
    }
    return number
}

func delegationRequireBool(
    _ object: JSONValue.Object,
    method: String,
    name: String
) throws -> Bool {
    guard case let .bool(value)? = object[name] else {
        throw delegationMalformed(
            method,
            "\(name) was missing or not true or false"
        )
    }
    return value
}

func delegationRequireNonNegativeInt(
    _ object: JSONValue.Object,
    method: String,
    name: String
) throws -> Int {
    guard let value = delegationOptionalNonNegativeInt(object[name]) else {
        throw delegationMalformed(
            method,
            "\(name) was missing or not a nonnegative integer"
        )
    }
    return value
}

func delegationRequireString(
    _ object: JSONValue.Object,
    method: String,
    name: String,
    allowBlank: Bool
) throws -> String {
    guard let value = object[name]?.stringValue else {
        throw delegationMalformed(
            method,
            "\(name) was missing or not a string"
        )
    }
    guard allowBlank || !value.isBlank else {
        throw delegationMalformed(method, "\(name) was blank")
    }
    return value
}

func delegationRequireCleanString(
    _ object: JSONValue.Object,
    method: String,
    name: String
) throws -> String {
    guard let value = delegationCleanString(object[name]) else {
        throw delegationMalformed(method, "\(name) was missing or blank")
    }
    return value
}

func delegationOptionalTimestamp(
    _ object: JSONValue.Object,
    method: String,
    name: String
) throws -> Double? {
    guard let value = object[name], value != .null else {
        return nil
    }
    guard let timestamp = delegationOptionalFiniteNonNegativeDouble(value) else {
        throw delegationMalformed(
            method,
            "\(name) was not a finite nonnegative number"
        )
    }
    return timestamp
}

func delegationRequireTimestamp(
    _ object: JSONValue.Object,
    method: String,
    name: String
) throws -> Double {
    guard let value = delegationOptionalFiniteNonNegativeDouble(object[name]) else {
        throw delegationMalformed(
            method,
            "\(name) was missing or not a finite nonnegative number"
        )
    }
    return value
}

func delegationMalformed(
    _ method: String,
    _ detail: String
) -> HermesError {
    HermesError(
        "Malformed response to \(method): \(detail)",
        retryable: false
    )
}

func delegationRequireNonBlankInput(
    method: String,
    name: String,
    value: String
) throws -> String {
    let clean = value.strippingANSI()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
        throw HermesError(
            "\(method) requires a nonblank \(name)",
            retryable: false
        )
    }
    return clean
}

func delegationRequireNonNegativeInput(
    method: String,
    name: String,
    value: Int
) throws {
    guard value >= 0 else {
        throw HermesError(
            "\(method) requires nonnegative \(name)",
            retryable: false
        )
    }
}

func delegationRequireFiniteNonNegativeInput(
    method: String,
    name: String,
    value: Double
) throws {
    guard value.isFinite, value >= 0 else {
        throw HermesError(
            "\(method) requires a finite nonnegative \(name)",
            retryable: false
        )
    }
}

func delegationPutString(
    _ object: inout JSONValue.Object,
    name: String,
    value: String?
) {
    guard let clean = delegationCleanString(value.map(JSONValue.string)) else {
        return
    }
    object[name] = .string(clean)
}

func delegationPutStrings(
    _ object: inout JSONValue.Object,
    name: String,
    values: [String]
) {
    let clean = values.compactMap {
        delegationCleanString(.string($0))
    }
    if !clean.isEmpty {
        object[name] = .array(clean.map(JSONValue.string))
    }
}

func delegationPutNonNegativeInt(
    _ object: inout JSONValue.Object,
    name: String,
    value: Int?
) throws {
    guard let value else {
        return
    }
    try delegationRequireNonNegativeInput(
        method: "spawn_tree.save",
        name: name,
        value: value
    )
    object[name] = .number(Double(value))
}

func delegationPutFiniteNonNegativeDouble(
    _ object: inout JSONValue.Object,
    name: String,
    value: Double?
) throws {
    guard let value else {
        return
    }
    try delegationRequireFiniteNonNegativeInput(
        method: "spawn_tree.save",
        name: name,
        value: value
    )
    object[name] = .number(value)
}
