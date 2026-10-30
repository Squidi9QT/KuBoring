import Foundation

enum PrivilegedPmset {
    enum Command: Equatable {
        case lowPowerOnBattery(Bool)
        case lowPowerOnAdapter(Bool)
        case disableSleep(Bool)

        var arguments: [String] {
            switch self {
            case .lowPowerOnBattery(let on): return ["-b", "lowpowermode", on ? "1" : "0"]
            case .lowPowerOnAdapter(let on): return ["-c", "lowpowermode", on ? "1" : "0"]
            case .disableSleep(let on): return ["-a", "disablesleep", on ? "1" : "0"]
            }
        }
    }

    enum Outcome: Equatable { case done, cancelled, failed }

    static let sudoersPath = "/private/etc/sudoers.d/kuboring-lowpower"

    static var ruleInstalled: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    static func ruleText(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode [01], /usr/bin/pmset -c lowpowermode [01], "
            + "/usr/bin/pmset -a disablesleep [01]\n"
    }

    static func run(_ commands: [Command], prompt: String) async -> Outcome {
        if await runPasswordless(commands) { return .done }
        let result = await runWithAdmin(commands, prompt: prompt)
        if result.status == 0 { return .done }
        return result.error.contains("-128") ? .cancelled : .failed
    }

    private static func runPasswordless(_ commands: [Command]) async -> Bool {
        guard ruleInstalled else { return false }
        for command in commands {
            let r = await exec("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + command.arguments)
            if r.status != 0 { return false }
        }
        return true
    }

    private static func runWithAdmin(_ commands: [Command], prompt: String) async -> (status: Int32, error: String) {
        let pmset = commands.map { "/usr/bin/pmset " + $0.arguments.joined(separator: " ") }.joined(separator: " && ")
        var shell = pmset
        if let rule = writeRuleFile() {
            shell =
                "(/usr/sbin/visudo -cf \(rule) && /usr/bin/install -m 0440 -o root -g wheel \(rule) \(sudoersPath)); "
                + "/bin/rm -f \(rule); " + pmset
        }
        let safePrompt = prompt.replacingOccurrences(of: "\"", with: "'")
        let script = "do shell script \"\(shell)\" with administrator privileges with prompt \"\(safePrompt)\""
        let r = await exec("/usr/bin/osascript", ["-e", script])
        return (r.status, r.error)
    }

    private static func writeRuleFile() -> String? {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy(\.isASCII),
            user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
        else { return nil }
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("kuboring-lowpower-\(UUID().uuidString)")
        guard !path.contains(" "), !path.contains("\""), !path.contains("'"),
            (try? ruleText(user: user).write(toFile: path, atomically: true, encoding: .utf8)) != nil
        else { return nil }
        return path
    }

    static func exec(_ executable: String, _ args: [String]) async -> (status: Int32, output: String, error: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return (-1, "", error.localizedDescription) }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
        }.value
    }

    static func sleepDisabled() async -> Bool {
        let out = await exec("/usr/bin/pmset", ["-g"]).output
        return parseSleepDisabled(out)
    }

    static func parseSleepDisabled(_ text: String) -> Bool {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return false
    }
}
