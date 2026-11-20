import AppKit
import ApplicationServices
import Foundation

let help = """
cordkey — map USB/HID headset buttons (Consumer & Telephony pages) to keyboard keys.

Usage:
  cordkey --menubar          launch macOS menu bar icon app (default inside CordKey.app)
  cordkey [button flags] [options]
  cordkey devices            list connected HID headsets (Consumer & Telephony pages)
  cordkey probe              print raw button events from ALL connected USB headsets
  cordkey watch              print keyboard & media events the system sees (to verify)
  cordkey keys               list supported key names and aliases

Button flags (KEY is a key name or chord: f13, space, right_option, fn, cmd+shift+space):
  --play KEY                Consumer Play/Pause (0x0c:0xcd) [default: f13]
  --vol-up KEY              Consumer Volume Up (0x0c:0xe9)
  --vol-down KEY            Consumer Volume Down (0x0c:0xea)
  --mute KEY                Consumer Audio Mute (0x0c:0xe2)
  --voice KEY               Consumer Voice Command (0x0c:0xcf)
  --mic-mute KEY            Telephony Phone/Mic Mute (0x0b:0x2f, Jabra/Poly/Logitech)
  --hook KEY                Telephony Hook Switch / Call (0x0b:0x20)
  --button SPEC KEY         map arbitrary button SPEC (e.g. 0x0b:0x2f or mic-mute) to KEY

Options:
  --menubar                 start as a macOS menu bar status icon (settings saved)
  --vendor ID               headset USB vendor id  (default 0x05ac, Apple)
  --product ID              headset USB product id (default 0x110b, USB-C EarPods)
  --hold-ms MS              require holding >= MS ms to trigger; shorter taps pass through
  --tap KEY                 remap short tap (with --hold-ms) on Play button to KEY
  --double-tap KEY          remap double tap (with --hold-ms) on Play button to KEY
  --toggle                  tap once to hold key down (triggers cleanly after release),
                            tap again to release immediately
  --repeat                  emit key-repeat events while holding a non-modifier key
  --sound                   play subtle system sound cue on key engage/release
  --no-seize                don't take exclusive access (original button action still fires)
  --no-prompt               don't show system Accessibility permission dialog on startup
  -v, --verbose             log raw button events
  -h, --help                show this help
"""

func parseInt(_ s: String) -> Int? {
    s.lowercased().hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) : Int(s)
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n\nRun `cordkey --help` for usage.\n").data(using: .utf8)!)
    exit(2)
}

var mappings: [HIDButton: KeyCombo] = [:]
var tapCombos: [HIDButton: KeyCombo] = [:]
var doubleTapCombos: [HIDButton: KeyCombo] = [:]
var vendor = 0x05ac
var product = 0x110b
var seize = true
var verbose = false
var toggle = false
var holdMs = 0
var keyRepeat = false
var soundFeedback = false
var promptAX = true
var menubarMode = Bundle.main.bundlePath.hasSuffix(".app")

// Ignore LaunchServices -psn_* arguments passed when opened as a .app bundle.
var args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
func value(for flag: String) -> String {
    guard !args.isEmpty else { die("missing value for \(flag)") }
    return args.removeFirst()
}
func combo(for flag: String) -> KeyCombo {
    let v = value(for: flag)
    guard let c = KeyCombo.parse(v) else { die("unknown key '\(v)' (see `cordkey keys`)") }
    return c
}

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--menubar": menubarMode = true
    case "--cli": menubarMode = false
    case "--play": menubarMode = false; mappings[.play] = combo(for: a)
    case "--vol-up": menubarMode = false; mappings[.volUp] = combo(for: a)
    case "--vol-down": menubarMode = false; mappings[.volDown] = combo(for: a)
    case "--mute": menubarMode = false; mappings[.mute] = combo(for: a)
    case "--voice": menubarMode = false; mappings[.voice] = combo(for: a)
    case "--mic-mute": menubarMode = false; mappings[.micMute] = combo(for: a)
    case "--hook": menubarMode = false; mappings[.hook] = combo(for: a)
    case "--button":
        menubarMode = false
        let spec = value(for: a)
        guard let btn = HIDButton.parse(spec) else { die("bad --button spec '\(spec)' (use e.g. mic-mute or 0x0b:0x2f)") }
        mappings[btn] = combo(for: a)
    case "--vendor":
        guard let v = parseInt(value(for: a)) else { die("bad --vendor") }
        vendor = v
    case "--product":
        guard let v = parseInt(value(for: a)) else { die("bad --product") }
        product = v
    case "--hold-ms":
        guard let ms = Int(value(for: a)), ms >= 0 else { die("bad --hold-ms (must be >= 0)") }
        holdMs = ms
    case "--tap":
        menubarMode = false
        tapCombos[.play] = combo(for: a)
    case "--double-tap":
        menubarMode = false
        doubleTapCombos[.play] = combo(for: a)
    case "--toggle": toggle = true
    case "--repeat": keyRepeat = true
    case "--sound": soundFeedback = true
    case "--no-seize": seize = false
    case "--no-prompt": promptAX = false
    case "--write-iconset": IconGenerator.writeIconset(to: value(for: a))
    case "-v", "--verbose": verbose = true
    case "devices":
        let list = HIDListener.listHeadsetDevices()
        if list.isEmpty {
            print("No HID Consumer/Telephony headset devices found (Input Monitoring permission may be required).")
        } else {
            for d in list {
                let mark = (d.vendorID == 0x05ac && d.productID == 0x110b) ? "  [default]" : ""
                let mfg = d.manufacturer.isEmpty ? "" : " — \(d.manufacturer)"
                print(String(format: "0x%04x  0x%04x  %-8s  %-18s  %@%@%@",
                             d.vendorID, d.productID,
                             (d.transport as NSString).utf8String!,
                             (d.pagesLabel as NSString).utf8String!,
                             d.product, mfg, mark))
            }
        }
        exit(0)
    case "probe": HIDProbe.run()
    case "watch": Watch.run()
    case "keys":
        print(KeyTable.allNames.joined(separator: " "))
        print("\naliases: " + KeyTable.aliasList.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
        exit(0)
    case "-h", "--help":
        print(help)
        exit(0)
    default:
        die("unknown argument '\(a)'")
    }
}

