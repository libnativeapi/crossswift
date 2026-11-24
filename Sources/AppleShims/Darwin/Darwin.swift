@_exported import Foundation
@_exported import CDarwinShims
import CoreFoundation
#if os(Windows)
  import ucrt
  import CAppKitWindows
#elseif canImport(Glibc)
  @_exported import Glibc
#elseif canImport(Musl)
  @_exported import Musl
#endif

#if os(Linux)
  public typealias boolean_t = Int32
  public typealias attrgroup_t = UInt32
  public typealias u_short = UInt16

  public let F_SETNOSIGPIPE: Int32 = 73
  public let O_EVTONLY: Int32 = 0x8000

  public let UF_IMMUTABLE: Int32 = 0x00000002
  public let SF_IMMUTABLE: Int32 = 0x00020000
  public let SF_NOUNLINK: Int32 = 0x00100000
  public let SF_RESTRICTED: Int32 = 0x00080000
  public let SF_FIRMLINK: Int32 = 0x00800000
  public let XATTR_NOFOLLOW: Int32 = 0x0001
  #if canImport(Glibc)
    public let POSIX_SPAWN_SETSID: Int32 = 0x0400
    public let FNM_CASEFOLD: Int32 = 0x10

    // Linux Glibc exposes SOCK_STREAM as `__socket_type` and IFF_* as `Int`,
    // whereas Darwin and Musl expose them as `Int32`.
    public let SOCK_STREAM: Int32 = Int32(Glibc.SOCK_STREAM.rawValue)
    public let IFF_UP: Int32 = 0x1
    public let IFF_LOOPBACK: Int32 = 0x8
    public let IFF_RUNNING: Int32 = 0x40
  #endif

  #if canImport(Glibc)
    extension Glibc.sockaddr {
      public var sa_len: UInt8 {
        sa_family == UInt16(AF_INET6)
          ? UInt8(MemoryLayout<sockaddr_in6>.size)
          : UInt8(MemoryLayout<sockaddr_in>.size)
      }
    }

    extension Glibc.timeval {
      public init(tv_sec: Int, tv_usec: Int32) {
        self.init(tv_sec: tv_sec, tv_usec: Int(tv_usec))
      }
    }

    public func getloadavg(_ loadavg: UnsafeMutablePointer<Double>?, _ nelem: Int32) -> Int32 {
      guard let loadavg else { return -1 }
      return Glibc.getloadavg(loadavg, nelem)
    }

    extension Glibc.stat {
      public var st_flags: UInt32 { 0 }
      public var st_mtimespec: Glibc.timespec { st_mtim }
      public var st_atimespec: Glibc.timespec { st_atim }
      public var st_ctimespec: Glibc.timespec { st_ctim }
      public var st_birthtimespec: Glibc.timespec { st_ctim }
    }

    public func mach_absolute_time() -> UInt64 {
      var ts = Glibc.timespec()
      Glibc.clock_gettime(CLOCK_MONOTONIC, &ts)
      return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
    }
  #elseif canImport(Musl)
    extension Musl.sockaddr {
      public var sa_len: UInt8 {
        sa_family == UInt16(AF_INET6)
          ? UInt8(MemoryLayout<sockaddr_in6>.size)
          : UInt8(MemoryLayout<sockaddr_in>.size)
      }
    }

    extension Musl.timeval {
      public init(tv_sec: Int, tv_usec: Int32) {
        self.init(tv_sec: tv_sec, tv_usec: Int(tv_usec))
      }
    }

    public func getloadavg(_ loadavg: UnsafeMutablePointer<Double>?, _ nelem: Int32) -> Int32 {
      guard let loadavg, nelem > 0 else { return -1 }
      for i in 0..<Int(nelem) { loadavg[i] = 0 }
      return nelem
    }

    extension Musl.stat {
      public var st_flags: UInt32 { 0 }
      public var st_mtimespec: Musl.timespec { st_mtim }
      public var st_atimespec: Musl.timespec { st_atim }
      public var st_ctimespec: Musl.timespec { st_ctim }
      public var st_birthtimespec: Musl.timespec { st_ctim }
    }

    public func mach_absolute_time() -> UInt64 {
      var ts = Musl.timespec()
      Musl.clock_gettime(CLOCK_MONOTONIC, &ts)
      return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
    }
  #endif

  public func sysctlbyname(
    _ name: UnsafePointer<CChar>,
    _ oldp: UnsafeMutableRawPointer?,
    _ oldlenp: UnsafeMutablePointer<Int>?,
    _ newp: UnsafeMutableRawPointer?,
    _ newlen: Int
  ) -> Int32 { -1 }

  @discardableResult
  public func getxattr(
    _ path: UnsafePointer<CChar>?,
    _ name: UnsafePointer<CChar>?,
    _ value: UnsafeMutableRawPointer?,
    _ size: Int,
    _ position: UInt32,
    _ options: Int32
  ) -> Int { -1 }

  @discardableResult
  public func removexattr(
    _ path: UnsafePointer<CChar>?,
    _ name: UnsafePointer<CChar>?,
    _ options: Int32
  ) -> Int32 { -1 }

  // Darwin declares posix_spawnattr_t / posix_spawn_file_actions_t as opaque pointers
  // (so Swift code holds `posix_spawnattr_t?`), while Linux Glibc/Musl declare them as C structs.
  @discardableResult
  public func posix_spawnattr_init(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>) -> Int32 {
    var raw = posix_spawnattr_t()
    #if canImport(Glibc)
      let rc = Glibc.posix_spawnattr_init(&raw)
    #else
      let rc = Musl.posix_spawnattr_init(&raw)
    #endif
    attr.pointee = raw
    return rc
  }

  @discardableResult
  public func posix_spawnattr_destroy(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>) -> Int32 {
    guard var raw = attr.pointee else { return 0 }
    #if canImport(Glibc)
      let rc = Glibc.posix_spawnattr_destroy(&raw)
    #else
      let rc = Musl.posix_spawnattr_destroy(&raw)
    #endif
    attr.pointee = nil
    return rc
  }

  @discardableResult
  public func posix_spawnattr_setflags(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ flags: Int16) -> Int32 {
    guard var raw = attr.pointee else { return -1 }
    #if canImport(Glibc)
      let rc = Glibc.posix_spawnattr_setflags(&raw, flags)
    #else
      let rc = Musl.posix_spawnattr_setflags(&raw, flags)
    #endif
    attr.pointee = raw
    return rc
  }

  @discardableResult
  public func posix_spawn_file_actions_init(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>) -> Int32 {
    var raw = posix_spawn_file_actions_t()
    #if canImport(Glibc)
      let rc = Glibc.posix_spawn_file_actions_init(&raw)
    #else
      let rc = Musl.posix_spawn_file_actions_init(&raw)
    #endif
    actions.pointee = raw
    return rc
  }

  @discardableResult
  public func posix_spawn_file_actions_destroy(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>) -> Int32 {
    guard var raw = actions.pointee else { return 0 }
    #if canImport(Glibc)
      let rc = Glibc.posix_spawn_file_actions_destroy(&raw)
    #else
      let rc = Musl.posix_spawn_file_actions_destroy(&raw)
    #endif
    actions.pointee = nil
    return rc
  }

  @discardableResult
  public func posix_spawn_file_actions_addchdir(
    _ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>,
    _ path: UnsafePointer<CChar>?
  ) -> Int32 {
    #if canImport(Glibc)
      guard var raw = actions.pointee, let path else { return 0 }
      let rc = Glibc.posix_spawn_file_actions_addchdir_np(&raw, path)
      actions.pointee = raw
      return rc
    #else
      return ENOTSUP
    #endif
  }

  @discardableResult
  public func posix_spawn_file_actions_adddup2(
    _ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>,
    _ fildes: Int32,
    _ newfildes: Int32
  ) -> Int32 {
    guard var raw = actions.pointee else { return -1 }
    #if canImport(Glibc)
      let rc = Glibc.posix_spawn_file_actions_adddup2(&raw, fildes, newfildes)
    #else
      let rc = Musl.posix_spawn_file_actions_adddup2(&raw, fildes, newfildes)
    #endif
    actions.pointee = raw
    return rc
  }

  @discardableResult
  public func posix_spawn_file_actions_addclose(
    _ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>,
    _ fildes: Int32
  ) -> Int32 {
    guard var raw = actions.pointee else { return -1 }
    #if canImport(Glibc)
      let rc = Glibc.posix_spawn_file_actions_addclose(&raw, fildes)
    #else
      let rc = Musl.posix_spawn_file_actions_addclose(&raw, fildes)
    #endif
    actions.pointee = raw
    return rc
  }

  public func posix_spawn(
    _ pid: UnsafeMutablePointer<pid_t>?,
    _ path: UnsafePointer<CChar>?,
    _ file_actions: UnsafePointer<posix_spawn_file_actions_t?>?,
    _ attrp: UnsafePointer<posix_spawnattr_t?>?,
    _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?,
    _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?
  ) -> Int32 {
    guard let path, let argv else { return -1 }
    var fa = file_actions?.pointee
    var at = attrp?.pointee
    #if canImport(Glibc)
      if fa != nil && at != nil {
        return withUnsafePointer(to: &fa!) { faPtr in
          withUnsafePointer(to: &at!) { atPtr in
            Glibc.posix_spawn(pid, path, faPtr, atPtr, argv, envp)
          }
        }
      } else if fa != nil {
        return withUnsafePointer(to: &fa!) { faPtr in
          Glibc.posix_spawn(pid, path, faPtr, nil, argv, envp)
        }
      } else if at != nil {
        return withUnsafePointer(to: &at!) { atPtr in
          Glibc.posix_spawn(pid, path, nil, atPtr, argv, envp)
        }
      } else {
        return Glibc.posix_spawn(pid, path, nil, nil, argv, envp)
      }
    #else
      if fa != nil && at != nil {
        return withUnsafePointer(to: &fa!) { faPtr in
          withUnsafePointer(to: &at!) { atPtr in
            Musl.posix_spawn(pid, path, faPtr, atPtr, argv, envp)
          }
        }
      } else if fa != nil {
        return withUnsafePointer(to: &fa!) { faPtr in
          Musl.posix_spawn(pid, path, faPtr, nil, argv, envp)
        }
      } else if at != nil {
        return withUnsafePointer(to: &at!) { atPtr in
          Musl.posix_spawn(pid, path, nil, atPtr, argv, envp)
        }
      } else {
        return Musl.posix_spawn(pid, path, nil, nil, argv, envp)
      }
    #endif
  }

  public let IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES: Int32 = 3
  public let IOPOL_SCOPE_THREAD: Int32 = 1
  public let IOPOL_MATERIALIZE_DATALESS_FILES_OFF: Int32 = 1
  public func getiopolicy_np(_ iotype: Int32, _ scope: Int32) -> Int32 { 0 }
  @discardableResult
  public func setiopolicy_np(_ iotype: Int32, _ scope: Int32, _ policy: Int32) -> Int32 { 0 }

  public let ATTR_BIT_MAP_COUNT: Int32 = 5
  public let ATTR_CMN_NAME: UInt32 = 0x00000001
  public let ATTR_CMN_OBJTYPE: UInt32 = 0x00000008
  public let ATTR_CMN_MODTIME: UInt32 = 0x00000400
  public let ATTR_CMN_ERROR: UInt32 = 0x10000000
  public let ATTR_CMN_RETURNED_ATTRS: UInt32 = 0x80000000
  public let ATTR_DIR_MOUNTSTATUS: UInt32 = 0x00000001
  public let DIR_MNTSTATUS_MNTPOINT: Int32 = 0x00000001
  public let DIR_MNTSTATUS_TRIGGER: Int32 = 0x00000002

  public struct vtype: Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
  }
  public let VREG = vtype(rawValue: 1)
  public let VDIR = vtype(rawValue: 2)

  public struct attribute_set_t: Sendable {
    public var commonattr: attrgroup_t = 0
    public var volattr: attrgroup_t = 0
    public var dirattr: attrgroup_t = 0
    public var fileattr: attrgroup_t = 0
    public var forkattr: attrgroup_t = 0
    public init() {}
  }

  public struct attrlist: Sendable {
    public var bitmapcount: u_short = 0
    public var reserved: UInt16 = 0
    public var commonattr: attrgroup_t = 0
    public var volattr: attrgroup_t = 0
    public var dirattr: attrgroup_t = 0
    public var fileattr: attrgroup_t = 0
    public var forkattr: attrgroup_t = 0
    public init() {}
  }

  public struct attrreference_t: Sendable {
    public var attr_dataoffset: Int32 = 0
    public var attr_length: UInt32 = 0
    public init() {}
  }

  public func getattrlistbulk(
    _ dirfd: Int32,
    _ attrList: UnsafeMutableRawPointer?,
    _ attrBuf: UnsafeMutableRawPointer,
    _ attrBufSize: Int,
    _ options: UInt64
  ) -> Int32 { 0 }

  public typealias integer_t = Int32
  public typealias natural_t = UInt32
  public typealias mach_port_t = UInt32
  public typealias mach_msg_type_number_t = UInt32
  public typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
  public typealias vm_address_t = UInt
  public typealias vm_size_t = UInt

  public let KERN_SUCCESS: Int32 = 0
  public let HOST_VM_INFO64: Int32 = 4
  public let PROCESSOR_CPU_LOAD_INFO: Int32 = 2
  public let CLK_TCK: Int32 = 100
  public let CPU_STATE_USER: Int32 = 0
  public let CPU_STATE_SYSTEM: Int32 = 1
  public let CPU_STATE_IDLE: Int32 = 2
  public let CPU_STATE_NICE: Int32 = 3
  public let CPU_STATE_MAX: Int32 = 4

  public var mach_task_self_: mach_port_t { 0 }
  public func mach_host_self() -> mach_port_t { 0 }

  public struct vm_statistics64_data_t: Sendable {
    public var free_count: UInt32 = 262_144
    public var active_count: UInt32 = 0
    public var inactive_count: UInt32 = 0
    public var wire_count: UInt32 = 0
    public init() {}
  }

  public func host_statistics64(
    _ host_priv: mach_port_t,
    _ flavor: Int32,
    _ host_info64_out: UnsafeMutablePointer<integer_t>?,
    _ host_info64_outCnt: UnsafeMutablePointer<mach_msg_type_number_t>?
  ) -> Int32 {
    KERN_SUCCESS
  }

  public func host_processor_info(
    _ host: mach_port_t,
    _ flavor: Int32,
    _ out_processor_count: UnsafeMutablePointer<natural_t>?,
    _ out_processor_info: UnsafeMutablePointer<processor_info_array_t?>?,
    _ out_processor_infoCnt: UnsafeMutablePointer<mach_msg_type_number_t>?
  ) -> Int32 {
    let cpus = max(1, ProcessInfo.processInfo.processorCount)
    let total = cpus * Int(CPU_STATE_MAX)
    guard let buf = calloc(total, MemoryLayout<integer_t>.size)?.assumingMemoryBound(to: integer_t.self) else {
      return -1
    }
    out_processor_count?.pointee = natural_t(cpus)
    out_processor_info?.pointee = buf
    out_processor_infoCnt?.pointee = mach_msg_type_number_t(total)
    return KERN_SUCCESS
  }

  public func vm_deallocate(_ target_task: mach_port_t, _ address: vm_address_t, _ size: vm_size_t) -> Int32 {
    if let ptr = UnsafeMutableRawPointer(bitPattern: address) {
      free(ptr)
    }
    return KERN_SUCCESS
  }
