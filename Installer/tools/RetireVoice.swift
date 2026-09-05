import Darwin
import Foundation
import Security

// Installer-only migration tool. Never executes an old launcher, uses a pidfile,
// or guesses ownership from a port or a process-name substring.
private struct RetirementError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct ProcessIdentity: Equatable {
    let pid: pid_t
    let uid: uid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let executable: String
}

private func identity(of pid: pid_t) -> ProcessIdentity? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
    return ProcessIdentity(pid: pid, uid: info.pbi_uid,
                           startSeconds: info.pbi_start_tvsec,
                           startMicroseconds: info.pbi_start_tvusec,
                           executable: URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path)
}

private func allPIDs() throws -> [pid_t] {
    var capacity = max(Int(proc_listallpids(nil, 0)) + 128, 256)
    for _ in 0..<5 {
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { throw RetirementError("Cannot enumerate processes; preserving voice app.") }
        if count < capacity { return Array(pids.prefix(count)) }
        capacity *= 2
    }
    throw RetirementError("Process list did not stabilize; preserving voice app.")
}

private func arguments(of pid: pid_t) throws -> [String] {
    var maximum: Int32 = 0
    var size = MemoryLayout.size(ofValue: maximum)
    guard sysctlbyname("kern.argmax", &maximum, &size, nil, 0) == 0, maximum > 0 else {
        throw RetirementError("Cannot inspect voice process arguments.")
    }
    var bytes = [UInt8](repeating: 0, count: Int(maximum))
    size = bytes.count
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0, size > 4 else {
        throw RetirementError("Cannot inspect arguments for pid \(pid); preserving voice app.")
    }
    let count = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
    guard count > 0, count <= size else { throw RetirementError("Invalid process argument data.") }
    var offset = 4
    func nextString() throws -> String {
        let start = offset
        while offset < size && bytes[offset] != 0 { offset += 1 }
        guard offset < size, let result = String(bytes: bytes[start..<offset], encoding: .utf8) else {
            throw RetirementError("Unreadable process arguments; preserving voice app.")
        }
        offset += 1
        return result
    }
    _ = try nextString() // kernel executable path precedes argv
    while offset < size && bytes[offset] == 0 { offset += 1 }
    return try (0..<count).map { _ in try nextString() }
}

private func verify(_ app: URL) throws {
    var code: SecStaticCode?
    var requirement: SecRequirement?
    let rule = "anchor apple generic and identifier \"im.roarkai.inputmethod.Luoke.voice\" and certificate leaf[subject.OU] = \"DF7J2VBQD8\""
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
          let code,
          SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
          let requirement,
          SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess else {
        throw RetirementError("Voice app signature is not the expected RoType product; preserving app and processes.")
    }
}

private func retire(_ app: URL) throws {
    try verify(app)
    func bundledPath(_ relative: String) throws -> String {
        let path = app.appendingPathComponent(relative).resolvingSymlinksInPath().path
        guard path.hasPrefix(app.path + "/") else {
            throw RetirementError("Voice executable resolves outside its signed app.")
        }
        return path
    }
    let helper = try bundledPath("Contents/MacOS/RoTypeVoice")
    let python = try bundledPath("Contents/Resources/Python/bin/python3")
    let server = try bundledPath("Contents/Resources/server.py")
    let deadline = DispatchTime.now().uptimeNanoseconds + 6_000_000_000
    var signalled = Set<pid_t>()
    while true {
        var found = false
        for pid in try allPIDs() {
            guard let process = identity(of: pid), process.executable == helper || process.executable == python else { continue }
            if process.executable == python {
                let argv: [String]
                do { argv = try arguments(of: pid) }
                catch {
                    if identity(of: pid) != process { continue }
                    throw error
                }
                guard argv.count == 2,
                      URL(fileURLWithPath: argv[1]).resolvingSymlinksInPath().path == server else { continue }
            }
            guard getuid() == 0 || process.uid == getuid() else {
                throw RetirementError("Voice process belongs to another user; administrator authorization required.")
            }
            // Recheck start time, owner and executable immediately before signalling.
            // No SIGKILL escalation: an uncooperative process blocks removal.
            guard identity(of: pid) == process else { continue }
            found = true
            if kill(pid, SIGTERM) != 0 && errno != ESRCH {
                throw RetirementError("Could not stop owned voice pid \(pid); preserving app.")
            }
            signalled.insert(pid)
        }
        if !found { break }
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw RetirementError("Voice processes did not exit within six seconds; preserving app.")
        }
        usleep(50_000)
    }
    print("Verified voice retirement: \(signalled.count) owned processes stopped.")
}

do {
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--app" else {
        throw RetirementError("Usage: retire-voice --app <exact signed legacy voice app>")
    }
    let app = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.resolvingSymlinksInPath()
    try retire(app)
} catch {
    FileHandle.standardError.write(Data("RoType: \(error)\n".utf8))
    exit(1)
}
