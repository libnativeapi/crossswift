import Foundation

/// Parses Xcode `.xcstrings` JSON catalogs at runtime so `String(localized:)`,
/// `LocalizedStringResource`, and `Text("literal")` resolve translations and
/// plural variations on Windows and Linux with zero build-time asset compilation.
public final class XCStringsCatalog: @unchecked Sendable {
  public static let shared = XCStringsCatalog()

  private let lock = NSLock()
  private var sourceLanguage: String = "en"
  private var entries: [String: Entry] = [:]
  private var availableLanguages: [String] = []
  private var languageOverride: String?
  private var latchedLaunchLanguage: String?
  private var systemLanguagesHook: (@Sendable () -> [String])?
  private var didAttemptAutoBootstrap = false

  struct PluralSet {
    var zero: String?
    var one: String?
    var two: String?
    var few: String?
    var many: String?
    var other: String?
  }

  struct LocalizationUnit {
    var value: String?
    var plural: PluralSet?
  }

  struct Entry {
    var localizations: [String: LocalizationUnit] = [:]
  }

  public init() {}

  public var preferredLanguage: String? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return languageOverride
    }
    set {
      lock.lock()
      languageOverride = newValue
      lock.unlock()
    }
  }

  public var systemLanguagesProvider: (@Sendable () -> [String])? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return systemLanguagesHook
    }
    set {
      lock.lock()
      systemLanguagesHook = newValue
      lock.unlock()
    }
  }

  public var localizations: [String] {
    ensureBootstrappedIfNeeded()
    lock.lock()
    defer { lock.unlock() }
    return availableLanguages.isEmpty ? [sourceLanguage] : availableLanguages
  }

  public var activeLaunchLanguage: String {
    ensureBootstrappedIfNeeded()
    lock.lock()
    let override = languageOverride
    let latched = latchedLaunchLanguage
    let src = sourceLanguage
    let locs = availableLanguages.isEmpty ? [sourceLanguage] : availableLanguages
    let hook = systemLanguagesHook
    lock.unlock()

    if let override, !override.isEmpty {
      return Self.preferredLocalizations(from: locs, forPreferences: [override]).first ?? override
    }
    if let latched, !latched.isEmpty {
      return latched
    }
    let prefs = Self.effectiveUserPreferences(systemHook: hook)
    return Self.preferredLocalizations(from: locs, forPreferences: prefs).first ?? src
  }

  public func latchLaunchLanguageIfNeeded() {
    ensureBootstrappedIfNeeded()
    lock.lock()
    if latchedLaunchLanguage != nil {
      lock.unlock()
      return
    }
    let locs = availableLanguages.isEmpty ? [sourceLanguage] : availableLanguages
    let src = sourceLanguage
    let hook = systemLanguagesHook
    lock.unlock()

    let prefs = Self.effectiveUserPreferences(systemHook: hook)
    let matched = Self.preferredLocalizations(from: locs, forPreferences: prefs).first ?? src
    lock.lock()
    if latchedLaunchLanguage == nil {
      latchedLaunchLanguage = matched
    }
    lock.unlock()
  }

  private func ensureBootstrappedIfNeeded() {
    guard self === XCStringsCatalog.shared else { return }
    lock.lock()
    let shouldTry = !didAttemptAutoBootstrap && entries.isEmpty
    if shouldTry {
      didAttemptAutoBootstrap = true
    }
    lock.unlock()
    guard shouldTry else { return }

    let fm = FileManager.default
    let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    var roots: [URL] = [exeDir, cwd]
    var cursor = exeDir
    for _ in 0..<4 {
      cursor = cursor.deletingLastPathComponent()
      roots.append(cursor)
    }
    for root in roots {
      let infoCat = root.appendingPathComponent("Resources/InfoPlist.xcstrings")
      let mainCat = root.appendingPathComponent("Resources/Localizable.xcstrings")
      var loadedAny = false
      if fm.fileExists(atPath: infoCat.path), let data = try? Data(contentsOf: infoCat) {
        loadedAny = load(data: data, merge: true) || loadedAny
      }
      if fm.fileExists(atPath: mainCat.path), let data = try? Data(contentsOf: mainCat) {
        loadedAny = load(data: data, merge: true) || loadedAny
      }
      if loadedAny {
        break
      }
    }
  }

  public func reset() {
    lock.lock()
    sourceLanguage = "en"
    entries.removeAll()
    availableLanguages.removeAll()
    didAttemptAutoBootstrap = true
    lock.unlock()
  }

  @discardableResult
  public func load(from url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url) else {
      return false
    }
    return load(data: data, merge: false)
  }

  @discardableResult
  public func load(data: Data, merge: Bool = false) -> Bool {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let stringsDict = root["strings"] as? [String: Any]
    else {
      return false
    }
    let srcLang = (root["sourceLanguage"] as? String) ?? "en"
    var parsed: [String: Entry] = [:]
    parsed.reserveCapacity(stringsDict.count)
    var langSet: Set<String> = [srcLang]

    for (key, rawEntry) in stringsDict {
      guard let entryDict = rawEntry as? [String: Any],
            let locsDict = entryDict["localizations"] as? [String: Any]
      else {
        continue
      }
      var entry = Entry()
      for (lang, rawLoc) in locsDict {
        guard let locDict = rawLoc as? [String: Any] else { continue }
        langSet.insert(lang)
        var unit = LocalizationUnit()
        if let su = locDict["stringUnit"] as? [String: Any],
           let val = su["value"] as? String
        {
          unit.value = val
        }
        if let vars = locDict["variations"] as? [String: Any],
           let pluralDict = vars["plural"] as? [String: Any]
        {
          var ps = PluralSet()
          func extract(_ form: String) -> String? {
            guard let f = pluralDict[form] as? [String: Any],
                  let su = f["stringUnit"] as? [String: Any]
            else { return nil }
            return su["value"] as? String
          }
          ps.zero = extract("zero")
          ps.one = extract("one")
          ps.two = extract("two")
          ps.few = extract("few")
          ps.many = extract("many")
          ps.other = extract("other")
          unit.plural = ps
        }
        entry.localizations[lang] = unit
      }
      parsed[key] = entry
    }

    lock.lock()
    self.sourceLanguage = srcLang
    if merge {
      for (key, entry) in parsed {
        self.entries[key] = entry
      }
      let combined = Set(self.availableLanguages).union(langSet)
      self.availableLanguages = [srcLang] + combined.filter { $0 != srcLang }.sorted()
    } else {
      self.entries = parsed
      self.availableLanguages = [srcLang] + langSet.filter { $0 != srcLang }.sorted()
    }
    lock.unlock()
    return true
  }

  public func resolve(
    key: String,
    defaultValue: String? = nil,
    arguments: [LocalizationArg] = [],
    locale: Locale? = nil
  ) -> String {
    let template = lookupTemplate(key: key, defaultValue: defaultValue, arguments: arguments, locale: locale)
    guard !arguments.isEmpty else { return template }
    return Self.formatTemplate(template, arguments: arguments)
  }

  private static func readAppleLanguages() -> [String]? {
    if let arr = UserDefaults.standard.stringArray(forKey: "AppleLanguages"), !arr.isEmpty {
      return arr
    }
    if let raw = UserDefaults.standard.object(forKey: "AppleLanguages") as? [Any] {
      let strs = raw.compactMap { $0 as? String }
      if !strs.isEmpty { return strs }
    }
    return nil
  }

  private static func effectiveUserPreferences(systemHook: (@Sendable () -> [String])?) -> [String] {
    if let apple = readAppleLanguages(), !apple.isEmpty {
      return apple
    }
    if let sys = systemHook?(), !sys.isEmpty {
      return sys
    }
    return [Locale.current.identifier]
  }

  public static func preferredLocalizations(
    from possibleLocalizations: [String],
    forPreferences preferencesArray: [String]?
  ) -> [String] {
    guard !possibleLocalizations.isEmpty else { return [] }
    let prefs: [String]
    if let preferencesArray {
      prefs = preferencesArray
    } else {
      XCStringsCatalog.shared.lock.lock()
      let hook = XCStringsCatalog.shared.systemLanguagesHook
      XCStringsCatalog.shared.lock.unlock()
      prefs = effectiveUserPreferences(systemHook: hook)
    }

    var matches: [String] = []
    for pref in prefs {
      let forms = expandedLanguageForms(for: pref)
      for form in forms {
        for loc in possibleLocalizations {
          let locNorm = loc.replacingOccurrences(of: "_", with: "-").lowercased()
          let locPrimary = expandedLanguageForms(for: loc).first ?? locNorm
          if locNorm == form || locPrimary == form {
            if !matches.contains(loc) {
              matches.append(loc)
            }
          }
        }
        if !matches.isEmpty {
          break
        }
      }
    }

    if !matches.isEmpty {
      return matches
    }
    if let en = possibleLocalizations.first(where: { $0.caseInsensitiveCompare("en") == .orderedSame }) {
      return [en]
    }
    if let base = possibleLocalizations.first(where: { $0.caseInsensitiveCompare("Base") == .orderedSame }) {
      return [base]
    }
    return [possibleLocalizations[0]]
  }

  private static func expandedLanguageForms(for identifier: String) -> [String] {
    let clean = identifier
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
    guard !clean.isEmpty else { return [] }
    let lower = clean.lowercased()
    var forms: [String] = []
    func add(_ s: String) {
      if !s.isEmpty && !forms.contains(s) { forms.append(s) }
    }
    add(lower)
    if lower.hasPrefix("zh-hans") || lower == "zh-cn" || lower == "zh-sg" || lower == "zh" {
      add("zh-hans")
      add("zh-cn")
      add("zh")
    } else if lower.hasPrefix("zh-hant") || lower == "zh-tw" || lower == "zh-hk" || lower == "zh-mo" {
      add("zh-hant")
      add("zh-tw")
      add("zh-hk")
      add("zh")
    }
    let parts = lower.split(separator: "-").map(String.init)
    if parts.count >= 2 {
      add("\(parts[0])-\(parts[1])")
    }
    if let base = parts.first {
      add(base)
      if base == "nb" { add("no") }
      if base == "no" { add("nb") }
    }
    return forms
  }

  private func lookupTemplate(
    key: String,
    defaultValue: String?,
    arguments: [LocalizationArg],
    locale: Locale?
  ) -> String {
    ensureBootstrappedIfNeeded()
    lock.lock()
    let override = languageOverride
    let latched = latchedLaunchLanguage
    let entry = entries[key]
    let src = sourceLanguage
    let hook = systemLanguagesHook
    lock.unlock()

    let fallback = defaultValue ?? key
    guard let entry else { return fallback }

    let preferences: [String]
    if let locale, locale.identifier != Locale.current.identifier {
      preferences = [locale.identifier]
    } else if let override, !override.isEmpty {
      preferences = [override]
    } else if let latched, !latched.isEmpty {
      preferences = [latched]
    } else {
      preferences = Self.effectiveUserPreferences(systemHook: hook)
    }

    var candidates: [String] = []
    for pref in preferences {
      for c in Self.languageCandidates(for: pref, sourceLanguage: src) where !candidates.contains(c) {
        candidates.append(c)
      }
    }
    if !candidates.contains(src) {
      candidates.append(src)
    }

    for candidate in candidates {
      if let unit = entry.localizations[candidate] {
        if let plural = unit.plural {
          let n = arguments.compactMap(\.numericValue).first ?? 0
          return Self.selectPlural(plural, number: n, language: candidate) ?? unit.value ?? fallback
        }
        if let val = unit.value {
          return val
        }
      }
    }
    return fallback
  }

  private static func languageCandidates(for identifier: String, sourceLanguage: String) -> [String] {
    let normalized = identifier.replacingOccurrences(of: "_", with: "-")
    var list: [String] = [normalized]
    let lower = normalized.lowercased()
    if lower.hasPrefix("zh-hans") || lower == "zh-cn" || lower == "zh-sg" || lower == "zh" {
      if !list.contains("zh-Hans") { list.append("zh-Hans") }
    } else if lower.hasPrefix("zh-hant") || lower == "zh-tw" || lower == "zh-hk" || lower == "zh-mo" {
      if !list.contains("zh-Hant") { list.append("zh-Hant") }
    }
    if let dash = normalized.firstIndex(of: "-") {
      let base = String(normalized[..<dash])
      if !list.contains(base) { list.append(base) }
      if base.lowercased() == "nb" && !list.contains("no") { list.append("no") }
      if base.lowercased() == "no" && !list.contains("nb") { list.append("nb") }
    }
    if !list.contains(sourceLanguage) {
      list.append(sourceLanguage)
    }
    return list
  }

  private static func selectPlural(_ ps: PluralSet, number: Double, language: String) -> String? {
    let absN = abs(number)
    let intN = Int(absN)
    let isInt = abs(absN - Double(intN)) < 1e-9
    if isInt && intN == 0, let z = ps.zero { return z }
    if isInt && intN == 1, let o = ps.one { return o }
    if isInt && intN == 2, let t = ps.two { return t }
    return ps.other ?? ps.many ?? ps.few ?? ps.one
  }

  package static func formatTemplate(_ template: String, arguments: [LocalizationArg]) -> String {
    var out = ""
    out.reserveCapacity(template.count + 16)
    var idx = template.startIndex
    var nextSequential = 0

    while idx < template.endIndex {
      let ch = template[idx]
      guard ch == "%" else {
        out.append(ch)
        idx = template.index(after: idx)
        continue
      }
      let afterPercent = template.index(after: idx)
      guard afterPercent < template.endIndex else {
        out.append("%")
        break
      }
      if template[afterPercent] == "%" {
        out.append("%")
        idx = template.index(after: afterPercent)
        continue
      }

      var scan = afterPercent
      // Optional positional index e.g. %1$@, %2$lld
      var explicitPos: Int?
      var digits = ""
      while scan < template.endIndex, template[scan].isWholeNumber {
        digits.append(template[scan])
        scan = template.index(after: scan)
      }
      if !digits.isEmpty, scan < template.endIndex, template[scan] == "$" {
        explicitPos = (Int(digits) ?? 1) - 1
        scan = template.index(after: scan)
      } else {
        scan = afterPercent
      }

      // Precision / length modifiers (., numbers, l, ll, z, h)
      var precisionDigits = ""
      if scan < template.endIndex, template[scan] == "." {
        scan = template.index(after: scan)
        while scan < template.endIndex, template[scan].isWholeNumber {
          precisionDigits.append(template[scan])
          scan = template.index(after: scan)
        }
      }
      while scan < template.endIndex, "lhztqL".contains(template[scan]) {
        scan = template.index(after: scan)
      }
      guard scan < template.endIndex else {
        out.append(contentsOf: template[idx...])
        break
      }

      let spec = template[scan]
      let argIndex = explicitPos ?? nextSequential
      if explicitPos == nil { nextSequential += 1 }

      if arguments.indices.contains(argIndex) {
        let arg = arguments[argIndex]
        if (spec == "f" || spec == "F"), let prec = Int(precisionDigits), let num = arg.numericValue {
          out.append(String(format: "%.\(prec)f", num))
        } else {
          out.append(arg.formattedString)
        }
      }
      idx = template.index(after: scan)
    }
    return out
  }
}

