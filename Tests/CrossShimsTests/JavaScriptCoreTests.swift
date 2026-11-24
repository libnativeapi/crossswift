#if !os(macOS)
  import Foundation
  import JavaScriptCore
  import Testing

  @Suite("JavaScriptCore")
  struct JavaScriptCoreTests {
    @Test("Evaluates primitives, UTF-8 strings, and type predicates")
    func evaluatePrimitivesAndPredicates() {
      let context = JSContext()!

      let undef = context.evaluateScript("undefined")!
      #expect(undef.isUndefined)
      #expect(!undef.isNull)
      #expect(undef.toString() == "undefined")
      #expect(undef.toObject() == nil)

      let nullVal = context.evaluateScript("null")!
      #expect(nullVal.isNull)
      #expect(!nullVal.isUndefined)
      #expect(!nullVal.isObject)
      #expect(nullVal.toString() == "null")
      #expect(nullVal.toObject() is NSNull)

      let boolVal = context.evaluateScript("true")!
      #expect(boolVal.isBoolean)
      #expect(boolVal.toBool() == true)
      #expect(boolVal.toObject() as? Bool == true)

      let intVal = context.evaluateScript("40 + 2")!
      #expect(intVal.isNumber)
      #expect(intVal.toInt32() == 42)
      #expect(intVal.toDouble() == 42.0)
      #expect(intVal.toObject() as? Int == 42)

      let floatVal = context.evaluateScript("3.25")!
      #expect(floatVal.isNumber)
      #expect(floatVal.toDouble() == 3.25)
      #expect(floatVal.toObject() as? Double == 3.25)

      let strVal = context.evaluateScript("'hello 世界 🚀'")!
      #expect(strVal.isString)
      #expect(strVal.toString() == "hello 世界 🚀")
      #expect(strVal.toObject() as? String == "hello 世界 🚀")

      let arrVal = context.evaluateScript("[1, 'two', true, null]")!
      #expect(arrVal.isObject)
      #expect(arrVal.isArray)
      let arr = arrVal.toArray()!
      #expect(arr.count == 4)
      #expect(arr[0] as? Int == 1)
      #expect(arr[1] as? String == "two")
      #expect(arr[2] as? Bool == true)
      #expect(arr[3] is NSNull)
    }

    @Test("Reports thrown errors and syntax errors with sourceURL filename in stack")
    func exceptionsAndStackSourceURL() {
      let context = JSContext()!
      var handledMessage: String?
      var handledStack: String?

      context.exceptionHandler = { _, exc in
        handledMessage = exc?.toString()
        handledStack = exc?.objectForKeyedSubscript("stack")?.toString()
      }

      let url = URL(fileURLWithPath: "/virtual/extensions/my-command.js")
      let result = context.evaluateScript(
        """
        function innerBoom() {
          throw new Error("kaboom");
        }
        function outerBoom() {
          return innerBoom();
        }
        outerBoom();
        """,
        withSourceURL: url
      )!

      #expect(result.isUndefined)
      #expect(handledMessage == "Error: kaboom")
      #expect(handledStack != nil)
      #expect(handledStack?.contains("innerBoom") == true)
      #expect(handledStack?.contains("outerBoom") == true)
      #expect(handledStack?.contains("my-command.js") == true)

      // context.exception is also populated and can be cleared.
      #expect(context.exception?.toString() == "Error: kaboom")
      context.exception = nil
      #expect(context.exception == nil)

      // Syntax errors also trigger exceptionHandler with source URL.
      handledMessage = nil
      let badURL = URL(fileURLWithPath: "/virtual/broken-syntax.js")
      context.evaluateScript("function broken( {", withSourceURL: badURL)
      #expect(handledMessage?.contains("SyntaxError") == true)
    }

    @Test("Catches infinite recursion cleanly as RangeError")
    func stackOverflowBecomesJSException() {
      let context = JSContext()!
      var caught: String?
      context.exceptionHandler = { _, exc in
        caught = exc?.toString()
      }
      context.evaluateScript("function recurse() { return recurse(); } recurse();")
      #expect(caught?.contains("RangeError") == true || caught?.contains("InternalError") == true)
    }

    @Test("Round-trips nested objects, arrays, subscripts, and Swift types")
    func objectsArraysAndConversions() {
      let context = JSContext()!

      let obj = JSValue(newObjectIn: context)!
      obj.setObject("Alice", forKeyedSubscript: "name")
      obj.setObject("Engineer" as NSString, forKeyedSubscript: "role" as NSString)
      obj.setObject(Int(7), forKeyedSubscript: "intVal")
      obj.setObject(Int32(-12), forKeyedSubscript: "int32Val")
      obj.setObject(2.5 as Double, forKeyedSubscript: "doubleVal")
      obj.setObject(Float(1.5), forKeyedSubscript: "floatVal")
      obj.setObject(true, forKeyedSubscript: "active")
      obj.setObject(NSNull(), forKeyedSubscript: "empty")
      obj.setObject(nil, forKeyedSubscript: "missing")
      obj.setObject(["a", "b", "c"], forKeyedSubscript: "tags")
      obj.setObject(["nestedKey": 99], forKeyedSubscript: "meta")

      context.setObject(obj, forKeyedSubscript: "profile" as NSString)

      let check = context.evaluateScript(
        """
        ({
          summary: `${profile.name}:${profile.role}:${profile.intVal}:${profile.int32Val}:${profile.doubleVal}:${profile.floatVal}:${profile.active}:${profile.empty === null}:${profile.missing === undefined}:${profile.tags.join(',')}:${profile.meta.nestedKey}`,
          tagsCount: profile.tags.length
        })
        """
      )!
      #expect(
        check.objectForKeyedSubscript("summary")?.toString()
          == "Alice:Engineer:7:-12:2.5:1.5:true:true:true:a,b,c:99"
      )
      #expect(check.objectForKeyedSubscript("tagsCount")?.toInt32() == 3)

      // Integer subscripting on arrays
      let arr = context.evaluateScript("['zero', 'one', 'two']")!
      #expect(arr.objectForKeyedSubscript(1)?.toString() == "one")
      arr.setObject("ONE", forKeyedSubscript: 1)
      #expect(arr.objectForKeyedSubscript(1)?.toString() == "ONE")

      // toDictionary on nested JS object
      let dict = context.objectForKeyedSubscript("profile")!.toDictionary()!
      #expect(dict["name"] as? String == "Alice")
      #expect(dict["active"] as? Bool == true)
      #expect(dict["empty"] is NSNull)
      #expect((dict["meta"] as? [String: Any])?["nestedKey"] as? Int == 99)

      // Cyclic object does not infinite-loop in toDictionary/toObject
      let cyclic = context.evaluateScript("var c = { x: 1 }; c.self = c; c;")!
      let cyclicDict = cyclic.toDictionary()!
      #expect(cyclicDict["x"] as? Int == 1)
    }

    @Test("Bridges all Tinycast and general Swift closure signatures bidirectionally")
    func bidirectionalClosureBridging() throws {
      let context = JSContext()!
      let host = JSValue(newObjectIn: context)!

      var logEvents: [(String, String)] = []
      var finishedSessions: [String] = []
      var timerStarts: [(String, Double, Bool)] = []
      var invokeCalls: [(String, String, String, String)] = []

      let void1: (String) -> Void = { session in
        finishedSessions.append(session)
      }
      let void2: (String, String) -> Void = { level, msg in
        logEvents.append((level, msg))
      }
      let timerFn: (String, Double, Bool) -> Void = { id, ms, repeats in
        timerStarts.append((id, ms, repeats))
      }
      let syncFn: (String, String, String) -> String = { api, method, args in
        let escaped = args.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"ok":true,"value":"\#(api).\#(method):\#(escaped)"}"#
      }
      let invokeFn: (String, String, String, String) -> Void = { callId, api, method, args in
        invokeCalls.append((callId, api, method, args))
      }

      // General arities + @Sendable + JSContext.current()
      let zeroArg: () -> String = { "pong" }
      let addInts: (Int, Int) -> Int = { $0 + $1 }
      let scaleDouble: (Double, Double) -> Double = { $0 * $1 }
      let sendableFn: @Sendable (String) -> Bool = { $0 == "ok" }
      let contextAware: () -> String = {
        JSContext.current()?.objectForKeyedSubscript("marker")?.toString() ?? "none"
      }

      host.setObject(void1, forKeyedSubscript: "finished" as NSString)
      host.setObject(void2, forKeyedSubscript: "log" as NSString)
      host.setObject(timerFn, forKeyedSubscript: "startTimer" as NSString)
      host.setObject(syncFn, forKeyedSubscript: "invokeSync" as NSString)
      host.setObject(invokeFn, forKeyedSubscript: "invoke" as NSString)
      context.setObject(host, forKeyedSubscript: "__host" as NSString)

      context.setObject("from-global", forKeyedSubscript: "marker")
      context.setObject(zeroArg, forKeyedSubscript: "ping")
      context.setObject(addInts, forKeyedSubscript: "add")
      context.setObject(scaleDouble, forKeyedSubscript: "mul")
      context.setObject(sendableFn, forKeyedSubscript: "isOk")
      context.setObject(contextAware, forKeyedSubscript: "readMarker")

      let syncRes = context.evaluateScript(
        """
        __host.log("info", "booted");
        __host.finished("sess-1");
        __host.startTimer("t1", 125.5, true);
        __host.invoke("c1", "feedback", "showHUD", '["hi"]');
        JSON.stringify({
          sync: JSON.parse(__host.invokeSync("fs", "read", '["a.txt"]')).value,
          ping: ping(),
          sum: add(19, 23),
          prod: mul(2.5, 4.0),
          ok1: isOk("ok"),
          ok2: isOk("no"),
          marker: readMarker()
        });
        """
      )!.toString()!

      #expect(context.exception == nil, "Unexpected JS exception: \(context.exception?.toString() ?? "")")
      #expect(logEvents.count == 1)
      #expect(logEvents[0].0 == "info")
      #expect(logEvents[0].1 == "booted")
      #expect(finishedSessions == ["sess-1"])
      #expect(timerStarts.count == 1)
      #expect(timerStarts[0].0 == "t1")
      #expect(timerStarts[0].1 == 125.5)
      #expect(timerStarts[0].2 == true)
      #expect(invokeCalls.count == 1)
      #expect(invokeCalls[0].0 == "c1")
      #expect(invokeCalls[0].1 == "feedback")
      #expect(invokeCalls[0].2 == "showHUD")
      #expect(invokeCalls[0].3 == #"["hi"]"#)

      let data = try #require(syncRes.data(using: .utf8))
      let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(parsed["sync"] as? String == #"fs.read:["a.txt"]"#)
      #expect(parsed["ping"] as? String == "pong")
      #expect(parsed["sum"] as? Int == 42)
      #expect(parsed["prod"] as? Double == 10.0)
      #expect(parsed["ok1"] as? Bool == true)
      #expect(parsed["ok2"] as? Bool == false)
      #expect(parsed["marker"] as? String == "from-global")

      // Swift calling JS functions via call(withArguments:) and invokeMethod(_:withArguments:)
      let fn = context.evaluateScript("(function(a, b) { return a + '-' + b; })")!
      #expect(fn.call(withArguments: ["hello", 99])?.toString() == "hello-99")

      let calc = context.evaluateScript("({ base: 10, add(x) { return this.base + x; } })")!
      #expect(calc.invokeMethod("add", withArguments: [32])?.toInt32() == 42)
    }

    @Test("Handles re-entrant evaluateScript inside a host callback (__tinycastCompile pattern)")
    func reentrantEvaluateScriptFromCallback() {
      let context = JSContext()!
      var uncaught: [String] = []
      context.exceptionHandler = { _, exc in
        uncaught.append(exc?.toString() ?? "unknown")
      }

      let compile: (String, String) -> JSValue? = { [weak context] code, filename in
        guard let context else { return nil }
        let wrapped = "(function (exports, require, module, __filename, __dirname) {\n\(code)\n})"
        return context.evaluateScript(wrapped, withSourceURL: URL(fileURLWithPath: filename))
      }
      context.setObject(compile, forKeyedSubscript: "__tinycastCompile" as NSString)

      let output = context.evaluateScript(
        """
        function runCJS(code, file) {
          const mod = { exports: {} };
          const factory = globalThis.__tinycastCompile(code, file);
          factory(mod.exports, () => ({}), mod, file, "/ext");
          return mod.exports.default();
        }
        runCJS('module.exports.default = () => "compiled-ok:" + __filename;', '/ext/cmd.js');
        """
      )!.toString()!

      #expect(uncaught.isEmpty)
      #expect(output == "compiled-ok:/ext/cmd.js")

      // Verify stack trace from inside a dynamically compiled module includes its filename.
      let stackText = context.evaluateScript(
        """
        (function() {
          const mod = { exports: {} };
          const factory = globalThis.__tinycastCompile(
            'module.exports = function failHere() { throw new Error("module-boom"); };',
            '/ext/failing-module.js'
          );
          factory(mod.exports, () => ({}), mod, '/ext/failing-module.js', '/ext');
          try {
            mod.exports();
          } catch (e) {
            return e.message + "|" + e.stack;
          }
          return "no-error";
        })()
        """
      )!.toString()!

      #expect(stackText.contains("module-boom"))
      #expect(stackText.contains("failHere"))
      #expect(stackText.contains("failing-module.js"))
    }

    @Test("Drains Promise microtasks automatically after evaluateScript and invokeMethod")
    func promiseMicrotaskDraining() {
      let context = JSContext()!
      var resolvedValue: String?
      let onDone: (String) -> Void = { resolvedValue = $0 }
      context.setObject(onDone, forKeyedSubscript: "onDone")

      context.evaluateScript(
        """
        Promise.resolve("async-value")
          .then(v => v + "-chained")
          .then(v => onDone(v));
        """
      )
      #expect(resolvedValue == "async-value-chained")

      resolvedValue = nil
      let runner = context.evaluateScript(
        """
        ({
          run(x) {
            Promise.resolve(x).then(v => onDone("from-method:" + v));
          }
        })
        """
      )!
      runner.invokeMethod("run", withArguments: ["42"])
      #expect(resolvedValue == "from-method:42")
    }

    @Test("Cleanly tears down contexts on background DispatchQueue without leaks or UAF")
    func contextTeardownAndBackgroundQueueLifetime() {
      final class ClosureToken: @unchecked Sendable {
        let onDeinit: () -> Void
        init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
        deinit { onDeinit() }
      }
      final class CounterBox: @unchecked Sendable {
        let lock = NSLock()
        var count = 0
        func increment() {
          lock.lock()
          count += 1
          lock.unlock()
        }
        func read() -> Int {
          lock.lock()
          defer { lock.unlock() }
          return count
        }
      }
      final class ContextSlot: @unchecked Sendable {
        var context: JSContext?
      }

      let queue = DispatchQueue(label: "dev.crossswift.jsc.test.queue")
      let group = DispatchGroup()
      let counter = CounterBox()

      // Run multiple create -> eval -> throw -> teardown cycles across serial queue hops.
      for iteration in 0..<5 {
        group.enter()
        let slot = ContextSlot()
        queue.async {
          let c = JSContext()!
          let token = ClosureToken {
            counter.increment()
          }
          let fn: (String) -> String = { input in
            _ = token
            return "\(iteration):\(input)"
          }
          c.setObject(fn, forKeyedSubscript: "echo")
          slot.context = c
        }
        queue.async {
          let res = slot.context?.evaluateScript("echo('hi')")?.toString()
          #expect(res == "\(iteration):hi")
          slot.context?.evaluateScript("throw new Error('teardown-exc')")
          #expect(slot.context?.exception?.toString() == "Error: teardown-exc")
        }
        queue.async {
          slot.context = nil
          group.leave()
        }
      }

      let waitResult = group.wait(timeout: .now() + 10)
      #expect(waitResult == .success)
      #expect(counter.read() == 5)

      // Verify JSValue outliving its JSContext reference remains valid and frees cleanly.
      var survivingValue: JSValue?
      do {
        let ephemeral = JSContext()!
        survivingValue = ephemeral.evaluateScript("({ label: 'survived' })")
      }
      #expect(survivingValue?.objectForKeyedSubscript("label")?.toString() == "survived")
      survivingValue = nil

      // Verify two contexts sharing one JSVirtualMachine are isolated and tear down cleanly.
      let vm = JSVirtualMachine()
      var c1: JSContext? = JSContext(virtualMachine: vm)
      var c2: JSContext? = JSContext(virtualMachine: vm)
      c1?.evaluateScript("var sharedName = 'ctx1';")
      c2?.evaluateScript("var sharedName = 'ctx2';")
      #expect(c1?.objectForKeyedSubscript("sharedName")?.toString() == "ctx1")
      #expect(c2?.objectForKeyedSubscript("sharedName")?.toString() == "ctx2")
      c1 = nil
      #expect(c2?.objectForKeyedSubscript("sharedName")?.toString() == "ctx2")
      c2 = nil
    }

    @Test("Exercises Tinycast RaycastRuntime host protocol end-to-end")
    func raycastRuntimeProtocolSmokeTest() {
      final class Harness: @unchecked Sendable {
        let queue = DispatchQueue(label: "dev.crossswift.jsc.raycast.protocol")
        var context: JSContext?
        var timers: [String: DispatchWorkItem] = [:]
        var renders: [(String, String)] = []
        var failures: [(String, String)] = []
        var finished: [String] = []
        var logs: [(String, String)] = []
        var asyncInvokes: [(String, String, String, String)] = []

        func installHost(in ctx: JSContext) {
          let host = JSValue(newObjectIn: ctx)!
          let log: (String, String) -> Void = { [weak self] level, msg in
            self?.logs.append((level, msg))
          }
          let render: (String, String) -> Void = { [weak self] session, json in
            self?.renders.append((session, json))
          }
          let failed: (String, String) -> Void = { [weak self] session, msg in
            self?.failures.append((session, msg))
          }
          let navigation: (String, String) -> Void = { _, _ in }
          let finishedFn: (String) -> Void = { [weak self] session in
            self?.finished.append(session)
          }
          let fieldCommand: (String, String) -> Void = { _, _ in }
          let invoke: (String, String, String, String) -> Void = {
            [weak self] callId, api, method, argsJSON in
            self?.asyncInvokes.append((callId, api, method, argsJSON))
          }
          let invokeSync: (String, String, String) -> String = { api, method, argsJSON in
            let escaped = argsJSON.replacingOccurrences(of: "\"", with: "\\\"")
            return #"{"ok":true,"value":"\#(api).\#(method):\#(escaped)"}"#
          }
          let startTimer: (String, Double, Bool) -> Void = { [weak self] id, ms, _ in
            guard let self else { return }
            let interval = max(ms, 0) / 1000.0
            let work = DispatchWorkItem { [weak self] in
              guard let self else { return }
              self.timers[id] = nil
              _ = self.context?.objectForKeyedSubscript("__tinycast")?
                .invokeMethod("fireTimer", withArguments: [id])
            }
            self.timers[id]?.cancel()
            self.timers[id] = work
            self.queue.asyncAfter(deadline: .now() + interval, execute: work)
          }
          let clearTimer: (String) -> Void = { [weak self] id in
            self?.timers[id]?.cancel()
            self?.timers[id] = nil
          }

          host.setObject(log, forKeyedSubscript: "log" as NSString)
          host.setObject(render, forKeyedSubscript: "render" as NSString)
          host.setObject(failed, forKeyedSubscript: "failed" as NSString)
          host.setObject(navigation, forKeyedSubscript: "navigationDepthChanged" as NSString)
          host.setObject(finishedFn, forKeyedSubscript: "finished" as NSString)
          host.setObject(fieldCommand, forKeyedSubscript: "fieldCommand" as NSString)
          host.setObject(invoke, forKeyedSubscript: "invoke" as NSString)
          host.setObject(invokeSync, forKeyedSubscript: "invokeSync" as NSString)
          host.setObject(startTimer, forKeyedSubscript: "startTimer" as NSString)
          host.setObject(clearTimer, forKeyedSubscript: "clearTimer" as NSString)
          ctx.setObject(host, forKeyedSubscript: "__tinycastHost" as NSString)

          let compile: (String, String) -> JSValue? = { [weak self] code, filename in
            guard let context = self?.context else { return nil }
            let wrapped =
              "(function (exports, require, module, __filename, __dirname) {\n\(code)\n})"
            return context.evaluateScript(wrapped, withSourceURL: URL(fileURLWithPath: filename))
          }
          ctx.setObject(compile, forKeyedSubscript: "__tinycastCompile" as NSString)
        }

        func shutdown() {
          for t in timers.values { t.cancel() }
          timers.removeAll()
          context = nil
        }
      }

      // 1. Self-contained RaycastRuntime protocol test (always runs standalone).
      let miniRuntimeJS = """
        (function() {
          const host = globalThis.__tinycastHost;
          const pending = new Map();
          const timerCbs = new Map();
          let nextCall = 1;
          let nextTimer = 1;
          globalThis.setTimeout = (fn, ms) => {
            const id = String(nextTimer++);
            timerCbs.set(id, fn);
            host.startTimer(id, Number(ms) || 0, false);
            return id;
          };
          globalThis.__tinycast = {
            boot(cfg) {
              host.log("info", "boot:" + JSON.parse(cfg).env);
              return "ok";
            },
            start(session, code, file, dir, mode) {
              const mod = { exports: {} };
              const factory = globalThis.__tinycastCompile(code, file);
              const api = {
                invokeAsync(a, m, args) {
                  return new Promise((resolve, reject) => {
                    const id = String(nextCall++);
                    pending.set(id, { resolve, reject });
                    host.invoke(id, a, m, JSON.stringify(args));
                  });
                },
                invokeSync(a, m, args) {
                  return JSON.parse(host.invokeSync(a, m, JSON.stringify(args))).value;
                }
              };
              factory(mod.exports, () => api, mod, file, dir);
              if (mode === "no-view") {
                Promise.resolve(mod.exports.default()).then(
                  () => host.finished(session),
                  (e) => host.failed(session, String(e))
                );
              } else {
                host.render(session, JSON.stringify(mod.exports.default()));
              }
              return "ok";
            },
            dispatch(session, handler, payload) {
              host.render(session, JSON.stringify({ dispatched: handler, payload: JSON.parse(payload) }));
              return "1";
            },
            settle(callId, ok, payload) {
              const entry = pending.get(String(callId));
              if (!entry) return;
              pending.delete(String(callId));
              if (ok) entry.resolve(payload ? JSON.parse(payload) : undefined);
              else entry.reject(new Error(payload));
            },
            fireTimer(id) {
              const fn = timerCbs.get(String(id));
              timerCbs.delete(String(id));
              if (fn) fn();
            },
            stop() { return "ok"; }
          };
        })();
        """

      let harness = Harness()
      let doneGroup = DispatchGroup()
      doneGroup.enter()

      harness.queue.async {
        let ctx = JSContext()!
        var bootErr: String?
        ctx.exceptionHandler = { _, exc in
          bootErr = exc?.toString()
        }
        harness.installHost(in: ctx)
        ctx.evaluateScript(miniRuntimeJS, withSourceURL: URL(fileURLWithPath: "/mini-runtime.js"))
        #expect(bootErr == nil)
        harness.context = ctx

        let bootRes = ctx.objectForKeyedSubscript("__tinycast")?
          .invokeMethod("boot", withArguments: [#"{"env":"windows"}"#])
        #expect(bootRes?.toString() == "ok")

        let cmdCode = """
          const api = require('@raycast/api');
          module.exports.default = async function() {
            const syncVal = api.invokeSync('os', 'platform', []);
            const asyncVal = await api.invokeAsync('feedback', 'showHUD', [syncVal]);
            await new Promise(r => setTimeout(r, 10));
            __tinycastHost.log('info', 'done:' + asyncVal);
          };
          """
        _ = ctx.objectForKeyedSubscript("__tinycast")?
          .invokeMethod("start", withArguments: ["s1", cmdCode, "/ext/cmd.js", "/ext", "no-view"])

        #expect(harness.asyncInvokes.count == 1)
        let callId = harness.asyncInvokes[0].0
        _ = ctx.objectForKeyedSubscript("__tinycast")?
          .invokeMethod("settle", withArguments: [callId, true, #""settled-hud""#])

        // Wait briefly on the serial queue for the 10ms timer to fire and settle the promise.
        harness.queue.asyncAfter(deadline: .now() + 0.15) {
          _ = ctx.objectForKeyedSubscript("__tinycast")?
            .invokeMethod("dispatch", withArguments: ["s1", "onAction", #"["clicked"]"#])
          _ = ctx.objectForKeyedSubscript("__tinycast")?
            .invokeMethod("stop", withArguments: ["s1"])
          harness.shutdown()
          doneGroup.leave()
        }
      }

      #expect(doneGroup.wait(timeout: .now() + 5) == .success)
      #expect(harness.failures.isEmpty)
      #expect(harness.finished == ["s1"])
      #expect(harness.logs.contains { $0.1 == "boot:windows" })
      #expect(harness.logs.contains { $0.1 == "done:settled-hud" })
      #expect(harness.renders.count == 1)
      #expect(harness.renders[0].1.contains("onAction"))

      // 2. If Tinycast's real RaycastRuntime.generated.js is present in a sibling checkout,
      //    boot the real React + reconciler + @raycast/api bundle and render a List!
      let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      let candidatePaths = [
        packageRoot.deletingLastPathComponent()
          .appendingPathComponent("tinycast/Tinycast/Resources/RaycastRuntime.generated.js"),
        URL(fileURLWithPath: "E:/Projects/libnativeapi/tinycast/Tinycast/Resources/RaycastRuntime.generated.js"),
      ]
      if let realRuntimeURL = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
        let realSource = try? String(contentsOf: realRuntimeURL, encoding: .utf8)
      {
        let realHarness = Harness()
        let realGroup = DispatchGroup()
        realGroup.enter()

        realHarness.queue.async {
          let ctx = JSContext()!
          var bootError: String?
          ctx.exceptionHandler = { _, exc in
            let stack = exc?.objectForKeyedSubscript("stack")?.toString() ?? ""
            bootError = "\(exc?.toString() ?? "error")\n\(stack)"
          }
          realHarness.installHost(in: ctx)
          ctx.evaluateScript(realSource, withSourceURL: realRuntimeURL)
          #expect(bootError == nil, "Real RaycastRuntime boot error: \(bootError ?? "")")
          realHarness.context = ctx

          let bootResult = ctx.objectForKeyedSubscript("__tinycast")?
            .invokeMethod("boot", withArguments: [#"{"node":{}}"#])
          #expect(bootResult?.toString() == "ok")

          let listCommand = """
            const React = require("react");
            const { List } = require("@raycast/api");
            module.exports.default = function Command() {
              return React.createElement(
                List,
                { navigationTitle: "QuickJS Smoke" },
                React.createElement(List.Item, { id: "item-1", title: "Hello from QuickJS-ng" })
              );
            };
            """
          let launchCtx = #"{"extensionName":"smoke","commandName":"list","commandMode":"view","assetsPath":"/tmp","supportPath":"/tmp","isDarkAppearance":true}"#
          _ = ctx.objectForKeyedSubscript("__tinycast")?
            .invokeMethod(
              "start",
              withArguments: ["real-1", listCommand, "/tmp/list.js", "/tmp", "view", launchCtx]
            )

          realHarness.queue.asyncAfter(deadline: .now() + 0.15) {
            _ = ctx.objectForKeyedSubscript("__tinycast")?
              .invokeMethod("stop", withArguments: ["real-1"])
            realHarness.shutdown()
            realGroup.leave()
          }
        }

        #expect(realGroup.wait(timeout: .now() + 10) == .success)
        #expect(realHarness.failures.isEmpty, "Real RaycastRuntime failures: \(realHarness.failures)")
        #expect(!realHarness.renders.isEmpty, "Expected React reconciler to emit at least one render tree")
        #expect(realHarness.renders.last?.1.contains("Hello from QuickJS-ng") == true)
      }
    }
  }
#endif
