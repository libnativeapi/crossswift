import Foundation

#if !os(macOS)
  import CQuickJS

  // MARK: - Internal Runtime & Context Boxes

  private final class WeakJSContext {
    weak var value: JSContext?
    init(_ value: JSContext) {
      self.value = value
    }
  }

  /// Owns a `JSRuntime` and serializes access with a recursive lock so
  /// re-entrant JS -> Swift -> JS calls (such as module compilation callbacks)
  /// and cross-thread `DispatchQueue` hops remain memory-safe.
  internal final class QJSRuntimeBox: @unchecked Sendable {
    let raw: QJSRuntimeRef
    let lock = NSRecursiveLock()
    private var evalDepth: Int = 0
    private var contexts: [UnsafeMutableRawPointer: WeakJSContext] = [:]

    init() {
      guard let rt = qjs_runtime_new() else {
        fatalError("Failed to allocate QuickJS runtime")
      }
      self.raw = rt
    }

    deinit {
      qjs_runtime_free(raw)
    }

    func withLocked<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }

    func register(context: JSContext, rawCtx: QJSContextRef) {
      withLocked {
        contexts[UnsafeMutableRawPointer(rawCtx)] = WeakJSContext(context)
      }
    }

    func unregister(rawCtx: QJSContextRef) {
      withLocked {
        _ = contexts.removeValue(forKey: UnsafeMutableRawPointer(rawCtx))
      }
    }

    /// Runs a JS entry point under the runtime lock, refreshing QuickJS's stack
    /// top on top-level entries (safe across thread-pool hops on serial queues)
    /// and draining queued Promise/microtask jobs when the outermost call exits.
    func withExecutionScope<T>(_ body: () -> T) -> T {
      lock.lock()
      if evalDepth == 0 {
        qjs_runtime_update_stack_top(raw)
      }
      evalDepth += 1
      defer {
        evalDepth -= 1
        if evalDepth == 0 {
          drainPendingJobsLocked()
        }
        lock.unlock()
      }
      return body()
    }

    private func drainPendingJobsLocked() {
      evalDepth += 1
      defer { evalDepth -= 1 }
      while true {
        var jobCtx: QJSContextRef?
        let status = qjs_execute_pending_job(raw, &jobCtx)
        if status == 0 {
          break
        }
        if status < 0, let jobCtx {
          if let excRef = qjs_get_exception(jobCtx) {
            if let jsCtx = contexts[UnsafeMutableRawPointer(jobCtx)]?.value {
              jsCtx.reportRawExceptionLocked(excRef)
            } else {
              qjs_value_free(jobCtx, excRef)
            }
          }
        }
      }
    }
  }

  /// Owns a `JSContext` handle and retains its parent `QJSRuntimeBox` so the
  /// runtime can never be freed while any context or `JSValue` handle is alive.
  internal final class QJSContextBox: @unchecked Sendable {
    let runtime: QJSRuntimeBox
    let raw: QJSContextRef

    init?(runtime: QJSRuntimeBox) {
      guard let ctx = runtime.withLocked({ qjs_context_new(runtime.raw) }) else {
        return nil
      }
      self.runtime = runtime
      self.raw = ctx
    }

    deinit {
      runtime.withLocked {
        qjs_context_free(raw)
      }
    }
  }

  // MARK: - Thread-local Call Frame State

  private final class JSCallFrame {
    weak var context: JSContext?
    let thisValue: JSValue?
    let arguments: [JSValue]

    init(context: JSContext?, thisValue: JSValue?, arguments: [JSValue]) {
      self.context = context
      self.thisValue = thisValue
      self.arguments = arguments
    }
  }

  private enum JSCallFrameStack {
    private static let key = "dev.crossswift.javascriptcore.callStack"

    private static var frames: [JSCallFrame] {
      get {
        (Thread.current.threadDictionary[key] as? [JSCallFrame]) ?? []
      }
      set {
        if newValue.isEmpty {
          Thread.current.threadDictionary.removeObject(forKey: key)
        } else {
          Thread.current.threadDictionary[key] = newValue
        }
      }
    }

    static var current: JSCallFrame? {
      frames.last
    }

    static func push(_ frame: JSCallFrame) {
      var list = frames
      list.append(frame)
      frames = list
    }

    static func pop() {
      var list = frames
      if !list.isEmpty {
        list.removeLast()
      }
      frames = list
    }
  }

  // MARK: - Closure Bridging Storage

  private final class QJSClosureBox {
    let invoke: (QJSContextRef, QJSValueRef?, Int32, UnsafePointer<QJSValueRef?>?) -> QJSValueRef?

    init(
      _ invoke: @escaping (QJSContextRef, QJSValueRef?, Int32, UnsafePointer<QJSValueRef?>?) ->
        QJSValueRef?
    ) {
      self.invoke = invoke
    }
  }

  private func qjsSwiftClosureTrampoline(
    ctx: QJSContextRef?,
    thisVal: QJSValueRef?,
    argc: Int32,
    argv: UnsafePointer<QJSValueRef?>?,
    userdata: UnsafeMutableRawPointer?
  ) -> QJSValueRef? {
    guard let ctx, let userdata else {
      return nil
    }
    let box = Unmanaged<QJSClosureBox>.fromOpaque(userdata).takeUnretainedValue()
    return box.invoke(ctx, thisVal, argc, argv)
  }

  private func qjsSwiftClosureFinalizer(userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    Unmanaged<QJSClosureBox>.fromOpaque(userdata).release()
  }

  // MARK: - Optional Unwrapping Helper

  private protocol _JSCOptional {
    var _unwrappedAny: Any? { get }
  }

  extension Optional: _JSCOptional {
    var _unwrappedAny: Any? {
      switch self {
      case .some(let wrapped): return wrapped
      case .none: return nil
      }
    }
  }

  private func unwrapOptional(_ value: Any?) -> Any? {
    var current: Any? = value
    while let unwrapped = current, let opt = unwrapped as? _JSCOptional {
      current = opt._unwrappedAny
    }
    return current
  }

  // MARK: - JS <-> Swift Value Conversion Helpers

  private func jsStringFromRaw(_ ctx: QJSContextRef, _ ref: QJSValueRef) -> String {
    var len: Int = 0
    guard let cstr = qjs_to_cstring_len(ctx, ref, &len) else {
      return ""
    }
    defer { qjs_free_cstring(ctx, cstr) }
    if len == 0 {
      return ""
    }
    let bytes = UnsafeRawBufferPointer(start: cstr, count: len)
    return String(decoding: bytes, as: UTF8.self)
  }

  private func makeJSString(_ ctx: QJSContextRef, _ string: String) -> QJSValueRef? {
    var utf8 = Array(string.utf8)
    let count = utf8.count
    if count == 0 {
      return qjs_new_string(ctx, "", 0)
    }
    return utf8.withUnsafeMutableBytes { buf in
      let ptr = buf.baseAddress?.assumingMemoryBound(to: CChar.self)
      return qjs_new_string(ctx, ptr, count)
    }
  }

  private func makeJSValue(
    from value: Any?,
    in contextBox: QJSContextBox,
    owner: JSContext?,
    functionName: String = ""
  ) -> QJSValueRef? {
    let ctx = contextBox.raw
    guard let unwrapped = unwrapOptional(value) else {
      return qjs_new_undefined()
    }

    if unwrapped is NSNull {
      return qjs_new_null()
    }
    if let jsVal = unwrapped as? JSValue {
      if let raw = jsVal.raw, let valBox = jsVal.contextBox {
        if valBox.runtime === contextBox.runtime {
          return qjs_value_dup(ctx, raw)
        }
        return makeJSValue(from: jsVal.toObject(), in: contextBox, owner: owner)
      }
      return qjs_new_undefined()
    }
    if let b = unwrapped as? Bool {
      return qjs_new_bool(ctx, b)
    }
    if let i = unwrapped as? Int {
      if i >= Int(Int32.min) && i <= Int(Int32.max) {
        return qjs_new_int32(ctx, Int32(i))
      }
      return qjs_new_float64(ctx, Double(i))
    }
    if let i32 = unwrapped as? Int32 {
      return qjs_new_int32(ctx, i32)
    }
    if let i16 = unwrapped as? Int16 {
      return qjs_new_int32(ctx, Int32(i16))
    }
    if let i8 = unwrapped as? Int8 {
      return qjs_new_int32(ctx, Int32(i8))
    }
    if let i64 = unwrapped as? Int64 {
      if i64 >= Int64(Int32.min) && i64 <= Int64(Int32.max) {
        return qjs_new_int32(ctx, Int32(i64))
      }
      return qjs_new_float64(ctx, Double(i64))
    }
    if let u = unwrapped as? UInt {
      if u <= UInt(Int32.max) {
        return qjs_new_int32(ctx, Int32(u))
      }
      return qjs_new_float64(ctx, Double(u))
    }
    if let u32 = unwrapped as? UInt32 {
      if u32 <= UInt32(Int32.max) {
        return qjs_new_int32(ctx, Int32(u32))
      }
      return qjs_new_float64(ctx, Double(u32))
    }
    if let u16 = unwrapped as? UInt16 {
      return qjs_new_int32(ctx, Int32(u16))
    }
    if let u8 = unwrapped as? UInt8 {
      return qjs_new_int32(ctx, Int32(u8))
    }
    if let u64 = unwrapped as? UInt64 {
      if u64 <= UInt64(Int32.max) {
        return qjs_new_int32(ctx, Int32(u64))
      }
      return qjs_new_float64(ctx, Double(u64))
    }
    if let d = unwrapped as? Double {
      return qjs_new_float64(ctx, d)
    }
    if let f = unwrapped as? Float {
      return qjs_new_float64(ctx, Double(f))
    }
    if let s = unwrapped as? String {
      return makeJSString(ctx, s)
    }
    if let ns = unwrapped as? NSString {
      return makeJSString(ctx, String(ns))
    }
    if let date = unwrapped as? Date {
      return qjs_new_date(ctx, date.timeIntervalSince1970 * 1000.0)
    }
    if let num = unwrapped as? NSNumber {
      let typeChar = UnicodeScalar(UInt8(bitPattern: num.objCType.pointee))
      if typeChar == "B" || typeChar == "c" {
        return qjs_new_bool(ctx, num.boolValue)
      }
      let d = num.doubleValue
      if d.isFinite && d.rounded(.towardZero) == d && d >= Double(Int32.min)
        && d <= Double(Int32.max) && !(d == 0 && d.sign == .minus)
      {
        return qjs_new_int32(ctx, Int32(d))
      }
      return qjs_new_float64(ctx, d)
    }
    if let array = unwrapped as? [Any] {
      guard let jsArr = qjs_new_array(ctx) else { return qjs_new_undefined() }
      for (index, element) in array.enumerated() {
        let jsElem = makeJSValue(from: element, in: contextBox, owner: owner)
        _ = qjs_set_property_uint32(ctx, jsArr, UInt32(index), jsElem)
        qjs_value_free(ctx, jsElem)
      }
      return jsArr
    }
    if let nsArray = unwrapped as? NSArray {
      guard let jsArr = qjs_new_array(ctx) else { return qjs_new_undefined() }
      for index in 0..<nsArray.count {
        let jsElem = makeJSValue(from: nsArray.object(at: index), in: contextBox, owner: owner)
        _ = qjs_set_property_uint32(ctx, jsArr, UInt32(index), jsElem)
        qjs_value_free(ctx, jsElem)
      }
      return jsArr
    }
    if let dict = unwrapped as? [String: Any] {
      guard let jsObj = qjs_new_object(ctx) else { return qjs_new_undefined() }
      for (k, v) in dict {
        let jsVal = makeJSValue(from: v, in: contextBox, owner: owner, functionName: k)
        k.withCString { keyCStr in
          _ = qjs_set_property_str(ctx, jsObj, keyCStr, jsVal)
        }
        qjs_value_free(ctx, jsVal)
      }
      return jsObj
    }
    if let dict = unwrapped as? [AnyHashable: Any] {
      guard let jsObj = qjs_new_object(ctx) else { return qjs_new_undefined() }
      for (k, v) in dict {
        let keyStr = (k as? String) ?? (k as? NSString).map(String.init) ?? String(describing: k)
        let jsVal = makeJSValue(from: v, in: contextBox, owner: owner, functionName: keyStr)
        keyStr.withCString { keyCStr in
          _ = qjs_set_property_str(ctx, jsObj, keyCStr, jsVal)
        }
        qjs_value_free(ctx, jsVal)
      }
      return jsObj
    }
    if let nsDict = unwrapped as? NSDictionary {
      guard let jsObj = qjs_new_object(ctx) else { return qjs_new_undefined() }
      for (k, v) in nsDict {
        let keyStr = (k as? String) ?? (k as? NSString).map(String.init) ?? String(describing: k)
        let jsVal = makeJSValue(from: v, in: contextBox, owner: owner, functionName: keyStr)
        keyStr.withCString { keyCStr in
          _ = qjs_set_property_str(ctx, jsObj, keyCStr, jsVal)
        }
        qjs_value_free(ctx, jsVal)
      }
      return jsObj
    }

    if let closureRef = tryBridgeClosure(
      unwrapped,
      in: contextBox,
      owner: owner,
      name: functionName
    ) {
      return closureRef
    }

    return qjs_new_undefined()
  }

  // MARK: - Swift Closure Bridging

  private protocol _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Self
  }

  extension String: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> String {
      guard let ref else { return "undefined" }
      return jsStringFromRaw(ctx, ref)
    }
  }

  extension Bool: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Bool {
      guard let ref else { return false }
      return qjs_to_bool(ctx, ref)
    }
  }

  extension Int32: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Int32 {
      guard let ref else { return 0 }
      return qjs_to_int32(ctx, ref)
    }
  }

  extension Int: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Int {
      guard let ref else { return 0 }
      let d = qjs_to_float64(ctx, ref)
      if d.isFinite && d >= Double(Int.min) && d <= Double(Int.max) {
        return Int(d)
      }
      return Int(qjs_to_int32(ctx, ref))
    }
  }

  extension Double: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Double {
      guard let ref else { return 0 }
      return qjs_to_float64(ctx, ref)
    }
  }

  extension Float: _JSArg {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> Float {
      guard let ref else { return 0 }
      return Float(qjs_to_float64(ctx, ref))
    }
  }

  private struct _JSValueArg: _JSArg {
    let value: JSValue
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> _JSValueArg {
      let dup = ref.flatMap { qjs_value_dup(ctx, $0) } ?? qjs_new_undefined()
      return _JSValueArg(value: JSValue(internalContextBox: contextBox, owner: owner, raw: dup))
    }
  }

  extension Optional: _JSArg where Wrapped == String {
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> String? {
      guard let ref, !qjs_is_undefined(ref), !qjs_is_null(ref) else { return nil }
      return jsStringFromRaw(ctx, ref)
    }
  }

  private struct _JSOptionalValueArg: _JSArg {
    let value: JSValue?
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> _JSOptionalValueArg {
      guard let ref else {
        return _JSOptionalValueArg(
          value: JSValue(internalContextBox: contextBox, owner: owner, raw: qjs_new_undefined())
        )
      }
      return _JSOptionalValueArg(
        value: JSValue(internalContextBox: contextBox, owner: owner, raw: qjs_value_dup(ctx, ref))
      )
    }
  }

  private struct _JSAnyArg: _JSArg {
    let value: Any?
    static func _extract(
      ctx: QJSContextRef,
      contextBox: QJSContextBox,
      owner: JSContext?,
      ref: QJSValueRef?
    ) -> _JSAnyArg {
      guard let ref else { return _JSAnyArg(value: nil) }
      let jsVal = JSValue(internalContextBox: contextBox, owner: owner, raw: qjs_value_dup(ctx, ref))
      return _JSAnyArg(value: jsVal.toObject())
    }
  }

  private func makeBridgedFunction(
    name: String,
    arity: Int32,
    in contextBox: QJSContextBox,
    owner: JSContext?,
    body: @escaping (QJSContextRef, QJSContextBox, JSContext?, Int32, UnsafePointer<QJSValueRef?>?) ->
      Any?
  ) -> QJSValueRef? {
    let closureBox = QJSClosureBox { [weak contextBox, weak owner] ctx, thisVal, argc, argv in
      guard let box = contextBox else { return nil }
      let ownerCtx = owner

      let thisJS: JSValue? = thisVal.map {
        JSValue(internalContextBox: box, owner: ownerCtx, raw: qjs_value_dup(ctx, $0))
      }
      var jsArgs: [JSValue] = []
      if argc > 0, let argv {
        jsArgs.reserveCapacity(Int(argc))
        for i in 0..<Int(argc) {
          let dup = argv[i].flatMap { qjs_value_dup(ctx, $0) } ?? qjs_new_undefined()
          jsArgs.append(JSValue(internalContextBox: box, owner: ownerCtx, raw: dup))
        }
      }

      JSCallFrameStack.push(JSCallFrame(context: ownerCtx, thisValue: thisJS, arguments: jsArgs))
      defer { JSCallFrameStack.pop() }

      let result = body(ctx, box, ownerCtx, argc, argv)
      return makeJSValue(from: result, in: box, owner: ownerCtx)
    }

    let userdata = Unmanaged.passRetained(closureBox).toOpaque()
    return name.withCString { cName in
      qjs_new_closure(
        contextBox.raw,
        cName,
        arity,
        qjsSwiftClosureTrampoline,
        qjsSwiftClosureFinalizer,
        userdata
      )
    }
  }

  private func argRefAt(
    _ index: Int,
    argc: Int32,
    argv: UnsafePointer<QJSValueRef?>?
  ) -> QJSValueRef? {
    guard index < Int(argc), let argv else { return nil }
    return argv[index]
  }

  private func matchFn0<R>(_ value: Any) -> (() -> R)? {
    if let fn = value as? () -> R { return fn }
    if let fn = value as? @Sendable () -> R { return fn }
    return nil
  }

  private func matchFn1<A, R>(_ value: Any) -> ((A) -> R)? {
    if let fn = value as? (A) -> R { return fn }
    if let fn = value as? @Sendable (A) -> R { return fn }
    return nil
  }

  private func matchFn2<A, B, R>(_ value: Any) -> ((A, B) -> R)? {
    if let fn = value as? (A, B) -> R { return fn }
    if let fn = value as? @Sendable (A, B) -> R { return fn }
    return nil
  }

  private func matchFn3<A, B, C, R>(_ value: Any) -> ((A, B, C) -> R)? {
    if let fn = value as? (A, B, C) -> R { return fn }
    if let fn = value as? @Sendable (A, B, C) -> R { return fn }
    return nil
  }

  private func matchFn4<A, B, C, D, R>(_ value: Any) -> ((A, B, C, D) -> R)? {
    if let fn = value as? (A, B, C, D) -> R { return fn }
    if let fn = value as? @Sendable (A, B, C, D) -> R { return fn }
    return nil
  }

  private func tryBridge0(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrap<R>(_ invoke: @escaping () -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { _, _, _, _, _ in
        invoke()
      }
    }
    if let fn: () -> Void = matchFn0(value) { return wrap { fn(); return nil as Any? } }
    if let fn: () -> String = matchFn0(value) { return wrap(fn) }
    if let fn: () -> String? = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Bool = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Int = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Int32 = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Double = matchFn0(value) { return wrap(fn) }
    if let fn: () -> JSValue? = matchFn0(value) { return wrap(fn) }
    if let fn: () -> JSValue = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Any? = matchFn0(value) { return wrap(fn) }
    if let fn: () -> Any = matchFn0(value) { return wrap(fn) }
    return nil
  }

  private func tryBridge1<A: _JSArg>(
    _ value: Any,
    _: A.Type,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrap<R>(_ invoke: @escaping (A) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 1, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = A._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv))
        return invoke(a)
      }
    }
    if let fn: (A) -> Void = matchFn1(value) { return wrap { fn($0); return nil as Any? } }
    if let fn: (A) -> String = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> String? = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Bool = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Int = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Int32 = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Double = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> JSValue? = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> JSValue = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Any? = matchFn1(value) { return wrap(fn) }
    if let fn: (A) -> Any = matchFn1(value) { return wrap(fn) }
    return nil
  }

  private func tryBridge1Any(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrapJS<R>(_ invoke: @escaping (JSValue) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 1, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        return invoke(a)
      }
    }
    func wrapOpt<R>(_ invoke: @escaping (Any?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 1, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        return invoke(a)
      }
    }
    func wrapJSOpt<R>(_ invoke: @escaping (JSValue?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 1, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        return invoke(a)
      }
    }
    if let fn: (JSValue) -> Void = matchFn1(value) { return wrapJS { fn($0); return nil as Any? } }
    if let fn: (JSValue) -> String = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> String? = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> Bool = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> Int = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> Int32 = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> Double = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> JSValue? = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> JSValue = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue) -> Any? = matchFn1(value) { return wrapJS(fn) }
    if let fn: (JSValue?) -> Void = matchFn1(value) { return wrapJSOpt { fn($0); return nil as Any? } }
    if let fn: (JSValue?) -> String = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?) -> Bool = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?) -> Int = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?) -> Double = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?) -> JSValue? = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?) -> Any? = matchFn1(value) { return wrapJSOpt(fn) }
    if let fn: (Any?) -> Void = matchFn1(value) { return wrapOpt { fn($0); return nil as Any? } }
    if let fn: (Any?) -> String = matchFn1(value) { return wrapOpt(fn) }
    if let fn: (Any?) -> Bool = matchFn1(value) { return wrapOpt(fn) }
    if let fn: (Any?) -> Int = matchFn1(value) { return wrapOpt(fn) }
    if let fn: (Any?) -> Double = matchFn1(value) { return wrapOpt(fn) }
    if let fn: (Any?) -> JSValue? = matchFn1(value) { return wrapOpt(fn) }
    if let fn: (Any?) -> Any? = matchFn1(value) { return wrapOpt(fn) }
    return nil
  }

  private func tryBridge2<A: _JSArg, B: _JSArg>(
    _ value: Any,
    _: A.Type,
    _: B.Type,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrap<R>(_ invoke: @escaping (A, B) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 2, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = A._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv))
        let bVal = B._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv))
        return invoke(a, bVal)
      }
    }
    if let fn: (A, B) -> Void = matchFn2(value) { return wrap { fn($0, $1); return nil as Any? } }
    if let fn: (A, B) -> String = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> String? = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Bool = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Int = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Int32 = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Double = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> JSValue? = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> JSValue = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Any? = matchFn2(value) { return wrap(fn) }
    if let fn: (A, B) -> Any = matchFn2(value) { return wrap(fn) }
    return nil
  }

  private func tryBridge2Special(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrapStrJS<R>(_ invoke: @escaping (String, JSValue) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 2, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = String._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv))
        let bVal = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        return invoke(a, bVal)
      }
    }
    func wrapJS2<R>(_ invoke: @escaping (JSValue, JSValue) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 2, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        return invoke(a, bVal)
      }
    }
    func wrapJSOpt<R>(_ invoke: @escaping (JSValue?, JSValue?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 2, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        return invoke(a, bVal)
      }
    }
    func wrapAnyOpt<R>(_ invoke: @escaping (Any?, Any?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 2, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        return invoke(a, bVal)
      }
    }
    if let fn: (String, JSValue) -> Void = matchFn2(value) { return wrapStrJS { fn($0, $1); return nil as Any? } }
    if let fn: (String, JSValue) -> String = matchFn2(value) { return wrapStrJS(fn) }
    if let fn: (String, JSValue) -> JSValue? = matchFn2(value) { return wrapStrJS(fn) }
    if let fn: (String, JSValue) -> Any? = matchFn2(value) { return wrapStrJS(fn) }
    if let fn: (JSValue, JSValue) -> Void = matchFn2(value) { return wrapJS2 { fn($0, $1); return nil as Any? } }
    if let fn: (JSValue, JSValue) -> String = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue, JSValue) -> Bool = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue, JSValue) -> Int = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue, JSValue) -> Double = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue, JSValue) -> JSValue? = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue, JSValue) -> Any? = matchFn2(value) { return wrapJS2(fn) }
    if let fn: (JSValue?, JSValue?) -> Void = matchFn2(value) { return wrapJSOpt { fn($0, $1); return nil as Any? } }
    if let fn: (JSValue?, JSValue?) -> String = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?) -> Bool = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?) -> Int = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?) -> Double = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?) -> JSValue? = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?) -> Any? = matchFn2(value) { return wrapJSOpt(fn) }
    if let fn: (Any?, Any?) -> Void = matchFn2(value) { return wrapAnyOpt { fn($0, $1); return nil as Any? } }
    if let fn: (Any?, Any?) -> String = matchFn2(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?) -> Bool = matchFn2(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?) -> Int = matchFn2(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?) -> Double = matchFn2(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?) -> JSValue? = matchFn2(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?) -> Any? = matchFn2(value) { return wrapAnyOpt(fn) }
    return nil
  }

  private func tryBridge3<A: _JSArg, B: _JSArg, C: _JSArg>(
    _ value: Any,
    _: A.Type,
    _: B.Type,
    _: C.Type,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrap<R>(_ invoke: @escaping (A, B, C) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 3, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = A._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv))
        let bVal = B._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv))
        let c = C._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv))
        return invoke(a, bVal, c)
      }
    }
    if let fn: (A, B, C) -> Void = matchFn3(value) { return wrap { fn($0, $1, $2); return nil as Any? } }
    if let fn: (A, B, C) -> String = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> String? = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Bool = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Int = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Int32 = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Double = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> JSValue? = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> JSValue = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Any? = matchFn3(value) { return wrap(fn) }
    if let fn: (A, B, C) -> Any = matchFn3(value) { return wrap(fn) }
    return nil
  }

  private func tryBridge3Special(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrapJS3<R>(_ invoke: @escaping (JSValue, JSValue, JSValue) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 3, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        return invoke(a, bVal, c)
      }
    }
    func wrapJSOpt<R>(_ invoke: @escaping (JSValue?, JSValue?, JSValue?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 3, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        return invoke(a, bVal, c)
      }
    }
    func wrapAnyOpt<R>(_ invoke: @escaping (Any?, Any?, Any?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 3, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        return invoke(a, bVal, c)
      }
    }
    if let fn: (JSValue, JSValue, JSValue) -> Void = matchFn3(value) { return wrapJS3 { fn($0, $1, $2); return nil as Any? } }
    if let fn: (JSValue, JSValue, JSValue) -> String = matchFn3(value) { return wrapJS3(fn) }
    if let fn: (JSValue, JSValue, JSValue) -> JSValue? = matchFn3(value) { return wrapJS3(fn) }
    if let fn: (JSValue, JSValue, JSValue) -> Any? = matchFn3(value) { return wrapJS3(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?) -> Void = matchFn3(value) { return wrapJSOpt { fn($0, $1, $2); return nil as Any? } }
    if let fn: (JSValue?, JSValue?, JSValue?) -> String = matchFn3(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?) -> JSValue? = matchFn3(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?) -> Any? = matchFn3(value) { return wrapJSOpt(fn) }
    if let fn: (Any?, Any?, Any?) -> Void = matchFn3(value) { return wrapAnyOpt { fn($0, $1, $2); return nil as Any? } }
    if let fn: (Any?, Any?, Any?) -> String = matchFn3(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?, Any?) -> JSValue? = matchFn3(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?, Any?) -> Any? = matchFn3(value) { return wrapAnyOpt(fn) }
    return nil
  }

  private func tryBridge4<A: _JSArg, B: _JSArg, C: _JSArg, D: _JSArg>(
    _ value: Any,
    _: A.Type,
    _: B.Type,
    _: C.Type,
    _: D.Type,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrap<R>(_ invoke: @escaping (A, B, C, D) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 4, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = A._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv))
        let bVal = B._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv))
        let c = C._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv))
        let d = D._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(3, argc: argc, argv: argv))
        return invoke(a, bVal, c, d)
      }
    }
    if let fn: (A, B, C, D) -> Void = matchFn4(value) { return wrap { fn($0, $1, $2, $3); return nil as Any? } }
    if let fn: (A, B, C, D) -> String = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> String? = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Bool = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Int = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Int32 = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Double = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> JSValue? = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> JSValue = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Any? = matchFn4(value) { return wrap(fn) }
    if let fn: (A, B, C, D) -> Any = matchFn4(value) { return wrap(fn) }
    return nil
  }

  private func tryBridge4Special(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func wrapJS4<R>(_ invoke: @escaping (JSValue, JSValue, JSValue, JSValue) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 4, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        let d = _JSValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(3, argc: argc, argv: argv)).value
        return invoke(a, bVal, c, d)
      }
    }
    func wrapJSOpt<R>(_ invoke: @escaping (JSValue?, JSValue?, JSValue?, JSValue?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 4, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        let d = _JSOptionalValueArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(3, argc: argc, argv: argv)).value
        return invoke(a, bVal, c, d)
      }
    }
    func wrapAnyOpt<R>(_ invoke: @escaping (Any?, Any?, Any?, Any?) -> R) -> QJSValueRef? {
      makeBridgedFunction(name: name, arity: 4, in: box, owner: owner) { ctx, b, o, argc, argv in
        let a = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(0, argc: argc, argv: argv)).value
        let bVal = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(1, argc: argc, argv: argv)).value
        let c = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(2, argc: argc, argv: argv)).value
        let d = _JSAnyArg._extract(ctx: ctx, contextBox: b, owner: o, ref: argRefAt(3, argc: argc, argv: argv)).value
        return invoke(a, bVal, c, d)
      }
    }
    if let fn: (JSValue, JSValue, JSValue, JSValue) -> Void = matchFn4(value) { return wrapJS4 { fn($0, $1, $2, $3); return nil as Any? } }
    if let fn: (JSValue, JSValue, JSValue, JSValue) -> String = matchFn4(value) { return wrapJS4(fn) }
    if let fn: (JSValue, JSValue, JSValue, JSValue) -> JSValue? = matchFn4(value) { return wrapJS4(fn) }
    if let fn: (JSValue, JSValue, JSValue, JSValue) -> Any? = matchFn4(value) { return wrapJS4(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?, JSValue?) -> Void = matchFn4(value) { return wrapJSOpt { fn($0, $1, $2, $3); return nil as Any? } }
    if let fn: (JSValue?, JSValue?, JSValue?, JSValue?) -> String = matchFn4(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?, JSValue?) -> JSValue? = matchFn4(value) { return wrapJSOpt(fn) }
    if let fn: (JSValue?, JSValue?, JSValue?, JSValue?) -> Any? = matchFn4(value) { return wrapJSOpt(fn) }
    if let fn: (Any?, Any?, Any?, Any?) -> Void = matchFn4(value) { return wrapAnyOpt { fn($0, $1, $2, $3); return nil as Any? } }
    if let fn: (Any?, Any?, Any?, Any?) -> String = matchFn4(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?, Any?, Any?) -> JSValue? = matchFn4(value) { return wrapAnyOpt(fn) }
    if let fn: (Any?, Any?, Any?, Any?) -> Any? = matchFn4(value) { return wrapAnyOpt(fn) }
    return nil
  }

  private func tryBridgeVariadic(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    func extractJSArgs(
      ctx: QJSContextRef,
      b: QJSContextBox,
      o: JSContext?,
      argc: Int32,
      argv: UnsafePointer<QJSValueRef?>?
    ) -> [JSValue] {
      guard argc > 0, let argv else { return [] }
      return (0..<Int(argc)).map { i in
        let dup = argv[i].flatMap { qjs_value_dup(ctx, $0) } ?? qjs_new_undefined()
        return JSValue(internalContextBox: b, owner: o, raw: dup)
      }
    }
    if let fn: ([JSValue]) -> Void = matchFn1(value) {
      return makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { ctx, b, o, argc, argv in
        fn(extractJSArgs(ctx: ctx, b: b, o: o, argc: argc, argv: argv))
        return nil
      }
    }
    if let fn: ([JSValue]) -> JSValue? = matchFn1(value) {
      return makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { ctx, b, o, argc, argv in
        fn(extractJSArgs(ctx: ctx, b: b, o: o, argc: argc, argv: argv))
      }
    }
    if let fn: ([JSValue]) -> Any? = matchFn1(value) {
      return makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { ctx, b, o, argc, argv in
        fn(extractJSArgs(ctx: ctx, b: b, o: o, argc: argc, argv: argv))
      }
    }
    if let fn: ([Any]) -> Void = matchFn1(value) {
      return makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { ctx, b, o, argc, argv in
        let args: [Any] = extractJSArgs(ctx: ctx, b: b, o: o, argc: argc, argv: argv).map {
          $0.toObject() ?? NSNull()
        }
        fn(args)
        return nil
      }
    }
    if let fn: ([Any]) -> Any? = matchFn1(value) {
      return makeBridgedFunction(name: name, arity: 0, in: box, owner: owner) { ctx, b, o, argc, argv in
        let args: [Any] = extractJSArgs(ctx: ctx, b: b, o: o, argc: argc, argv: argv).map {
          $0.toObject() ?? NSNull()
        }
        return fn(args)
      }
    }
    return nil
  }

  private func tryBridgeClosure(
    _ value: Any,
    in box: QJSContextBox,
    owner: JSContext?,
    name: String
  ) -> QJSValueRef? {
    // 0 arguments
    if let r = tryBridge0(value, in: box, owner: owner, name: name) { return r }

    // 1 argument
    if let r = tryBridge1(value, String.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, String?.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, Int32.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1(value, Float.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge1Any(value, in: box, owner: owner, name: name) { return r }

    // 2 arguments
    if let r = tryBridge2(value, String.self, String.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, String.self, String?.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, String.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, String.self, Int32.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, String.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, String.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, Int.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, Int32.self, Int32.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, Double.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2(value, Bool.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge2Special(value, in: box, owner: owner, name: name) { return r }

    // 3 arguments
    if let r = tryBridge3(value, String.self, String.self, String.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, String.self, Double.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, String.self, String.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, String.self, String.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, String.self, String.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, String.self, Int.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, Int.self, Int.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3(value, Double.self, Double.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge3Special(value, in: box, owner: owner, name: name) { return r }

    // 4 arguments
    if let r = tryBridge4(value, String.self, String.self, String.self, String.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4(value, String.self, String.self, String.self, Bool.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4(value, String.self, String.self, String.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4(value, String.self, String.self, String.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4(value, Int.self, Int.self, Int.self, Int.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4(value, Double.self, Double.self, Double.self, Double.self, in: box, owner: owner, name: name) { return r }
    if let r = tryBridge4Special(value, in: box, owner: owner, name: name) { return r }

    // Variadic helpers
    if let r = tryBridgeVariadic(value, in: box, owner: owner, name: name) { return r }

    return nil
  }

  // MARK: - Public JavaScriptCore API

  open class JSVirtualMachine: NSObject, @unchecked Sendable {
    internal let runtimeBox: QJSRuntimeBox

    public override init() {
      self.runtimeBox = QJSRuntimeBox()
      super.init()
    }
  }

  open class JSValue: NSObject, @unchecked Sendable {
    internal let contextBox: QJSContextBox?
    internal weak var ownerContext: JSContext?
    internal var raw: QJSValueRef?

    public var context: JSContext! { ownerContext }

    public override init() {
      self.contextBox = nil
      self.ownerContext = nil
      self.raw = nil
      super.init()
    }

    internal init(
      internalContextBox: QJSContextBox,
      owner: JSContext?,
      raw: QJSValueRef?
    ) {
      self.contextBox = internalContextBox
      self.ownerContext = owner
      self.raw = raw
      super.init()
    }

    deinit {
      if let raw, let contextBox {
        contextBox.runtime.withLocked {
          qjs_value_free(contextBox.raw, raw)
        }
      }
    }

    public init!(newObjectIn context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      guard let obj = box.runtime.withLocked({ qjs_new_object(box.raw) }) else {
        return nil
      }
      self.contextBox = box
      self.ownerContext = context
      self.raw = obj
      super.init()
    }

    public init!(newArrayIn context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      guard let arr = box.runtime.withLocked({ qjs_new_array(box.raw) }) else {
        return nil
      }
      self.contextBox = box
      self.ownerContext = context
      self.raw = arr
      super.init()
    }

    public init!(newErrorFromMessage message: String!, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      let msg = message ?? ""
      let errRef: QJSValueRef? = box.runtime.withExecutionScope {
        let global = qjs_get_global_object(box.raw)
        defer { qjs_value_free(box.raw, global) }
        let errCtor = qjs_get_property_str(box.raw, global, "Error")
        defer { qjs_value_free(box.raw, errCtor) }
        let msgRef = makeJSString(box.raw, msg)
        defer { qjs_value_free(box.raw, msgRef) }
        let args: [QJSValueRef?] = [msgRef]
        return args.withUnsafeBufferPointer { buf in
          qjs_call_constructor(box.raw, errCtor, 1, buf.baseAddress)
        }
      }
      self.contextBox = box
      self.ownerContext = context
      self.raw = errRef ?? qjs_new_undefined()
      super.init()
    }

    public init!(undefinedIn context: JSContext!) {
      guard let context else { return nil }
      self.contextBox = context.contextBox
      self.ownerContext = context
      self.raw = qjs_new_undefined()
      super.init()
    }

    public init!(nullIn context: JSContext!) {
      guard let context else { return nil }
      self.contextBox = context.contextBox
      self.ownerContext = context
      self.raw = qjs_new_null()
      super.init()
    }

    public init!(bool value: Bool, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      self.contextBox = box
      self.ownerContext = context
      self.raw = box.runtime.withLocked { qjs_new_bool(box.raw, value) }
      super.init()
    }

    public init!(int32 value: Int32, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      self.contextBox = box
      self.ownerContext = context
      self.raw = box.runtime.withLocked { qjs_new_int32(box.raw, value) }
      super.init()
    }

    public init!(uInt32 value: UInt32, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      self.contextBox = box
      self.ownerContext = context
      self.raw = box.runtime.withLocked {
        if value <= UInt32(Int32.max) {
          return qjs_new_int32(box.raw, Int32(value))
        }
        return qjs_new_float64(box.raw, Double(value))
      }
      super.init()
    }

    public init!(double value: Double, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      self.contextBox = box
      self.ownerContext = context
      self.raw = box.runtime.withLocked { qjs_new_float64(box.raw, value) }
      super.init()
    }

    public init!(object value: Any!, in context: JSContext!) {
      guard let context else { return nil }
      let box = context.contextBox
      self.contextBox = box
      self.ownerContext = context
      self.raw = box.runtime.withLocked {
        makeJSValue(from: value, in: box, owner: context)
      }
      super.init()
    }

    // MARK: Type Predicates

    public var isUndefined: Bool {
      guard let raw, let contextBox else { return true }
      return contextBox.runtime.withLocked { qjs_is_undefined(raw) }
    }

    public var isNull: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_null(raw) }
    }

    public var isBoolean: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_bool(raw) }
    }

    public var isNumber: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_number(raw) }
    }

    public var isString: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_string(raw) }
    }

    public var isObject: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_object(raw) }
    }

    public var isArray: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_array(raw) }
    }

    public var isDate: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_date(raw) }
    }

    public var isSymbol: Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked { qjs_is_symbol(raw) }
    }

    // MARK: Comparisons

    public func isEqual(to value: Any!) -> Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked {
        let other = makeJSValue(from: value, in: contextBox, owner: ownerContext)
        defer { qjs_value_free(contextBox.raw, other) }
        return qjs_is_strict_equal(contextBox.raw, raw, other)
      }
    }

    public func isEqualWithTypeCoercion(to value: Any!) -> Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked {
        let other = makeJSValue(from: value, in: contextBox, owner: ownerContext)
        defer { qjs_value_free(contextBox.raw, other) }
        return qjs_is_equal(contextBox.raw, raw, other)
      }
    }

    public func isInstance(of value: Any!) -> Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked {
        let ctor = makeJSValue(from: value, in: contextBox, owner: ownerContext)
        defer { qjs_value_free(contextBox.raw, ctor) }
        return qjs_is_instance_of(contextBox.raw, raw, ctor)
      }
    }

    // MARK: Conversions

    public func toString() -> String! {
      guard let raw, let contextBox else { return "undefined" }
      return contextBox.runtime.withLocked {
        jsStringFromRaw(contextBox.raw, raw)
      }
    }

    public func toBool() -> Bool {
      guard let raw, let contextBox else { return false }
      return contextBox.runtime.withLocked {
        qjs_to_bool(contextBox.raw, raw)
      }
    }

    public func toInt32() -> Int32 {
      guard let raw, let contextBox else { return 0 }
      return contextBox.runtime.withLocked {
        qjs_to_int32(contextBox.raw, raw)
      }
    }

    public func toUInt32() -> UInt32 {
      UInt32(bitPattern: toInt32())
    }

    public func toDouble() -> Double {
      guard let raw, let contextBox else { return 0 }
      return contextBox.runtime.withLocked {
        qjs_to_float64(contextBox.raw, raw)
      }
    }

    public func toDate() -> Date! {
      guard let raw, let contextBox else { return nil }
      return contextBox.runtime.withLocked {
        guard qjs_is_date(raw) else { return nil }
        let ms = qjs_to_float64(contextBox.raw, raw)
        guard ms.isFinite else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
      }
    }

    public func toObject() -> Any! {
      guard let raw, let contextBox else { return nil }
      return contextBox.runtime.withLocked {
        convertRawToSwiftLocked(raw, in: contextBox, depth: 0)
      }
    }

    public func toDictionary() -> [AnyHashable: Any]! {
      guard let raw, let contextBox else { return nil }
      return contextBox.runtime.withLocked {
        guard qjs_is_object(raw) else { return nil }
        return convertObjectToDictionaryLocked(raw, in: contextBox, depth: 0)
      }
    }

    public func toArray() -> [Any]! {
      guard let raw, let contextBox else { return nil }
      return contextBox.runtime.withLocked {
        guard qjs_is_object(raw) else { return nil }
        return convertArrayToSwiftLocked(raw, in: contextBox, depth: 0)
      }
    }

    private func convertRawToSwiftLocked(
      _ ref: QJSValueRef,
      in box: QJSContextBox,
      depth: Int
    ) -> Any? {
      if qjs_is_undefined(ref) {
        return nil
      }
      if qjs_is_null(ref) {
        return NSNull()
      }
      if qjs_is_bool(ref) {
        return qjs_to_bool(box.raw, ref)
      }
      if qjs_is_number(ref) {
        let d = qjs_to_float64(box.raw, ref)
        if d.isFinite && d.rounded(.towardZero) == d && d >= Double(Int.min)
          && d <= Double(Int.max) && !(d == 0 && d.sign == .minus)
        {
          return Int(d)
        }
        return d
      }
      if qjs_is_string(ref) {
        return jsStringFromRaw(box.raw, ref)
      }
      if qjs_is_date(ref) {
        let ms = qjs_to_float64(box.raw, ref)
        return ms.isFinite ? Date(timeIntervalSince1970: ms / 1000.0) : nil
      }
      if qjs_is_array(ref) {
        if depth >= 64 { return [Any]() }
        return convertArrayToSwiftLocked(ref, in: box, depth: depth + 1)
      }
      if qjs_is_object(ref) {
        if depth >= 64 { return [String: Any]() }
        var dict: [String: Any] = [:]
        var propKeys = QJSPropertyKeys(keys: nil, count: 0)
        if qjs_get_own_property_names(box.raw, ref, &propKeys) {
          defer { qjs_free_property_names(&propKeys) }
          if let keysPtr = propKeys.keys {
            for i in 0..<Int(propKeys.count) {
              guard let keyC = keysPtr[i] else { continue }
              let key = String(cString: keyC)
              let propVal = qjs_get_property_str(box.raw, ref, keyC)
              defer { qjs_value_free(box.raw, propVal) }
              if let propVal, !qjs_is_exception(propVal) {
                if let converted = convertRawToSwiftLocked(propVal, in: box, depth: depth + 1) {
                  dict[key] = converted
                }
              } else if qjs_has_exception(box.raw) {
                let exc = qjs_get_exception(box.raw)
                qjs_value_free(box.raw, exc)
              }
            }
          }
        }
        return dict
      }
      return nil
    }

    private func convertArrayToSwiftLocked(
      _ ref: QJSValueRef,
      in box: QJSContextBox,
      depth: Int
    ) -> [Any] {
      let length = max(0, qjs_get_length(box.raw, ref))
      var result: [Any] = []
      result.reserveCapacity(Int(min(length, 1024)))
      for i in 0..<UInt32(clamping: length) {
        let elem = qjs_get_property_uint32(box.raw, ref, i)
        defer { qjs_value_free(box.raw, elem) }
        if let elem, !qjs_is_exception(elem) {
          result.append(convertRawToSwiftLocked(elem, in: box, depth: depth + 1) ?? NSNull())
        } else {
          if qjs_has_exception(box.raw) {
            let exc = qjs_get_exception(box.raw)
            qjs_value_free(box.raw, exc)
          }
          result.append(NSNull())
        }
      }
      return result
    }

    private func convertObjectToDictionaryLocked(
      _ ref: QJSValueRef,
      in box: QJSContextBox,
      depth: Int
    ) -> [AnyHashable: Any] {
      var dict: [AnyHashable: Any] = [:]
      var propKeys = QJSPropertyKeys(keys: nil, count: 0)
      if qjs_get_own_property_names(box.raw, ref, &propKeys) {
        defer { qjs_free_property_names(&propKeys) }
        if let keysPtr = propKeys.keys {
          for i in 0..<Int(propKeys.count) {
            guard let keyC = keysPtr[i] else { continue }
            let key = String(cString: keyC)
            let propVal = qjs_get_property_str(box.raw, ref, keyC)
            defer { qjs_value_free(box.raw, propVal) }
            if let propVal, !qjs_is_exception(propVal) {
              if let converted = convertRawToSwiftLocked(propVal, in: box, depth: depth + 1) {
                dict[key] = converted
              }
            } else if qjs_has_exception(box.raw) {
              let exc = qjs_get_exception(box.raw)
              qjs_value_free(box.raw, exc)
            }
          }
        }
      }
      return dict
    }

    // MARK: Property & Indexed Access

    private static func keyToIndexOrString(_ key: Any?) -> (index: UInt32?, string: String) {
      guard let unwrapped = unwrapOptional(key) else {
        return (nil, "undefined")
      }
      if let s = unwrapped as? String {
        return (nil, s)
      }
      if let ns = unwrapped as? NSString {
        return (nil, String(ns))
      }
      if let i = unwrapped as? Int, i >= 0, i <= Int(UInt32.max) {
        return (UInt32(i), String(i))
      }
      if let i32 = unwrapped as? Int32, i32 >= 0 {
        return (UInt32(i32), String(i32))
      }
      if let u32 = unwrapped as? UInt32 {
        return (u32, String(u32))
      }
      if let num = unwrapped as? NSNumber {
        let i = num.int64Value
        if Double(i) == num.doubleValue && i >= 0 && i <= Int64(UInt32.max) {
          return (UInt32(i), String(i))
        }
      }
      return (nil, String(describing: unwrapped))
    }

    public func objectForKeyedSubscript(_ key: Any!) -> JSValue! {
      guard let raw, let contextBox else { return JSValue() }
      let parsed = Self.keyToIndexOrString(key)
      let resultRef: QJSValueRef? = contextBox.runtime.withExecutionScope {
        let propRef: QJSValueRef?
        if let idx = parsed.index {
          propRef = qjs_get_property_uint32(contextBox.raw, raw, idx)
        } else {
          propRef = parsed.string.withCString { cKey in
            qjs_get_property_str(contextBox.raw, raw, cKey)
          }
        }
        if let propRef, qjs_is_exception(propRef) {
          qjs_value_free(contextBox.raw, propRef)
          if let exc = qjs_get_exception(contextBox.raw) {
            ownerContext?.reportRawExceptionLocked(exc) ?? qjs_value_free(contextBox.raw, exc)
          }
          return qjs_new_undefined()
        }
        return propRef ?? qjs_new_undefined()
      }
      return JSValue(internalContextBox: contextBox, owner: ownerContext, raw: resultRef)
    }

    public func setObject(_ object: Any!, forKeyedSubscript key: Any!) {
      guard let raw, let contextBox else { return }
      let parsed = Self.keyToIndexOrString(key)
      contextBox.runtime.withExecutionScope {
        let jsVal = makeJSValue(
          from: object,
          in: contextBox,
          owner: ownerContext,
          functionName: parsed.string
        )
        defer { qjs_value_free(contextBox.raw, jsVal) }
        let rc: Int32
        if let idx = parsed.index {
          rc = qjs_set_property_uint32(contextBox.raw, raw, idx, jsVal)
        } else {
          rc = parsed.string.withCString { cKey in
            qjs_set_property_str(contextBox.raw, raw, cKey, jsVal)
          }
        }
        if rc < 0, let exc = qjs_get_exception(contextBox.raw) {
          ownerContext?.reportRawExceptionLocked(exc) ?? qjs_value_free(contextBox.raw, exc)
        }
      }
    }

    public func atIndex(_ index: Int) -> JSValue! {
      objectForKeyedSubscript(index)
    }

    public func setValue(_ value: Any!, at index: Int) {
      setObject(value, forKeyedSubscript: index)
    }

    public func hasProperty(_ property: String!) -> Bool {
      guard let raw, let contextBox, let property else { return false }
      return contextBox.runtime.withLocked {
        property.withCString { qjs_has_property_str(contextBox.raw, raw, $0) }
      }
    }

    @discardableResult
    public func deleteProperty(_ property: String!) -> Bool {
      guard let raw, let contextBox, let property else { return false }
      return contextBox.runtime.withLocked {
        property.withCString { qjs_delete_property_str(contextBox.raw, raw, $0) }
      }
    }

    // MARK: Invocation

    @discardableResult
    public func call(withArguments arguments: [Any]!) -> JSValue! {
      guard let raw, let contextBox else { return JSValue() }
      let args = arguments ?? []
      let resultRef: QJSValueRef? = contextBox.runtime.withExecutionScope {
        let jsArgs: [QJSValueRef?] = args.map {
          makeJSValue(from: $0, in: contextBox, owner: ownerContext)
        }
        defer {
          for arg in jsArgs {
            qjs_value_free(contextBox.raw, arg)
          }
        }
        let res = jsArgs.withUnsafeBufferPointer { buf in
          qjs_call(contextBox.raw, raw, nil, Int32(jsArgs.count), buf.baseAddress)
        }
        if let res, qjs_is_exception(res) {
          qjs_value_free(contextBox.raw, res)
          if let exc = qjs_get_exception(contextBox.raw) {
            ownerContext?.reportRawExceptionLocked(exc) ?? qjs_value_free(contextBox.raw, exc)
          }
          return qjs_new_undefined()
        }
        return res ?? qjs_new_undefined()
      }
      return JSValue(internalContextBox: contextBox, owner: ownerContext, raw: resultRef)
    }

    @discardableResult
    public func invokeMethod(_ method: String!, withArguments arguments: [Any]!) -> JSValue! {
      guard let raw, let contextBox, let method else { return JSValue() }
      let args = arguments ?? []
      let resultRef: QJSValueRef? = contextBox.runtime.withExecutionScope {
        let jsArgs: [QJSValueRef?] = args.map {
          makeJSValue(from: $0, in: contextBox, owner: ownerContext)
        }
        defer {
          for arg in jsArgs {
            qjs_value_free(contextBox.raw, arg)
          }
        }
        let res = method.withCString { cMethod in
          jsArgs.withUnsafeBufferPointer { buf in
            qjs_invoke(contextBox.raw, raw, cMethod, Int32(jsArgs.count), buf.baseAddress)
          }
        }
        if let res, qjs_is_exception(res) {
          qjs_value_free(contextBox.raw, res)
          if let exc = qjs_get_exception(contextBox.raw) {
            ownerContext?.reportRawExceptionLocked(exc) ?? qjs_value_free(contextBox.raw, exc)
          }
          return qjs_new_undefined()
        }
        return res ?? qjs_new_undefined()
      }
      return JSValue(internalContextBox: contextBox, owner: ownerContext, raw: resultRef)
    }

    @discardableResult
    public func construct(withArguments arguments: [Any]!) -> JSValue! {
      guard let raw, let contextBox else { return JSValue() }
      let args = arguments ?? []
      let resultRef: QJSValueRef? = contextBox.runtime.withExecutionScope {
        let jsArgs: [QJSValueRef?] = args.map {
          makeJSValue(from: $0, in: contextBox, owner: ownerContext)
        }
        defer {
          for arg in jsArgs {
            qjs_value_free(contextBox.raw, arg)
          }
        }
        let res = jsArgs.withUnsafeBufferPointer { buf in
          qjs_call_constructor(contextBox.raw, raw, Int32(jsArgs.count), buf.baseAddress)
        }
        if let res, qjs_is_exception(res) {
          qjs_value_free(contextBox.raw, res)
          if let exc = qjs_get_exception(contextBox.raw) {
            ownerContext?.reportRawExceptionLocked(exc) ?? qjs_value_free(contextBox.raw, exc)
          }
          return qjs_new_undefined()
        }
        return res ?? qjs_new_undefined()
      }
      return JSValue(internalContextBox: contextBox, owner: ownerContext, raw: resultRef)
    }
  }

  open class JSContext: @unchecked Sendable {
    public let virtualMachine: JSVirtualMachine!
    internal let contextBox: QJSContextBox
    private var rawException: QJSValueRef?
    public var exceptionHandler: ((JSContext?, JSValue?) -> Void)?
    public var name: String?

    public var exception: JSValue? {
      get {
        contextBox.runtime.withLocked {
          guard let rawException else { return nil }
          let dup = qjs_value_dup(contextBox.raw, rawException)
          return JSValue(internalContextBox: contextBox, owner: self, raw: dup)
        }
      }
      set {
        contextBox.runtime.withLocked {
          if let old = rawException {
            qjs_value_free(contextBox.raw, old)
            rawException = nil
          }
          if let newValue, let newRaw = newValue.raw,
            newValue.contextBox?.runtime === contextBox.runtime
          {
            rawException = qjs_value_dup(contextBox.raw, newRaw)
          }
        }
      }
    }

    public var globalObject: JSValue! {
      let ref = contextBox.runtime.withLocked {
        qjs_get_global_object(contextBox.raw)
      }
      return JSValue(internalContextBox: contextBox, owner: self, raw: ref)
    }

    public convenience init!() {
      self.init(virtualMachine: JSVirtualMachine())
    }

    public init!(virtualMachine: JSVirtualMachine!) {
      let vm = virtualMachine ?? JSVirtualMachine()
      guard let box = QJSContextBox(runtime: vm.runtimeBox) else {
        return nil
      }
      self.virtualMachine = vm
      self.contextBox = box
      vm.runtimeBox.register(context: self, rawCtx: box.raw)
    }

    deinit {
      contextBox.runtime.withLocked {
        contextBox.runtime.unregister(rawCtx: contextBox.raw)
        if let exc = rawException {
          qjs_value_free(contextBox.raw, exc)
          rawException = nil
        }
      }
    }

    public class func current() -> JSContext? {
      JSCallFrameStack.current?.context
    }

    public class func currentThis() -> JSValue? {
      JSCallFrameStack.current?.thisValue
    }

    public class func currentArguments() -> [Any]? {
      JSCallFrameStack.current?.arguments
    }

    /// Takes ownership of `excRef` under `contextBox.runtime.lock`, updates
    /// `self.exception`, and dispatches `exceptionHandler` if installed.
    internal func reportRawExceptionLocked(_ excRef: QJSValueRef) {
      if let old = rawException {
        qjs_value_free(contextBox.raw, old)
      }
      rawException = excRef
      let handler = exceptionHandler
      if let handler {
        let dup = qjs_value_dup(contextBox.raw, excRef)
        let excValue = JSValue(internalContextBox: contextBox, owner: self, raw: dup)
        handler(self, excValue)
      }
    }

    @discardableResult
    public func evaluateScript(_ script: String!, withSourceURL sourceURL: URL? = nil) -> JSValue! {
      guard let script else {
        return JSValue(undefinedIn: self)
      }
      let filename: String
      if let sourceURL {
        filename = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
      } else {
        filename = "<eval>"
      }

      var utf8 = Array(script.utf8)
      let byteLen = utf8.count
      utf8.append(0)

      let resultRef: QJSValueRef? = contextBox.runtime.withExecutionScope {
        let res = filename.withCString { cFilename in
          utf8.withUnsafeBytes { buf -> QJSValueRef? in
            let ptr = buf.baseAddress?.assumingMemoryBound(to: CChar.self)
            return qjs_eval(contextBox.raw, ptr, byteLen, cFilename)
          }
        }
        if let res, qjs_is_exception(res) {
          qjs_value_free(contextBox.raw, res)
          if let exc = qjs_get_exception(contextBox.raw) {
            reportRawExceptionLocked(exc)
          }
          return qjs_new_undefined()
        }
        return res ?? qjs_new_undefined()
      }

      return JSValue(internalContextBox: contextBox, owner: self, raw: resultRef)
    }

    public func setObject(_ object: Any!, forKeyedSubscript key: Any!) {
      globalObject.setObject(object, forKeyedSubscript: key)
    }

    public func objectForKeyedSubscript(_ key: Any!) -> JSValue! {
      globalObject.objectForKeyedSubscript(key)
    }

    public subscript(_ key: Any!) -> JSValue! {
      get { objectForKeyedSubscript(key) }
      set { setObject(newValue, forKeyedSubscript: key) }
    }
  }
#endif