public enum LocalizationArg: Hashable, Sendable {
  case string(String)
  case int(Int64)
  case uint(UInt64)
  case double(Double)

  public var formattedString: String {
    switch self {
    case .string(let s): return s
    case .int(let v): return String(v)
    case .uint(let v): return String(v)
    case .double(let d):
      if abs(d.rounded() - d) < 1e-9 { return String(Int64(d)) }
      return String(d)
    }
  }

  public var numericValue: Double? {
    switch self {
    case .string: return nil
    case .int(let v): return Double(v)
    case .uint(let v): return Double(v)
    case .double(let d): return d
    }
  }
}

// MARK: - Foundation String(localized:) & LocalizedStringResource Shims on Non-Darwin

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  extension String {
    public struct LocalizationValue: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Hashable, Sendable {
      public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        package var key: String = ""
        package var arguments: [LocalizationArg] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
          key.reserveCapacity(literalCapacity + interpolationCount * 4)
        }

        public mutating func appendLiteral(_ literal: String) {
          key.append(literal.replacingOccurrences(of: "%", with: "%%"))
        }

        public mutating func appendInterpolation(_ value: String) {
          key.append("%@")
          arguments.append(.string(value))
        }

        public mutating func appendInterpolation<S: StringProtocol>(_ value: S) {
          key.append("%@")
          arguments.append(.string(String(value)))
        }

        public mutating func appendInterpolation(_ value: Int) {
          key.append("%lld")
          arguments.append(.int(Int64(value)))
        }

        public mutating func appendInterpolation(_ value: Int64) {
          key.append("%lld")
          arguments.append(.int(value))
        }

        public mutating func appendInterpolation(_ value: Int32) {
          key.append("%d")
          arguments.append(.int(Int64(value)))
        }

        public mutating func appendInterpolation(_ value: UInt) {
          key.append("%llu")
          arguments.append(.uint(UInt64(value)))
        }

        public mutating func appendInterpolation(_ value: Double) {
          key.append("%lf")
          arguments.append(.double(value))
        }

        public mutating func appendInterpolation(_ value: Float) {
          key.append("%f")
          arguments.append(.double(Double(value)))
        }

        public mutating func appendInterpolation(_ value: CGFloat) {
          key.append("%lf")
          arguments.append(.double(Double(value)))
        }

        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
          key.append("%@")
          arguments.append(.string(value.description))
        }

        public mutating func appendInterpolation<F: FormatStyle>(
          _ input: F.FormatInput, format: F
        ) where F.FormatOutput == String {
          key.append("%@")
          arguments.append(.string(format.format(input)))
        }

        public mutating func appendInterpolation(_ subject: Any, formatter: Formatter) {
          key.append("%@")
          arguments.append(.string(formatter.string(for: subject) ?? ""))
        }
      }

      package let key: String
      package let arguments: [LocalizationArg]

      public init(_ value: String) {
        self.key = value
        self.arguments = []
      }

      public init(stringLiteral value: String) {
        self.key = value
        self.arguments = []
      }

      public init(stringInterpolation: StringInterpolation) {
        self.key = stringInterpolation.key
        self.arguments = stringInterpolation.arguments
      }
    }

    public init(
      localized keyAndValue: LocalizationValue,
      table: String? = nil,
      bundle: Bundle? = nil,
      locale: Locale = .current,
      comment: StaticString? = nil
    ) {
      self = XCStringsCatalog.shared.resolve(
        key: keyAndValue.key,
        arguments: keyAndValue.arguments,
        locale: locale
      )
    }

    public init(
      localized key: StaticString,
      defaultValue: LocalizationValue,
      table: String? = nil,
      bundle: Bundle? = nil,
      locale: Locale = .current,
      comment: StaticString? = nil
    ) {
      let keyStr = key.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
      let defStr = XCStringsCatalog.formatTemplate(defaultValue.key, arguments: defaultValue.arguments)
      self = XCStringsCatalog.shared.resolve(
        key: keyStr,
        defaultValue: defStr,
        arguments: defaultValue.arguments,
        locale: locale
      )
    }

    public init(localized resource: LocalizedStringResource) {
      let defStr = resource.defaultValue.map {
        XCStringsCatalog.formatTemplate($0.key, arguments: $0.arguments)
      }
      self = XCStringsCatalog.shared.resolve(
        key: resource.key,
        defaultValue: defStr,
        arguments: resource.defaultValue?.arguments ?? [],
        locale: resource.locale
      )
    }
  }

  public struct LocalizedStringResource: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Hashable, Sendable {
    public typealias StringInterpolation = String.LocalizationValue.StringInterpolation

    public enum BundleDescription: Hashable, Sendable {
      case main
      case forClass(AnyClass)
      case atURL(URL)

      public static func == (lhs: BundleDescription, rhs: BundleDescription) -> Bool {
        switch (lhs, rhs) {
        case (.main, .main): return true
        case (.atURL(let a), .atURL(let b)): return a == b
        case (.forClass(let a), .forClass(let b)): return a === b
        default: return false
        }
      }

      public func hash(into hasher: inout Hasher) {
        switch self {
        case .main: hasher.combine(0)
        case .atURL(let u): hasher.combine(u)
        case .forClass(let c): hasher.combine(ObjectIdentifier(c))
        }
      }
    }

    public let key: String
    public let defaultValue: String.LocalizationValue?
    public let table: String?
    public var locale: Locale
    public let bundle: BundleDescription

    public init(
      _ keyAndValue: String.LocalizationValue,
      table: String? = nil,
      locale: Locale = .current,
      bundle: BundleDescription = .main,
      comment: StaticString? = nil
    ) {
      self.key = keyAndValue.key
      self.defaultValue = keyAndValue
      self.table = table
      self.locale = locale
      self.bundle = bundle
    }

    public init(
      _ key: StaticString,
      defaultValue: String.LocalizationValue,
      table: String? = nil,
      locale: Locale = .current,
      bundle: BundleDescription = .main,
      comment: StaticString? = nil
    ) {
      self.key = key.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
      self.defaultValue = defaultValue
      self.table = table
      self.locale = locale
      self.bundle = bundle
    }

    public init(stringLiteral value: String) {
      self.init(String.LocalizationValue(stringLiteral: value))
    }

    public init(stringInterpolation: StringInterpolation) {
      self.init(String.LocalizationValue(stringInterpolation: stringInterpolation))
    }
  }