if menubarMode {
    MenuBarApp.run(promptAX: promptAX, verbose: verbose)
}

if toggle && holdMs > 0 {
    die("--toggle and --hold-ms cannot be used together")
}
if !tapCombos.isEmpty || !doubleTapCombos.isEmpty {
    if toggle {
        die("--tap and --double-tap cannot be used with --toggle")
    }
    if holdMs <= 0 {
        die("--tap and --double-tap require --hold-ms > 0")
    }
}
if mappings.isEmpty {
    mappings[.play] = KeyCombo.parse("f13")!
}

// Accessibility is required to post synthetic key events.
let axOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptAX] as CFDictionary
if !AXIsProcessTrustedWithOptions(axOpts) {
    log("WARNING: no Accessibility permission — key events will be dropped. Grant it in System Settings → Privacy & Security → Accessibility, then restart cordkey.")
}

let mapper = ButtonMapper(config: .init(
    mappings: mappings,
    tapCombos: tapCombos,
    doubleTapCombos: doubleTapCombos,
    toggle: toggle,
    holdMs: holdMs,
    keyRepeat: keyRepeat,
    soundFeedback: soundFeedback,
    verbose: verbose
))

let listener = HIDListener(
    vendor: vendor,
    product: product,
    onInput: { button, down in
        mapper.handle(button: button, down: down)
    },
    onDisconnect: {
        mapper.releaseAll(reason: "headset disconnected")
    }
)

guard listener.start(seize: seize) else {
    log(String(format: "cannot open headset 0x%04x/0x%04x — is it plugged in? Input Monitoring may be required.", vendor, product))
    exit(1)
}
mapper.seized = listener.seized

for (b, c) in mappings.sorted(by: { $0.key < $1.key }) {
    var detail: [String] = []
    if toggle { detail.append("toggle") }
    if holdMs > 0 {
        let tapDesc = tapCombos[b].map(\.description) ?? "passthrough"
        var holdDesc = "hold >= \(holdMs)ms, tap = \(tapDesc)"
        if let dt = doubleTapCombos[b] {
            holdDesc += ", double-tap = \(dt)"
        }
        detail.append(holdDesc)
    }
    if keyRepeat && c.hasNonModifier { detail.append("repeat") }
    let suffix = detail.isEmpty ? "" : " (\(detail.joined(separator: ", ")))"
    log("map \(b.shortName) [\(b.codeTag)] → \(c)\(suffix)")
}
log("running (\(listener.seized ? "exclusive" : "shared") mode). Ctrl+C to quit.")

// Release held keys before system sleep so keys are never stuck across sleep/wake.
let sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.willSleepNotification,
    object: nil,
    queue: .main
) { _ in
    mapper.releaseAll(reason: "system sleep")
}

// Handle SIGINT / SIGTERM cleanly on main queue so held keys are never left stuck.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let shutdown: () -> Void = {
    NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
    mapper.releaseAll(reason: "exit")
    listener.stop()
    log("stopped.")
    exit(0)
}
let sigInt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigInt.setEventHandler(handler: shutdown)
sigInt.resume()

let sigTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigTerm.setEventHandler(handler: shutdown)
sigTerm.resume()

CFRunLoopRun()
