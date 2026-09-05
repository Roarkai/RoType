import Darwin
import Foundation

// A harmless stand-in for both legacy executables. Never opens a socket,
// starts Python, reads model data or accesses the microphone.
if CommandLine.arguments.contains("--quit") { exit(0) }
if ProcessInfo.processInfo.environment["ROTYPE_FIXTURE_IGNORE_TERM"] == "1" {
    signal(SIGTERM, SIG_IGN)
}
if let ready = ProcessInfo.processInfo.environment["ROTYPE_FIXTURE_READY"] {
    try Data("ready".utf8).write(to: URL(fileURLWithPath: ready), options: .atomic)
}
while true { sleep(1) }