#endif

// MARK: - SwiftUI LocalizedStringKey

public struct LocalizedStringKey: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Equatable, Sendable {
  public struct StringInterpolation: StringInterpolationProtocol, Sendable {
    var key: String = ""
    var arguments: [LocalizationArg] = []

    public init(literalCapacity: Int, interpolationCount: Int) {
      key.reserveCapacity(literalCapacity + interpolationCount * 4)
    }

    public mutating func appendLiteral(_ literal: String) {
      key.append(literal.replacingOccurrences(of: "%", with: "%%"))
    }

    public mutating func appendInterpolation(_ value: String) {
      key.append("%@")
      arguments.append(.string(value))
    }

    public mutating func appendInterpolation<S: StringProtocol>(_ value: S) {
      key.append("%@")
      arguments.append(.string(String(value)))
    }

    public mutating func appendInterpolation(_ value: Int) {
      key.append("%lld")
      arguments.append(.int(Int64(value)))
    }

    public mutating func appendInterpolation(_ value: Int64) {
      key.append("%lld")
      arguments.append(.int(value))
    }

    public mutating func appendInterpolation(_ value: Double) {
      key.append("%lf")
      arguments.append(.double(value))
    }

    public mutating func appendInterpolation(_ value: CGFloat) {
      key.append("%lf")
      arguments.append(.double(Double(value)))
    }

