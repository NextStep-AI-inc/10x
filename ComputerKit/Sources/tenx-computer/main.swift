import AppKit
@preconcurrency import ApplicationServices
import ComputerKit
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func ensureDaemon() throws {
    if let client = try? DaemonClient() { _ = client; return } // already running
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["daemon"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    // Wait for the socket to accept connections (up to 3s).
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let client = try? DaemonClient() { _ = client; return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ComputerError("daemon_start_timeout")
}

func runMCPFront() throws {
    try ensureDaemon()
    let client = try DaemonClient()
    try client.send(.object(["role": .string("mcp")]))

    // stdin -> socket
    DispatchQueue.global().async {
        while let line = readLine(strippingNewline: true) {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { continue }
            try? client.send(value)
        }
        exit(0)
    }
    // socket -> stdout
    while true {
        let response = try client.receive()
        let data = try JSONEncoder().encode(response)
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}

func runDaemon() throws {
    let server = DaemonServer(engine: MacDesktopEngine())
    try server.start()
    FileHandle.standardError.write("tenx-computer daemon listening\n".data(using: .utf8)!)
    dispatchMain()
}

func runStopAll() throws {
    let client = try DaemonClient()
    try client.send(.object(["role": .string("supervision")]))
    try client.send(.object(["command": .string("stop_all")]))
    print("stop_all sent")
}

func requestMissingPermissions(_ permissions: PermissionStatus) {
    if !permissions.screenRecording { CGRequestScreenCaptureAccess() }
    if !permissions.accessibility {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

@MainActor
func runSelfCheck() throws {
    let engine = MacDesktopEngine()
    let permissions = engine.preflightPermissions()
    guard permissions.isComplete else {
        requestMissingPermissions(permissions)
        FileHandle.standardError.write("selfcheck: permissions missing — screen_recording=\(permissions.screenRecording) accessibility=\(permissions.accessibility)\nPermission prompts triggered — grant `tenx-computer` in System Settings > Privacy & Security > Screen Recording and Accessibility, then re-run selfcheck.\n".data(using: .utf8)!)
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "tenx-computer probe"
    let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 280, height: 30))
    field.stringValue = ""
    window.contentView?.addSubview(field)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // Find the probe window through the engine.
    let deadline = Date().addingTimeInterval(5)
    var probe: WindowInfo?
    while Date() < deadline, probe == nil {
        probe = try? engine.listWindows().first(where: { $0.title == "tenx-computer probe" })
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard let probe else { throw ComputerError("selfcheck: probe window not found") }

    // Type into it (background delivery to our own pid).
    try engine.act(.click(point: CGPoint(x: 160, y: 45), button: .left), window: probe)
    try engine.act(.type("hello 10x"), window: probe)

    // Pump the run loop so the events land.
    let settle = Date().addingTimeInterval(1)
    while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

    guard field.stringValue == "hello 10x" else {
        FileHandle.standardError.write("selfcheck: input FAILED — field contains \"\(field.stringValue)\"\n".data(using: .utf8)!)
        exit(1)
    }

    let shot = try engine.screenshot(windowID: probe.id)
    guard shot.pngData.count > 10_000 else {
        FileHandle.standardError.write("selfcheck: capture FAILED — suspiciously small PNG (\(shot.pngData.count) bytes)\n".data(using: .utf8)!)
        exit(1)
    }

    print("selfcheck: OK — input typed, capture \(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))px @\(Int(shot.scale))x")
    exit(0)
}

func runSelfCheckOnMain() throws {
    if Thread.isMainThread {
        try MainActor.assumeIsolated { try runSelfCheck() }
    } else {
        try DispatchQueue.main.sync { try runSelfCheck() }
    }
}

switch arguments.first {
case "daemon": try runDaemon()
case "stop-all": try runStopAll()
case "selfcheck": try runSelfCheckOnMain()
case "mcp", nil: try runMCPFront()
default:
    FileHandle.standardError.write("usage: tenx-computer [mcp|daemon|stop-all|selfcheck]\n".data(using: .utf8)!)
    exit(64)
}
