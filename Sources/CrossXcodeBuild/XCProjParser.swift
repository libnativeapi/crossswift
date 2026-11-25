import Foundation

public enum XCProjParserError: Error, LocalizedError {
  case unexpectedEndOfInput
  case unexpectedCharacter(Character, offset: Int)
  case expectedToken(String, offset: Int)
  case invalidEscapeSequence(offset: Int)
  case invalidNumber(String, offset: Int)
  case invalidUTF8

  public var errorDescription: String? {
    switch self {
    case .unexpectedEndOfInput:
      return "Unexpected end of project.xcproj"
    case .unexpectedCharacter(let ch, let offset):
      return "Unexpected character '\(ch)' at offset \(offset) in project.xcproj"
    case .expectedToken(let expected, let offset):
      return "Expected '\(expected)' at offset \(offset) in project.xcproj"
    case .invalidEscapeSequence(let offset):
      return "Invalid string escape sequence at offset \(offset) in project.xcproj"
    case .invalidNumber(let raw, let offset):
      return "Invalid number '\(raw)' at offset \(offset) in project.xcproj"
    case .invalidUTF8:
      return "project.xcproj is not valid UTF-8 text"
    }
  }
}

/// Pure-Swift recursive-descent parser for Xcode 27 `project.xcproj` files.
///
/// `project.xcproj` uses JSON with trailing commas in objects and arrays
/// (JSON5/JSONC-style). This parser handles standard JSON values plus trailing
/// commas, `//` line comments, `/* ... */` block comments, and UTF-8 BOMs.
public struct XCProjParser {
  private let scalars: [UnicodeScalar]
  private var index: Int = 0

  public static func parse(fileAt url: URL) throws -> Any {
    let data = try Data(contentsOf: url)
    return try parse(data: data)
  }

  public static func parse(data: Data) throws -> Any {
    guard let text = String(data: data, encoding: .utf8) else {
      throw XCProjParserError.invalidUTF8
    }
    return try parse(string: text)
  }

  public static func parse(string: String) throws -> Any {
    let trimmed: Substring
    if string.unicodeScalars.first == "\u{FEFF}" {
      trimmed = string.dropFirst()
    } else {
      trimmed = string[...]
    }
    var parser = XCProjParser(text: String(trimmed))
    let value = try parser.parseValue()
    parser.skipWhitespaceAndComments()
    if let trailing = parser.peek() {
      throw XCProjParserError.unexpectedCharacter(Character(trailing), offset: parser.index)
    }
    return value
  }

  private init(text: String) {
    self.scalars = Array(text.unicodeScalars)
  }

  private var isAtEnd: Bool { index >= scalars.count }

  private func peek(_ offset: Int = 0) -> UnicodeScalar? {
    let pos = index + offset
    return pos < scalars.count ? scalars[pos] : nil
  }

  @discardableResult
  private mutating func advance() -> UnicodeScalar {
    let s = scalars[index]
    index += 1
    return s
  }

  private mutating func skipWhitespaceAndComments() {
    while !isAtEnd {
      let s = scalars[index]
      if s == " " || s == "\t" || s == "\r" || s == "\n" {
        index += 1
        continue
      }
      if s == "/" && peek(1) == "/" {
        index += 2
        while !isAtEnd && scalars[index] != "\n" {
          index += 1
        }
        continue
      }
      if s == "/" && peek(1) == "*" {
        index += 2
        while !isAtEnd {
          if scalars[index] == "*" && peek(1) == "/" {
            index += 2
            break
          }
          index += 1
        }
        continue
      }
      break
    }
  }

  private mutating func parseValue() throws -> Any {
    skipWhitespaceAndComments()
    guard let ch = peek() else {
      throw XCProjParserError.unexpectedEndOfInput
    }
    switch ch {
    case "{":
      return try parseObject()
    case "[":
      return try parseArray()
    case "\"":
      return try parseString()
    case "t":
      try expectLiteral("true")
      return true
    case "f":
      try expectLiteral("false")
      return false
    case "n":
      try expectLiteral("null")
      return NSNull()
    case "-", "0"..."9":
      return try parseNumber()
    default:
      throw XCProjParserError.unexpectedCharacter(Character(ch), offset: index)
    }
  }

  private mutating func parseObject() throws -> [String: Any] {
    _ = advance() // '{'
    var dict: [String: Any] = [:]
    while true {
      skipWhitespaceAndComments()
      guard let ch = peek() else {
        throw XCProjParserError.unexpectedEndOfInput
      }
      if ch == "}" {
        _ = advance()
        return dict
      }
      guard ch == "\"" else {
        throw XCProjParserError.expectedToken("\"", offset: index)
      }
      let key = try parseString()
      skipWhitespaceAndComments()
      guard peek() == ":" else {
        throw XCProjParserError.expectedToken(":", offset: index)
      }
      _ = advance()
      let value = try parseValue()
      dict[key] = value
      skipWhitespaceAndComments()
      if peek() == "," {
        _ = advance()
        // Allow trailing comma before '}'
        continue
      }
      if peek() == "}" {
        _ = advance()
        return dict
      }
      throw XCProjParserError.expectedToken(", or }", offset: index)
    }
  }