    public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
      key.append("%@")
      arguments.append(.string(value.description))
    }

    public mutating func appendInterpolation<F: FormatStyle>(
      _ input: F.FormatInput, format: F
    ) where F.FormatOutput == String {
      key.append("%@")
      arguments.append(.string(format.format(input)))
    }

    public mutating func appendInterpolation(_ subject: Any, formatter: Formatter) {
      key.append("%@")
      arguments.append(.string(formatter.string(for: subject) ?? ""))
    }

    public mutating func appendInterpolation(_ text: Text) {
      key.append("%@")
      arguments.append(.string(text.content))
    }

    public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
      key.append("%@")
      arguments.append(.string(Text(date, style: style).content))
    }
  }

  let key: String
  let arguments: [LocalizationArg]

  public init(_ value: String) {
    self.key = value
    self.arguments = []
  }

  public init(stringLiteral value: String) {
    self.key = value
    self.arguments = []
  }

  public init(stringInterpolation: StringInterpolation) {
    self.key = stringInterpolation.key
    self.arguments = stringInterpolation.arguments
  }

  package func resolved(locale: Locale? = nil) -> String {
    XCStringsCatalog.shared.resolve(key: key, arguments: arguments, locale: locale)
  }
}

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  extension Date {
    public static var currentDate: Date { Date() }
  }

  public enum SystemFormatStyle {
    public struct DateReference: FormatStyle, Codable, Equatable, Hashable, Sendable {
      public enum Field: String, Codable, Hashable, Sendable {
        case year, month, week, day, hour, minute, second
      }

      public let referenceDate: Date
      public let allowedFields: Set<Field>
      public let maxFieldCount: Int

      public init(
        to referenceDate: Date,
        allowedFields: Set<Field> = [.year, .month, .week, .day, .hour, .minute, .second],
        maxFieldCount: Int = 1
      ) {
        self.referenceDate = referenceDate
        self.allowedFields = allowedFields
        self.maxFieldCount = maxFieldCount
      }

      public static func reference(
        to date: Date,
        allowedFields: Set<Field> = [.year, .month, .week, .day, .hour, .minute, .second],
        maxFieldCount: Int = 1
      ) -> DateReference {
        DateReference(to: date, allowedFields: allowedFields, maxFieldCount: maxFieldCount)
      }

      public func format(_ value: Date) -> String {
        let elapsed = max(0, value.timeIntervalSince(referenceDate))
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
      }
    }
  }
#endif
