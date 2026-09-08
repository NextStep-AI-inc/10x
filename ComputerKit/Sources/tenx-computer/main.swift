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

// Separate-process probe: a real AppKit app with a text field that never
// activates. Writes the field's content to the given file on a timer so the
// parent selfcheck can verify background input landed.
func runProbe(outPath: String) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "tenx-computer probe"
    let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 280, height: 30))
    field.stringValue = ""
    window.contentView?.addSubview(field)
    window.orderFront(nil)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
        try? field.stringValue.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
    app.run()
}

func runSelfCheck() throws {
    let engine = MacDesktopEngine()
    let permissions = engine.preflightPermissions()
    guard permissions.isComplete else {
        requestMissingPermissions(permissions)
        FileHandle.standardError.write("selfcheck: permissions missing — screen_recording=\(permissions.screenRecording) accessibility=\(permissions.accessibility)\nPermission prompts triggered — grant `tenx-computer` in System Settings > Privacy & Security > Screen Recording and Accessibility, then re-run selfcheck.\n".data(using: .utf8)!)
        exit(1)
    }

    // Cross-process probe: spawn `tenx-computer probe` (a separate process with
    // its own window that never takes focus), drive it through the engine.
    let outPath = NSTemporaryDirectory() + "tenx-computer-selfcheck-\(ProcessInfo.processInfo.processIdentifier).txt"
    defer { try? FileManager.default.removeItem(atPath: outPath) }
    let probeProcess = Process()
    probeProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    probeProcess.arguments = ["probe", outPath]
    probeProcess.standardOutput = FileHandle.nullDevice
    probeProcess.standardError = FileHandle.nullDevice
    try probeProcess.run()
    defer { probeProcess.terminate() }

    let deadline = Date().addingTimeInterval(5)
    var probe: WindowInfo?
    while Date() < deadline, probe == nil {
        Thread.sleep(forTimeInterval: 0.2)
        probe = try? engine.listWindows().first(where: { $0.title == "tenx-computer probe" && $0.pid == probeProcess.processIdentifier })
    }
    guard let probe else {
        FileHandle.standardError.write("selfcheck: probe window not found\n".data(using: .utf8)!)
        exit(1)
    }

    // Click the field: frame-relative top-left. Field center is 55pt above the
    // content bottom; bounds include the title bar, so y = height - 55.
    let clickPoint = CGPoint(x: 160, y: probe.bounds.height - 55)
    try engine.act(.click(point: clickPoint, button: .left), window: probe)
    try engine.act(.type("hello 10x"), window: probe)
    Thread.sleep(forTimeInterval: 1.5)

    let typed = (try? String(contentsOfFile: outPath, encoding: .utf8)) ?? ""
    guard typed == "hello 10x" else {
        FileHandle.standardError.write("selfcheck: input FAILED — probe field contains \"\(typed)\"\n".data(using: .utf8)!)
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

do {
    switch arguments.first {
    case "daemon": try runDaemon()
    case "stop-all": try runStopAll()
    case "selfcheck": try runSelfCheck()
    case "probe":
        guard let outPath = arguments.dropFirst().first else {
            FileHandle.standardError.write("usage: tenx-computer probe <outfile>\n".data(using: .utf8)!)
            exit(64)
        }
        try runProbe(outPath: outPath)
    case "mcp", nil: try runMCPFront()
    default:
        FileHandle.standardError.write("usage: tenx-computer [mcp|daemon|stop-all|selfcheck]\n".data(using: .utf8)!)
        exit(64)
    }
} catch {
    FileHandle.standardError.write("tenx-computer: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
