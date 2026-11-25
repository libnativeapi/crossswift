import Foundation
#if os(Windows)
  import ucrt
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// Swift compiler plugin wire protocol (version 1) without external swift-syntax dependency:
// stdin/stdout carry [UInt64 little-endian byte length][UTF-8 JSON payload].

private func readExact(count: Int) -> Data? {
  guard count > 0 else { return Data() }
  var buffer = Data(count: count)
  var offset = 0
  let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
    guard let base = raw.baseAddress else { return false }
    while offset < count {
      #if os(Windows)
        let n = Int(_read(0, base.advanced(by: offset), UInt32(count - offset)))
      #else
        let n = read(0, base.advanced(by: offset), count - offset)
      #endif
      if n == 0 {
        return false
      }
      if n < 0 {
        #if !os(Windows)
          if errno == EINTR { continue }
        #endif
        return false
      }
      offset += n
    }
    return true
  }
  return ok ? buffer : nil
}

private func writeAll(_ data: Data) {
  var lengthLE = UInt64(data.count).littleEndian
  withUnsafeBytes(of: &lengthLE) { header in
    guard let base = header.baseAddress else { return }
    var written = 0
    while written < 8 {
      #if os(Windows)
        let n = Int(_write(1, base.advanced(by: written), UInt32(8 - written)))
      #else
        let n = write(1, base.advanced(by: written), 8 - written)
      #endif
      if n <= 0 { return }
      written += n
    }
  }
  data.withUnsafeBytes { body in
    guard let base = body.baseAddress else { return }
    var written = 0
    while written < data.count {
      #if os(Windows)
        let n = Int(_write(1, base.advanced(by: written), UInt32(data.count - written)))
      #else
        let n = write(1, base.advanced(by: written), data.count - written)
      #endif
      if n <= 0 { return }
      written += n
    }
  }
}

private struct ParsedEntryDecl {
  let rawName: String
  let identToken: String
  let typeAnnotation: String?
  let initializerExpr: String?
}

private func skipWhitespaceAndComments(_ chars: [Character], from start: Int) -> Int {
  var i = start
  let n = chars.count
  while i < n {
    let c = chars[i]
    if c.isWhitespace {
      i += 1
    } else if c == "/" && i + 1 < n && chars[i + 1] == "/" {
      i += 2
      while i < n && !chars[i].isNewline { i += 1 }
    } else if c == "/" && i + 1 < n && chars[i + 1] == "*" {
      i += 2
      var depth = 1
      while i < n && depth > 0 {
        if chars[i] == "/" && i + 1 < n && chars[i + 1] == "*" {
          depth += 1
          i += 2
        } else if chars[i] == "*" && i + 1 < n && chars[i + 1] == "/" {
          depth -= 1
          i += 2
        } else {
          i += 1
        }
      }
    } else {
      break
    }
  }
  return i
}

private func isIdentContinuation(_ c: Character) -> Bool {
  c == "_" || c.isLetter || c.isNumber
}

