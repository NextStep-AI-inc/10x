import AppKit
import Foundation
let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
let profile = CommandLine.arguments[2]
let config = NSWorkspace.OpenConfiguration()
config.activates = false
config.createsNewApplicationInstance = true
config.environment = ["CFFIXED_USER_HOME": profile, "HOME": profile, "PATH": "\(profile)/.bun/bin:/opt/homebrew/bin:/usr/bin:/bin"]
var finished = false
NSWorkspace.shared.openApplication(at: bundle, configuration: config) { app, error in
    if let app { print("QA_PID=\(app.processIdentifier)") }
    else { print("LAUNCH_ERROR=\(String(describing: error))") }
    finished = true
}
while !finished { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