#elseif !os(macOS)
  public typealias uid_t = UInt32
  public typealias gid_t = UInt32
  public typealias pid_t = Int32
  public typealias mode_t = UInt16
  public typealias off_t = Int64
  public typealias boolean_t = Int32
  public typealias u_short = UInt16
  public typealias attrgroup_t = UInt32

  public let F_SETNOSIGPIPE: Int32 = 73
  public let F_SETFD: Int32 = 2
  public let FD_CLOEXEC: Int32 = 1
  public let O_EVTONLY: Int32 = 0x8000

  #if !os(Windows)
    public let O_RDONLY: Int32 = 0x0000
    public let O_WRONLY: Int32 = 0x0001
    public let O_RDWR: Int32 = 0x0002
    public let O_APPEND: Int32 = 0x0008
    public let O_CREAT: Int32 = 0x0200
    public let O_TRUNC: Int32 = 0x0400
    public let O_EXCL: Int32 = 0x0800
    public let O_NONBLOCK: Int32 = 0x0004
    public let O_NOFOLLOW: Int32 = 0x0100
    public let O_CLOEXEC: Int32 = 0x1000000
  #else
    public let O_NONBLOCK: Int32 = 0
    public let O_NOFOLLOW: Int32 = 0
    public let O_CLOEXEC: Int32 = 0
  #endif
  public let O_DIRECTORY: Int32 = 0x100000

  public let S_IRUSR: Int32 = 0o400
  public let S_IWUSR: Int32 = 0o200
  public let S_IFMT: mode_t = 0o170000
  public let S_IFDIR: mode_t = 0o040000
  public let S_IFREG: mode_t = 0o100000
  public let S_IFLNK: mode_t = 0o120000
  public let S_ISVTX: mode_t = 0o001000

  public let UF_IMMUTABLE: Int32 = 0x00000002
  public let SF_IMMUTABLE: Int32 = 0x00020000
  public let SF_NOUNLINK: Int32 = 0x00100000
  public let SF_RESTRICTED: Int32 = 0x00080000
  public let SF_FIRMLINK: Int32 = 0x00800000

  public let AT_FDCWD: Int32 = -2
  public let AT_SYMLINK_NOFOLLOW: Int32 = 0x0020

  public let LOCK_EX: Int32 = 2
  public let LOCK_NB: Int32 = 4
  public let LOCK_UN: Int32 = 8
  public let SIGKILL: Int32 = 9
  public let SIGHUP: Int32 = 1
  public let WNOHANG: Int32 = 1
  public let TIOCSWINSZ: UInt = 0x80087467
  public let X_OK: Int32 = 1
  public let R_OK: Int32 = 4
  public let W_OK: Int32 = 2
  public let F_OK: Int32 = 0
  public let XATTR_NOFOLLOW: Int32 = 0x0001
  public let M_PI: Double = Double.pi
  public let M_E: Double = 2.71828182845904523536028747135266250

  public func getuid() -> uid_t { 0 }
  public func geteuid() -> uid_t { 0 }
  public func getgid() -> gid_t { 0 }
  public func getegid() -> gid_t { 0 }
  #if os(Windows)
    public func == (lhs: Int16, rhs: uid_t) -> Bool { lhs >= 0 && uid_t(lhs) == rhs }
    public func getpgrp() -> pid_t { ucrt._getpid() }
  #else
    public func getpid() -> pid_t { 1 }
    public func getpgrp() -> pid_t { 1 }
  #endif
  public func getpagesize() -> Int32 { 4096 }
  public func getgroups(_ count: Int32, _ list: UnsafeMutablePointer<gid_t>?) -> Int32 { 0 }
  public func mach_absolute_time() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000) }
  public func sysctlbyname(_ name: UnsafePointer<CChar>, _ oldp: UnsafeMutableRawPointer?, _ oldlenp: UnsafeMutablePointer<Int>?, _ newp: UnsafeMutableRawPointer?, _ newlen: Int) -> Int32 { -1 }

  public let FNM_CASEFOLD: Int32 = 0x10
  public func strcasecmp(_ s1: UnsafePointer<CChar>, _ s2: UnsafePointer<CChar>) -> Int32 {
    #if os(Windows)
      return _stricmp(s1, s2)
    #else
      return String(cString: s1).lowercased().compare(String(cString: s2).lowercased()).rawValue == 0 ? 0 : 1
    #endif
  }

  public func fnmatch(_ pattern: UnsafePointer<CChar>, _ string: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    let caseFold = (flags & FNM_CASEFOLD) != 0
    let p = Array((caseFold ? String(cString: pattern).lowercased() : String(cString: pattern)).unicodeScalars)
    let s = Array((caseFold ? String(cString: string).lowercased() : String(cString: string)).unicodeScalars)
    var pi = 0, si = 0, starIdx = -1, matchIdx = 0
    while si < s.count {
      if pi < p.count && (p[pi] == "?" || p[pi] == s[si]) {
        pi += 1; si += 1
      } else if pi < p.count && p[pi] == "*" {
        starIdx = pi; matchIdx = si; pi += 1
      } else if starIdx != -1 {
        pi = starIdx + 1; matchIdx += 1; si = matchIdx
      } else {
        return 1
      }
    }
    while pi < p.count && p[pi] == "*" { pi += 1 }
    return pi == p.count ? 0 : 1
  }

  @discardableResult
  public func fcntl(_ fd: Int32, _ cmd: Int32, _ arg: Int32 = 0) -> Int32 { 0 }

  @discardableResult
  public func flock(_ fd: Int32, _ op: Int32) -> Int32 { 0 }

  @discardableResult
  public func kill(_ pid: pid_t, _ sig: Int32) -> Int32 {
    #if os(Windows)
      if sig == 0 { return 0 }
      return cak_terminate_pid(UInt32(bitPattern: pid), sig == SIGKILL ? 1 : 0) != 0 ? 0 : -1
    #else
      return 0
    #endif
  }

  @discardableResult
  public func getxattr(_ path: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?, _ value: UnsafeMutableRawPointer?, _ size: Int, _ position: UInt32, _ options: Int32) -> Int { -1 }

  @discardableResult
  public func removexattr(_ path: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?, _ options: Int32) -> Int32 { -1 }

  public struct winsize: Sendable {
    public var ws_row: UInt16 = 24
    public var ws_col: UInt16 = 80
    public var ws_xpixel: UInt16 = 0
    public var ws_ypixel: UInt16 = 0
    public init(ws_row: UInt16 = 24, ws_col: UInt16 = 80, ws_xpixel: UInt16 = 0, ws_ypixel: UInt16 = 0) {
      self.ws_row = ws_row; self.ws_col = ws_col; self.ws_xpixel = ws_xpixel; self.ws_ypixel = ws_ypixel
    }
  }

  public func ioctl(_ fd: Int32, _ req: UInt, _ ptr: UnsafeMutableRawPointer?) -> Int32 { -1 }
  public func openpty(_ amaster: UnsafeMutablePointer<Int32>?, _ aslave: UnsafeMutablePointer<Int32>?, _ name: UnsafeMutablePointer<CChar>?, _ termp: UnsafeMutableRawPointer?, _ winp: UnsafeMutablePointer<winsize>?) -> Int32 { -1 }
  public func waitpid(_ pid: pid_t, _ status: UnsafeMutablePointer<Int32>?, _ options: Int32) -> pid_t { -1 }

  // MARK: - File descriptors, stat, utimes, realpath & getattrlistbulk

  public struct timeval: Sendable {
    public var tv_sec: Int
    public var tv_usec: Int32
    public init(tv_sec: Int = 0, tv_usec: Int32 = 0) {
      self.tv_sec = tv_sec
      self.tv_usec = tv_usec
    }
  }

  #if os(Windows)
    public struct _CrossTimespec: Sendable {
      public var tv_sec: Int
      public var tv_nsec: Int
      public init(tv_sec: Int = 0, tv_nsec: Int = 0) {
        self.tv_sec = tv_sec
        self.tv_nsec = tv_nsec
      }
    }

    public typealias stat = ucrt.stat

    extension ucrt.stat {
      public var st_flags: UInt32 {
        (st_mode & 0o222) == 0 ? UInt32(UF_IMMUTABLE) : 0
      }
      public var st_mtimespec: _CrossTimespec {
        _CrossTimespec(tv_sec: Int(st_mtime), tv_nsec: 0)
      }
      public var st_atimespec: _CrossTimespec {
        _CrossTimespec(tv_sec: Int(st_atime), tv_nsec: 0)
      }
      public var st_ctimespec: _CrossTimespec {
        _CrossTimespec(tv_sec: Int(st_ctime), tv_nsec: 0)
      }
      public var st_birthtimespec: _CrossTimespec {
        _CrossTimespec(tv_sec: Int(st_ctime), tv_nsec: 0)
      }
    }

    private func fillStat(_ src: cak_stat_info, into dst: UnsafeMutablePointer<ucrt.stat>?) {
      guard let dst else { return }
      var s = ucrt.stat()
      s.st_mode = src.st_mode
      s.st_size = Int32(clamping: src.st_size)
      s.st_mtime = src.mtime_sec
      s.st_atime = src.atime_sec
      s.st_ctime = src.btime_sec > 0 ? src.btime_sec : src.ctime_sec
      dst.pointee = s
    }

    public func lstat(_ path: UnsafePointer<CChar>, _ buf: UnsafeMutablePointer<ucrt.stat>?) -> Int32 {
      var info = cak_stat_info()
      var err: Int32 = 0
      guard cak_posix_stat(path, 0, &info, &err) == 0 else {
        _set_errno(err)
        return -1
      }
      fillStat(info, into: buf)
      return 0
    }

    public func fstat(_ fd: Int32, _ buf: UnsafeMutablePointer<ucrt.stat>?, _ _unused: Int32 = 0) -> Int32 {
      var info = cak_stat_info()
      var err: Int32 = 0
      guard cak_posix_fstat(fd, &info, &err) == 0 else {
        _set_errno(err)
        return -1
      }
      fillStat(info, into: buf)
      return 0
    }

    public func fstatat(_ dirfd: Int32, _ path: UnsafePointer<CChar>, _ buf: UnsafeMutablePointer<ucrt.stat>?, _ flag: Int32) -> Int32 {
      var info = cak_stat_info()
      var err: Int32 = 0
      let follow: Int32 = (flag & AT_SYMLINK_NOFOLLOW) != 0 ? 0 : 1
      guard cak_posix_stat(path, follow, &info, &err) == 0 else {
        _set_errno(err)
        return -1
      }
      fillStat(info, into: buf)
      return 0
    }
  #endif

  public func open(_ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t = 0) -> Int32 {
    #if os(Windows)
      var err: Int32 = 0
      let fd = cak_posix_open(path, oflag, Int32(mode), &err)
      if fd < 0 { _set_errno(err) }
      return fd
    #else
      return -1
    #endif
  }

  public func open(_ path: String, _ oflag: Int32) -> Int32 {
    path.withCString { Darwin.open($0, oflag, mode_t(0)) }
  }

  public func open(_ path: String, _ oflag: Int32, _ mode: mode_t) -> Int32 {
    path.withCString { Darwin.open($0, oflag, mode) }
  }

  @discardableResult
  public func close(_ fd: Int32, _ _unused: Int32 = 0) -> Int32 {
    #if os(Windows)
      return cak_posix_close(fd)
    #else
      return 0
    #endif
  }

  public func read(_ fd: Int32, _ buf: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if os(Windows)
      guard let buf else { return -1 }
      if count == 0 { return 0 }
      return Int(_read(fd, buf, UInt32(min(count, Int(Int32.max)))))
    #else
      return -1
    #endif
  }

  public func write(_ fd: Int32, _ buf: UnsafeRawPointer?, _ count: Int) -> Int {
    #if os(Windows)
      guard let buf else { return -1 }
      if count == 0 { return 0 }
      return Int(_write(fd, buf, UInt32(min(count, Int(Int32.max)))))
    #else
      return -1
    #endif
  }

  public func pread(_ fd: Int32, _ buf: UnsafeMutableRawPointer?, _ count: Int, _ offset: off_t) -> Int {
    #if os(Windows)
      guard let buf else { return -1 }
      guard _lseeki64(fd, offset, ucrt.SEEK_SET) >= 0 else { return -1 }
      if count == 0 { return 0 }
      return Int(_read(fd, buf, UInt32(min(count, Int(Int32.max)))))
    #else
      return -1
    #endif
  }

  #if !os(Windows)
    @_cdecl("_crossswift_stat")
    public func _crossswift_stat_impl(_ path: UnsafePointer<CChar>?, _ buf: UnsafeMutablePointer<CDarwinShims.stat>?) -> Int32 { -1 }

    @_cdecl("_crossswift_lstat")
    public func _crossswift_lstat_impl(_ path: UnsafePointer<CChar>?, _ buf: UnsafeMutablePointer<CDarwinShims.stat>?) -> Int32 { -1 }

    @_cdecl("_crossswift_fstat")
    public func _crossswift_fstat_impl(_ fd: Int32, _ buf: UnsafeMutablePointer<CDarwinShims.stat>?) -> Int32 { -1 }

    @_cdecl("_crossswift_fstatat")
    public func _crossswift_fstatat_impl(_ dirfd: Int32, _ path: UnsafePointer<CChar>?, _ buf: UnsafeMutablePointer<CDarwinShims.stat>?, _ flag: Int32) -> Int32 { -1 }
  #endif

  public func mkdir(_ path: UnsafePointer<CChar>, _ mode: mode_t) -> Int32 {
    #if os(Windows)
      var err: Int32 = 0
      guard cak_posix_mkdir(path, &err) == 0 else {
        _set_errno(err)
        return -1
      }
      return 0
    #else
      return -1
    #endif
  }

  public func utimes(_ path: UnsafePointer<CChar>, _ times: UnsafePointer<timeval>?) -> Int32 {
    #if os(Windows)
      guard let times else { return 0 }
      var err: Int32 = 0
      let a = times[0]
      let m = times[1]
      guard cak_posix_utimes(path, Int64(a.tv_sec), Int64(a.tv_usec), Int64(m.tv_sec), Int64(m.tv_usec), &err) == 0 else {
        _set_errno(err)
        return -1
      }
      return 0
    #else
      return -1
    #endif
  }

  public func realpath(_ path: UnsafePointer<CChar>?, _ resolved_path: UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    #if os(Windows)
      guard let path else { return nil }
      guard let dup = cak_realpath(path) else { return nil }
      if let resolved_path {
        let len = strlen(dup) + 1
        memcpy(resolved_path, dup, len)
        cak_free(dup)
        return resolved_path
      }
      return dup
    #else
      return nil
    #endif
  }

  public let IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES: Int32 = 3
  public let IOPOL_SCOPE_THREAD: Int32 = 1
  public let IOPOL_MATERIALIZE_DATALESS_FILES_OFF: Int32 = 1
  public func getiopolicy_np(_ iotype: Int32, _ scope: Int32) -> Int32 { 0 }
  @discardableResult
  public func setiopolicy_np(_ iotype: Int32, _ scope: Int32, _ policy: Int32) -> Int32 { 0 }

  public let ATTR_BIT_MAP_COUNT: Int32 = 5
  public let ATTR_CMN_NAME: UInt32 = 0x00000001
  public let ATTR_CMN_OBJTYPE: UInt32 = 0x00000008
  public let ATTR_CMN_MODTIME: UInt32 = 0x00000400
  public let ATTR_CMN_ERROR: UInt32 = 0x10000000
  public let ATTR_CMN_RETURNED_ATTRS: UInt32 = 0x80000000
  public let ATTR_DIR_MOUNTSTATUS: UInt32 = 0x00000001
  public let DIR_MNTSTATUS_MNTPOINT: Int32 = 0x00000001
  public let DIR_MNTSTATUS_TRIGGER: Int32 = 0x00000002

  public struct vtype: Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
  }
  public let VREG = vtype(rawValue: 1)
  public let VDIR = vtype(rawValue: 2)

  public struct attribute_set_t: Sendable {
    public var commonattr: attrgroup_t = 0
    public var volattr: attrgroup_t = 0
    public var dirattr: attrgroup_t = 0
    public var fileattr: attrgroup_t = 0
    public var forkattr: attrgroup_t = 0
    public init() {}
  }

  public struct attrlist: Sendable {
    public var bitmapcount: u_short = 0
    public var reserved: UInt16 = 0
    public var commonattr: attrgroup_t = 0
    public var volattr: attrgroup_t = 0
    public var dirattr: attrgroup_t = 0
    public var fileattr: attrgroup_t = 0
    public var forkattr: attrgroup_t = 0
    public init() {}
  }

  public struct attrreference_t: Sendable {
    public var attr_dataoffset: Int32 = 0
    public var attr_length: UInt32 = 0
    public init() {}
  }

  public func getattrlistbulk(
    _ dirfd: Int32,
    _ attrList: UnsafeMutableRawPointer?,
    _ attrBuf: UnsafeMutableRawPointer,
    _ attrBufSize: Int,
    _ options: UInt64
  ) -> Int32 {
    #if os(Windows)
      return cak_getattrlistbulk(dirfd, attrBuf, attrBufSize)
    #else
      return 0
    #endif
  }

  @discardableResult
  public func ftruncate(_ fd: Int32, _ length: off_t) -> Int32 {
    #if os(Windows)
      return _chsize_s(fd, length) == 0 ? 0 : -1
    #else
      return -1
    #endif
  }

  @discardableResult
  public func pwrite(_ fd: Int32, _ buf: UnsafeRawPointer?, _ count: Int, _ offset: off_t) -> Int {
    #if os(Windows)
      guard let buf else { return -1 }
      guard _lseeki64(fd, offset, SEEK_SET) >= 0 else { return -1 }
      if count == 0 { return 0 }
      return Int(_write(fd, buf, UInt32(min(count, Int(Int32.max)))))
    #else
      return -1
    #endif
  }

  public let PROT_READ: Int32 = 1
  public let MAP_PRIVATE: Int32 = 2
  public func mmap(
    _ addr: UnsafeMutableRawPointer?,
    _ length: Int,
    _ prot: Int32,
    _ flags: Int32,
    _ fd: Int32,
    _ offset: off_t
  ) -> UnsafeMutableRawPointer? {
    #if os(Windows)
      guard length > 0, let buf = malloc(length) else { return UnsafeMutableRawPointer(bitPattern: -1) }
      guard _lseeki64(fd, offset, SEEK_SET) >= 0 else {
        free(buf)
        return UnsafeMutableRawPointer(bitPattern: -1)
      }
      var remaining = length
      var cursor = buf
      while remaining > 0 {
        let chunk = Int(_read(fd, cursor, UInt32(min(remaining, Int(Int32.max)))))
        if chunk <= 0 { break }
        cursor += chunk
        remaining -= chunk
      }
      return buf
    #else
      return UnsafeMutableRawPointer(bitPattern: -1)
    #endif
  }

  @discardableResult
  public func munmap(_ addr: UnsafeMutableRawPointer?, _ length: Int) -> Int32 {
    #if os(Windows)
      free(addr)
      return 0
    #else
      return -1
    #endif
  }

  private let _sacLockScreenFn: @convention(c) () -> Int32 = {
    #if os(Windows)
      _ = cak_lock_workstation()
    #endif
    return 0
  }

  public let RTLD_LAZY: Int32 = 1
  public let RTLD_NOW: Int32 = 2

  public func dlopen(_ path: UnsafePointer<CChar>?, _ mode: Int32) -> UnsafeMutableRawPointer? {
    guard let path else { return UnsafeMutableRawPointer(bitPattern: 0x1) }
    let s = String(cString: path)
    if s.hasSuffix("/login") {
      return UnsafeMutableRawPointer(bitPattern: 0x10614)
    }
    return nil
  }

  @discardableResult
  public func dlclose(_ handle: UnsafeMutableRawPointer?) -> Int32 { 0 }

  public func dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let symbol else { return nil }
    let name = String(cString: symbol)
    if name == "SACLockScreenImmediate" {
      return unsafeBitCast(_sacLockScreenFn, to: UnsafeMutableRawPointer.self)
    }
    return nil
  }

  // MARK: - Mach / BSD host info & ifaddrs stubs for ExtensionNodeShims

  public typealias integer_t = Int32
  public typealias natural_t = UInt32
  public typealias mach_port_t = UInt32
  public typealias mach_msg_type_number_t = UInt32
  public typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
  public typealias vm_address_t = UInt
  public typealias vm_size_t = UInt

  public let KERN_SUCCESS: Int32 = 0
  public let HOST_VM_INFO64: Int32 = 4
  public let PROCESSOR_CPU_LOAD_INFO: Int32 = 2
  #if !os(Windows)
    public let CLK_TCK: Int32 = 100
  #endif
  public let CPU_STATE_USER: Int32 = 0
  public let CPU_STATE_SYSTEM: Int32 = 1
  public let CPU_STATE_IDLE: Int32 = 2
  public let CPU_STATE_NICE: Int32 = 3
  public let CPU_STATE_MAX: Int32 = 4

  public var mach_task_self_: mach_port_t { 0 }
  public func mach_host_self() -> mach_port_t { 0 }

  public struct vm_statistics64_data_t: Sendable {
    public var free_count: UInt32 = 262_144
    public var active_count: UInt32 = 0
    public var inactive_count: UInt32 = 0
    public var wire_count: UInt32 = 0
    public init() {}
  }

  public func getloadavg(_ loadavg: UnsafeMutablePointer<Double>?, _ nelem: Int32) -> Int32 {
    guard let loadavg, nelem > 0 else { return 0 }
    for i in 0..<Int(nelem) { loadavg[i] = 0 }
    return nelem
  }

  public func host_statistics64(
    _ host_priv: mach_port_t,
    _ flavor: Int32,
    _ host_info64_out: UnsafeMutablePointer<integer_t>?,
    _ host_info64_outCnt: UnsafeMutablePointer<mach_msg_type_number_t>?
  ) -> Int32 {
    KERN_SUCCESS
  }

  public func host_processor_info(
    _ host: mach_port_t,
    _ flavor: Int32,
    _ out_processor_count: UnsafeMutablePointer<natural_t>?,
    _ out_processor_info: UnsafeMutablePointer<processor_info_array_t?>?,
    _ out_processor_infoCnt: UnsafeMutablePointer<mach_msg_type_number_t>?
  ) -> Int32 {
    let cpus = max(1, ProcessInfo.processInfo.processorCount)
    let total = cpus * Int(CPU_STATE_MAX)
    guard let buf = calloc(total, MemoryLayout<integer_t>.size)?.assumingMemoryBound(to: integer_t.self) else {
      return -1
    }
    out_processor_count?.pointee = natural_t(cpus)
    out_processor_info?.pointee = buf
    out_processor_infoCnt?.pointee = mach_msg_type_number_t(total)
    return KERN_SUCCESS
  }

  public func vm_deallocate(_ target_task: mach_port_t, _ address: vm_address_t, _ size: vm_size_t) -> Int32 {
    if let ptr = UnsafeMutableRawPointer(bitPattern: address) {
      free(ptr)
    }
    return KERN_SUCCESS
  }

  // POSIX termios & posix_spawn stubs for PseudoTerminal
  public typealias tcflag_t = UInt
  public let ICANON: UInt = 0x0100
  public let ISIG: UInt = 0x0080
  public let OPOST: UInt = 0x0001
  public let ONLCR: UInt = 0x0002
  public struct termios: Sendable {
    public var c_iflag: tcflag_t = 0
    public var c_oflag: tcflag_t = 0
    public var c_cflag: tcflag_t = 0
    public var c_lflag: tcflag_t = 0
    public init() {}
  }
  public func cfmakeraw(_ termios_p: UnsafeMutablePointer<termios>?) {}

  public typealias posix_spawnattr_t = UnsafeMutableRawPointer
  public typealias posix_spawn_file_actions_t = UnsafeMutableRawPointer
  public let POSIX_SPAWN_SETSID: Int32 = 0x0400
  @discardableResult public func posix_spawnattr_init(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>?) -> Int32 { 0 }
  @discardableResult public func posix_spawnattr_destroy(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>?) -> Int32 { 0 }
  @discardableResult public func posix_spawnattr_setflags(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>?, _ flags: Int16) -> Int32 { 0 }
  @discardableResult public func posix_spawn_file_actions_init(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>?) -> Int32 { 0 }
  @discardableResult public func posix_spawn_file_actions_destroy(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>?) -> Int32 { 0 }
  @discardableResult public func posix_spawn_file_actions_addchdir(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>?, _ path: UnsafePointer<CChar>?) -> Int32 { 0 }
  @discardableResult public func posix_spawn_file_actions_adddup2(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>?, _ fildes: Int32, _ newfildes: Int32) -> Int32 { 0 }
  @discardableResult public func posix_spawn_file_actions_addclose(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>?, _ fildes: Int32) -> Int32 { 0 }
  public func posix_spawn(
    _ pid: UnsafeMutablePointer<pid_t>?,
    _ path: UnsafePointer<CChar>?,
    _ file_actions: UnsafePointer<posix_spawn_file_actions_t?>?,
    _ attrp: UnsafePointer<posix_spawnattr_t?>?,
    _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?,
    _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?
  ) -> Int32 { -1 }

  // POSIX networking & ifaddrs stubs for ExtensionNameResolver & ExtensionNodeShims
  public typealias socklen_t = UInt32
  public let AF_UNSPEC: Int32 = 0
  public let AF_INET: Int32 = 2
  public let AF_INET6: Int32 = 23
  public let SOCK_STREAM: Int32 = 1
  public let NI_NUMERICHOST: Int32 = 2
  public let NI_MAXHOST: Int32 = 1025
  public let INET6_ADDRSTRLEN: Int32 = 46
  public let IFF_UP: Int32 = 0x1
  public let IFF_LOOPBACK: Int32 = 0x8
  public let IFF_RUNNING: Int32 = 0x40

  public struct sockaddr: Sendable {
    public var sa_len: UInt8 = 0
    public var sa_family: UInt8 = 0
    public init() {}
  }

  public struct in_addr: Sendable {
    public var s_addr: UInt32 = 0
    public init() {}
  }

  public struct in6_addr: Sendable {
    public var _bytes: (UInt64, UInt64) = (0, 0)
    public init() {}
  }

  public struct sockaddr_in: Sendable {
    public var sin_len: UInt8 = 16
    public var sin_family: UInt8 = 2
    public var sin_port: UInt16 = 0
    public var sin_addr: in_addr = in_addr()
    public var sin_zero: UInt64 = 0
    public init() {}
  }

  public struct sockaddr_in6: Sendable {
    public var sin6_len: UInt8 = 28
    public var sin6_family: UInt8 = 23
    public var sin6_port: UInt16 = 0
    public var sin6_flowinfo: UInt32 = 0
    public var sin6_addr: in6_addr = in6_addr()
    public var sin6_scope_id: UInt32 = 0
    public init() {}
  }

  public struct sockaddr_storage: Sendable {
    public var _pad: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0, 0, 0, 0)
    public init() {}
  }

  public struct ifaddrs: @unchecked Sendable {
    public var ifa_next: UnsafeMutablePointer<ifaddrs>? = nil
    public var ifa_name: UnsafeMutablePointer<CChar>! = nil
    public var ifa_flags: UInt32 = 0
    public var ifa_addr: UnsafeMutablePointer<sockaddr>? = nil
    public var ifa_netmask: UnsafeMutablePointer<sockaddr>? = nil
    public init() {}
  }

  public func getifaddrs(_ ifap: UnsafeMutablePointer<UnsafeMutablePointer<ifaddrs>?>?) -> Int32 {
    ifap?.pointee = nil
    return 0
  }
  public func freeifaddrs(_ ifa: UnsafeMutablePointer<ifaddrs>?) {}
  public func inet_ntop(_ af: Int32, _ src: UnsafeRawPointer?, _ dst: UnsafeMutablePointer<CChar>?, _ size: socklen_t) -> UnsafePointer<CChar>? { nil }

  public struct addrinfo: @unchecked Sendable {
    public var ai_flags: Int32 = 0
    public var ai_family: Int32 = 0
    public var ai_socktype: Int32 = 0
    public var ai_protocol: Int32 = 0
    public var ai_addrlen: UInt32 = 0
    public var ai_canonname: UnsafeMutablePointer<CChar>? = nil
    public var ai_addr: UnsafeMutablePointer<sockaddr>? = nil
    public var ai_next: UnsafeMutablePointer<addrinfo>? = nil
    public init() {}
  }
  public func getaddrinfo(_ node: UnsafePointer<CChar>?, _ service: UnsafePointer<CChar>?, _ hints: UnsafePointer<addrinfo>?, _ res: UnsafeMutablePointer<UnsafeMutablePointer<addrinfo>?>?) -> Int32 { -1 }
  public func freeaddrinfo(_ res: UnsafeMutablePointer<addrinfo>?) {}
  public func getnameinfo(_ sa: UnsafePointer<sockaddr>?, _ salen: UInt32, _ host: UnsafeMutablePointer<CChar>?, _ hostlen: UInt32, _ serv: UnsafeMutablePointer<CChar>?, _ servlen: UInt32, _ flags: Int32) -> Int32 { -1 }
#endif
