import Cocoa

@main
struct Probe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 4,
              let pid = Int32(args[1]),
              let app = NSRunningApplication(processIdentifier: pid),
              let bundle = Bundle(path: args[2]) else { exit(2) }
        let allowed = RoTypeProcessTrust.canTerminate(app, replacement: bundle)
        let expected = args[3] != "deny"
        print("termination policy: \(allowed ? "allow" : "deny"), expected: \(args[3])")
        guard allowed == expected else { exit(1) }
        if args[3] == "terminate" {
            app.terminate()
            let deadline = Date().addingTimeInterval(2)
            while !app.isTerminated && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            if !app.isTerminated { app.forceTerminate() }
            let forcedDeadline = Date().addingTimeInterval(2)
            while !app.isTerminated && Date() < forcedDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            guard app.isTerminated else { exit(1) }
            print("stale process terminated")
        }
    }
}