private func parseEntryDecl(_ source: String) -> ParsedEntryDecl? {
  let chars = Array(source)
  let n = chars.count
  var i = skipWhitespaceAndComments(chars, from: 0)

  // Skip leading attributes (@Entry, etc.) and declaration modifiers (public, internal, etc.)
  while i < n {
    i = skipWhitespaceAndComments(chars, from: i)
    if i >= n { break }
    if chars[i] == "@" {
      i += 1
      while i < n && (isIdentContinuation(chars[i]) || chars[i] == ".") { i += 1 }
      i = skipWhitespaceAndComments(chars, from: i)
      if i < n && chars[i] == "(" {
        var depth = 1
        i += 1
        while i < n && depth > 0 {
          if chars[i] == "(" { depth += 1 }
          else if chars[i] == ")" { depth -= 1 }
          i += 1
        }
      }
      continue
    }
    let wordStart = i
    while i < n && isIdentContinuation(chars[i]) { i += 1 }
    if i == wordStart { break }
    let word = String(chars[wordStart..<i])
    if word == "var" {
      i = skipWhitespaceAndComments(chars, from: i)
      guard i < n else { return nil }
      let rawName: String
      let identToken: String
      if chars[i] == "`" {
        let start = i
        i += 1
        let nameStart = i
        while i < n && chars[i] != "`" { i += 1 }
        rawName = String(chars[nameStart..<i])
        if i < n { i += 1 }
        identToken = String(chars[start..<i])
      } else {
        let nameStart = i
        while i < n && isIdentContinuation(chars[i]) { i += 1 }
        guard i > nameStart else { return nil }
        rawName = String(chars[nameStart..<i])
        identToken = rawName
      }

      // Scan remaining tokens at top level for `:` and `=`
      var paren = 0
      var bracket = 0
      var brace = 0
      var angle = 0
      var inString = false
      var colonIdx: Int? = nil
      var equalIdx: Int? = nil
      var j = i
      while j < n {
        let ch = chars[j]
        if inString {
          if ch == "\\" {
            j += 2
            continue
          }
          if ch == "\"" { inString = false }
          j += 1
          continue
        }
        if ch == "\"" {
          inString = true
          j += 1
          continue
        }
        if ch == "/" && j + 1 < n && chars[j + 1] == "/" {
          break
        }
        let atTop = paren == 0 && bracket == 0 && brace == 0 && angle == 0
        if atTop && colonIdx == nil && equalIdx == nil && ch == ":" {
          colonIdx = j
          j += 1
          continue
        }
        if atTop && equalIdx == nil && ch == "=" {
          equalIdx = j
          break
        }
        switch ch {
        case "(": paren += 1
        case ")": paren = max(0, paren - 1)
        case "[": bracket += 1
        case "]": bracket = max(0, bracket - 1)
        case "{": brace += 1
        case "}": brace = max(0, brace - 1)
        case "<": if colonIdx != nil && equalIdx == nil { angle += 1 }
        case ">": if angle > 0 { angle -= 1 }
        default: break
        }
        j += 1
      }

      let typeStr: String?
      if let cIdx = colonIdx {
        let endIdx = equalIdx ?? n
        let slice = String(chars[(cIdx + 1)..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        typeStr = slice.isEmpty ? nil : slice
      } else {
        typeStr = nil
      }

      let initStr: String?
      if let eIdx = equalIdx {
        let slice = String(chars[(eIdx + 1)..<n]).trimmingCharacters(in: .whitespacesAndNewlines)
        initStr = slice.isEmpty ? nil : slice
      } else {
        initStr = nil
      }

      return ParsedEntryDecl(
        rawName: rawName,
        identToken: identToken,
        typeAnnotation: typeStr,
        initializerExpr: initStr
      )
    }
    // Modifier with optional `(set)`
    i = skipWhitespaceAndComments(chars, from: i)
    if i < n && chars[i] == "(" {
      while i < n && chars[i] != ")" { i += 1 }
      if i < n { i += 1 }
    }
  }
  return nil
}

private func handleExpandAttachedMacro(_ req: [String: Any]) -> [String: Any] {
  let macroInfo = req["macro"] as? [String: Any]
  let typeName = macroInfo?["typeName"] as? String ?? ""
  if typeName == "PreviewableMacro" {
    return ["expandMacroResult": ["diagnostics": []]]
  }
  let role = req["macroRole"] as? String ?? ""
  let declSyntax = req["declSyntax"] as? [String: Any]
  let source = declSyntax?["source"] as? String ?? ""

  guard let parsed = parseEntryDecl(source) else {
    return ["expandMacroResult": ["diagnostics": []]]
  }

  if typeName == "EntryDefaultValueMacro" {
    if role == "accessor", let expr = parsed.initializerExpr {
      let expanded = "{\n  get {\n    \(expr)\n  }\n}"
      return ["expandMacroResult": ["expandedSource": expanded, "diagnostics": []]]
    }
    return ["expandMacroResult": ["diagnostics": []]]
  }

  if typeName == "EntryMacro" {
    let keyName = "__Key_\(parsed.rawName)"
    if role == "accessor" {
      let expanded = """
        {
          get { self[\(keyName).self] }
          set { self[\(keyName).self] = newValue }
        }
        """
      return ["expandMacroResult": ["expandedSource": expanded, "diagnostics": []]]
    }
    if role == "peer" {
      let expanded: String
      if let expr = parsed.initializerExpr {
        let typePart = parsed.typeAnnotation.map { ": \($0)" } ?? ""
        expanded = """
          private struct \(keyName): EnvironmentKey {
            @_EntryDefaultValue
            static var defaultValue\(typePart) = \(expr)
          }
          """
      } else if let typeAnn = parsed.typeAnnotation {
        expanded = """
          private struct \(keyName): EnvironmentKey {
            static var defaultValue: \(typeAnn) { nil }
          }
          """
      } else {
        return ["expandMacroResult": ["diagnostics": []]]
      }
      return ["expandMacroResult": ["expandedSource": expanded, "diagnostics": []]]
    }
  }

  return ["expandMacroResult": ["diagnostics": []]]
}

#if os(Windows)
  _ = _setmode(0, _O_BINARY)
  _ = _setmode(1, _O_BINARY)
#endif

while let header = readExact(count: 8) {
  let length = header.withUnsafeBytes { raw -> UInt64 in
    var val: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &val) { dst in
      raw.copyBytes(to: dst)
    }
    return UInt64(littleEndian: val)
  }
  guard let payload = readExact(count: Int(length)),
    let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
  else {
    break
  }

  let response: [String: Any]
  if json["getCapability"] != nil {
    response = ["getCapabilityResult": ["capability": ["protocolVersion": 1]]]
  } else if let expandReq = json["expandAttachedMacro"] as? [String: Any] {
    response = handleExpandAttachedMacro(expandReq)
  } else if json["expandFreestandingMacro"] != nil {
    response = ["expandMacroResult": ["expandedSource": "", "diagnostics": []]]
  } else {
    response = [:]
  }

  if let encoded = try? JSONSerialization.data(withJSONObject: response) {
    writeAll(encoded)
  }
}