  private mutating func parseArray() throws -> [Any] {
    _ = advance() // '['
    var items: [Any] = []
    while true {
      skipWhitespaceAndComments()
      guard let ch = peek() else {
        throw XCProjParserError.unexpectedEndOfInput
      }
      if ch == "]" {
        _ = advance()
        return items
      }
      let value = try parseValue()
      items.append(value)
      skipWhitespaceAndComments()
      if peek() == "," {
        _ = advance()
        // Allow trailing comma before ']'
        continue
      }
      if peek() == "]" {
        _ = advance()
        return items
      }
      throw XCProjParserError.expectedToken(", or ]", offset: index)
    }
  }

  private mutating func parseString() throws -> String {
    _ = advance() // '"'
    var out = ""
    while !isAtEnd {
      let ch = advance()
      if ch == "\"" {
        return out
      }
      if ch != "\\" {
        out.append(Character(ch))
        continue
      }
      let escOffset = index
      guard !isAtEnd else {
        throw XCProjParserError.unexpectedEndOfInput
      }
      let esc = advance()
      switch esc {
      case "\"": out.append("\"")
      case "\\": out.append("\\")
      case "/": out.append("/")
      case "b": out.append("\u{08}")
      case "f": out.append("\u{0C}")
      case "n": out.append("\n")
      case "r": out.append("\r")
      case "t": out.append("\t")
      case "u":
        let codeUnit = try parseHex4(offset: escOffset)
        if codeUnit >= 0xD800 && codeUnit <= 0xDBFF {
          // UTF-16 high surrogate; expect trailing \uXXXX low surrogate
          guard peek() == "\\", peek(1) == "u" else {
            throw XCProjParserError.invalidEscapeSequence(offset: escOffset)
          }
          _ = advance()
          _ = advance()
          let low = try parseHex4(offset: index)
          guard low >= 0xDC00 && low <= 0xDFFF else {
            throw XCProjParserError.invalidEscapeSequence(offset: escOffset)
          }
          let combined = 0x10000 + ((UInt32(codeUnit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
          guard let scalar = UnicodeScalar(combined) else {
            throw XCProjParserError.invalidEscapeSequence(offset: escOffset)
          }
          out.append(Character(scalar))
        } else {
          guard let scalar = UnicodeScalar(codeUnit) else {
            throw XCProjParserError.invalidEscapeSequence(offset: escOffset)
          }
          out.append(Character(scalar))
        }
      default:
        throw XCProjParserError.invalidEscapeSequence(offset: escOffset)
      }
    }
    throw XCProjParserError.unexpectedEndOfInput
  }

  private mutating func parseHex4(offset: Int) throws -> UInt16 {
    var digits = ""
    for _ in 0..<4 {
      guard let s = peek(), isHexDigit(s) else {
        throw XCProjParserError.invalidEscapeSequence(offset: offset)
      }
      digits.append(Character(advance()))
    }
    guard let value = UInt16(digits, radix: 16) else {
      throw XCProjParserError.invalidEscapeSequence(offset: offset)
    }
    return value
  }

  private mutating func parseNumber() throws -> Any {
    let startOffset = index
    var raw = ""
    var isFloat = false
    if peek() == "-" {
      raw.append(Character(advance()))
    }
    while let ch = peek(), ch >= "0" && ch <= "9" {
      raw.append(Character(advance()))
    }
    if peek() == "." {
      isFloat = true
      raw.append(Character(advance()))
      while let ch = peek(), ch >= "0" && ch <= "9" {
        raw.append(Character(advance()))
      }
    }
    if let ch = peek(), ch == "e" || ch == "E" {
      isFloat = true
      raw.append(Character(advance()))
      if let sign = peek(), sign == "+" || sign == "-" {
        raw.append(Character(advance()))
      }
      while let ch = peek(), ch >= "0" && ch <= "9" {
        raw.append(Character(advance()))
      }
    }
    if isFloat {
      guard let d = Double(raw) else {
        throw XCProjParserError.invalidNumber(raw, offset: startOffset)
      }
      return d
    } else {
      guard let i = Int64(raw) else {
        if let d = Double(raw) { return d }
        throw XCProjParserError.invalidNumber(raw, offset: startOffset)
      }
      return Int(i)
    }
  }

  private mutating func expectLiteral(_ literal: String) throws {
    let startOffset = index
    for expected in literal.unicodeScalars {
      guard let actual = peek(), actual == expected else {
        throw XCProjParserError.expectedToken(literal, offset: startOffset)
      }
      _ = advance()
    }
  }

  private func isHexDigit(_ s: UnicodeScalar) -> Bool {
    (s >= "0" && s <= "9") || (s >= "a" && s <= "f") || (s >= "A" && s <= "F")
  }
}
