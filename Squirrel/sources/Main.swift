//
//  Main.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

import Foundation
import InputMethodKit

@main
struct SquirrelApp {
  static let userDir = if let pwuid = getpwuid(getuid()) {
    URL(fileURLWithFileSystemRepresentation: pwuid.pointee.pw_dir, isDirectory: true, relativeTo: nil).appending(components: "Library", "Rime")
  } else {
    try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Rime", isDirectory: true)
  }
  // Register the bundle that is actually executing. The previous hard-coded
  // path used the non-existent "Input Library" directory, leaving Squirrel
  // selected but absent from macOS' enabled input-source list after upgrades.
  static let appDir = Bundle.main.bundleURL
  static let logDir = FileManager.default.temporaryDirectory.appending(component: "rime.squirrel", directoryHint: .isDirectory)

  // swiftlint:disable:next cyclomatic_complexity
  static func main() {
    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee

    let handled = autoreleasepool {
      let installer = SquirrelInstaller()
      let args = CommandLine.arguments
      if args.count > 1 {
        switch args[1] {
        case "--quit":
          let bundleId = Bundle.main.bundleIdentifier!
          let currentPID = ProcessInfo.processInfo.processIdentifier
          let executableURL = Bundle.main.executableURL?.resolvingSymlinksInPath().standardizedFileURL
          let runningSquirrels = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter {
              $0.processIdentifier != currentPID
                && $0.executableURL?.resolvingSymlinksInPath().standardizedFileURL == executableURL
                && RoTypeProcessTrust.canTerminate($0, replacement: Bundle.main)
            }
          runningSquirrels.forEach { $0.terminate() }
          let deadline = Date().addingTimeInterval(2)
          while runningSquirrels.contains(where: { !$0.isTerminated }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
          }
          runningSquirrels.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
          return true
        case "--reload":
          DistributedNotificationCenter.default().postNotificationName(.init("SquirrelReloadNotification"), object: nil)
          return true
        case "--register-input-source", "--install":
          guard installer.register() else { Foundation.exit(EXIT_FAILURE) }
          return true
        case "--enable-input-source":
          if args.count > 2 {
            let modes = args[2...].map { SquirrelInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              guard installer.enable(modes: modes) else { Foundation.exit(EXIT_FAILURE) }
              return true
            }
          }
          guard installer.enable() else { Foundation.exit(EXIT_FAILURE) }
          return true
        case "--disable-input-source":
          if args.count > 2 {
            let modes = args[2...].map { SquirrelInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              guard installer.disable(modes: modes) else { Foundation.exit(EXIT_FAILURE) }
              return true
            }
          }
          guard installer.disable() else { Foundation.exit(EXIT_FAILURE) }
          return true
        case "--select-input-source":
          let selected: Bool
          if args.count > 2, let mode = SquirrelInstaller.InputMode(rawValue: args[2]) {
            selected = installer.select(mode: mode)
          } else {
            selected = installer.select()
          }
          guard selected else { Foundation.exit(EXIT_FAILURE) }
          return true
        case "--build":
          // Notification
          SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_update", comment: ""))
          // Build all schemas in current directory
          var builderTraits = RimeTraits.rimeStructInit()
          builderTraits.setCString("rime.squirrel-builder", to: \.app_name)
          rimeAPI.setup(&builderTraits)
          rimeAPI.deployer_initialize(nil)
          _ = rimeAPI.deploy()
          return true
        case "--sync":
          DistributedNotificationCenter.default().postNotificationName(.init("SquirrelSyncNotification"), object: nil)
          return true
        case "--preview-candidates":
          guard args.count >= 3 else { Foundation.exit(EXIT_FAILURE) }
          SquirrelPanel.preview(configurationPath: args[2], dark: args.contains("--dark"))
          return true
        case "--help":
          print(helpDoc)
          return true
        default:
          break
        }
      }
      return false
    }
    if handled {
      return
    }

    autoreleasepool {
      // find the bundle identifier and then initialize the input method server
      let main = Bundle.main
      let connectionName = main.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
      _ = IMKServer(name: connectionName, bundleIdentifier: main.bundleIdentifier!)
      // load the bundle explicitly because in this case the input method is a
      // background only application
      let app = NSApplication.shared
      let delegate = SquirrelApplicationDelegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)

      // opencc will be configured with relative dictionary paths
      FileManager.default.changeCurrentDirectoryPath(main.sharedSupportPath!)

      if NSApp.squirrelAppDelegate.problematicLaunchDetected() {
        print("Problematic launch detected!")
        let args = ["Problematic launch detected! Squirrel may be suffering a crash due to improper configuration. Revert previous modifications to see if the problem recurs."]
        let task = Process()
        task.executableURL = "/usr/bin/say".withCString { dir in
          URL(fileURLWithFileSystemRepresentation: dir, isDirectory: false, relativeTo: nil)
        }
        task.arguments = args
        try? task.run()
      } else {
        RoTypeFactoryDataMigration.run(userDirectory: SquirrelApp.userDir)
        NSApp.squirrelAppDelegate.setupRime()
        NSApp.squirrelAppDelegate.startRime(fullCheck: false)
        NSApp.squirrelAppDelegate.loadSettings()
        print("Squirrel reporting!")
      }

      // finally run everything
      app.run()
      print("Squirrel is quitting...")
      rimeAPI.finalize()
    }
    return
  }

  static let helpDoc = """
Supported arguments:
Perform actions:
  --quit                     quit all Squirrel process
  --reload                   deploy
  --sync                     sync user data
  --build                    build all schemas in current directory
Install Squirrel:
  --install, --register-input-source    register input source
  --enable-input-source [source id...]  input source list optional
  --disable-input-source [source id...] input source list optional
  --select-input-source [source id]     input source optional
"""
}

private enum RoTypeFactoryDataMigration {
  static let markerName = ".rotype-factory-data-v1"
  static let managedPaths = [
    "rotype.schema.yaml",
    "rotype_flypy.schema.yaml",
    "rotype_en.schema.yaml",
    "rotype_zh.dict.yaml",
    "rotype_en.dict.yaml",
    "lua/rotype_bilingual_translator.lua",
    "lua/rotype_dynamic_bilingual_filter.lua",
    "lua/rotype_dynamic_refresh.lua",
    "lua/rotype_english_echo.lua",
    "lua/rotype_full_translation_commit.lua",
    "lua/rotype_simplified_only_filter.lua"
  ]

  static func run(userDirectory: URL) {
    let fileManager = FileManager.default
    let marker = userDirectory.appendingPathComponent(markerName)
    guard !fileManager.fileExists(atPath: marker.path) else { return }

    do {
      try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
      let existingPaths = managedPaths.filter {
        fileManager.fileExists(atPath: userDirectory.appendingPathComponent($0).path)
      }
      if !existingPaths.isEmpty {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = userDirectory
          .appendingPathComponent("rotype-backups", isDirectory: true)
          .appendingPathComponent("factory-data-migration-\(formatter.string(from: Date()))-\(UUID().uuidString)", isDirectory: true)
        for relativePath in existingPaths {
          let source = userDirectory.appendingPathComponent(relativePath)
          let destination = backup.appendingPathComponent(relativePath)
          try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try fileManager.copyItem(at: source, to: destination)
          try fileManager.removeItem(at: source)
        }
        print("Moved legacy RoType factory files to: \(backup.path)")
      }
      try Data("RoType factory data is supplied by the input method bundle.\n".utf8)
        .write(to: marker, options: .atomic)
    } catch {
      print("Failed to migrate legacy RoType factory data: \(error.localizedDescription)")
    }
  }
}
