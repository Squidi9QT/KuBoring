import XCTest
@testable import KuBoringCore

@MainActor
final class LowPowerScheduleTests: XCTestCase {
    private func output(battery: Int, adapter: Int) -> String {
        """
        Battery Power:
         Sleep On Power Button 1
         lowpowermode         \(battery)
         standby              1
        AC Power:
         Sleep On Power Button 1
         lowpowermode         \(adapter)
         womp                 1
        """
    }

    func testParsesAllSchedules() {
        XCTAssertEqual(BatteryMonitor.parseSchedule(output(battery: 0, adapter: 0)), .never)
        XCTAssertEqual(BatteryMonitor.parseSchedule(output(battery: 1, adapter: 1)), .always)
        XCTAssertEqual(BatteryMonitor.parseSchedule(output(battery: 1, adapter: 0)), .onBattery)
        XCTAssertEqual(BatteryMonitor.parseSchedule(output(battery: 0, adapter: 1)), .onAdapter)
    }

    func testHighPowerValueCountsAsOff() {
        // На некоторых MacBook Pro lowpowermode 2 — «высокая мощность»; для нас это не энергосбережение.
        XCTAssertEqual(BatteryMonitor.parseSchedule(output(battery: 0, adapter: 2)), .never)
    }

    func testDesktopWithOnlyACSection() {
        let text = "AC Power:\n lowpowermode         1\n"
        XCTAssertEqual(BatteryMonitor.parseSchedule(text), .always)
    }
}

final class PrivilegedPmsetTests: XCTestCase {
    func testParsesSleepDisabled() {
        XCTAssertTrue(PrivilegedPmset.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n"))
        XCTAssertFalse(PrivilegedPmset.parseSleepDisabled(" SleepDisabled\t\t0\n"))
        XCTAssertFalse(PrivilegedPmset.parseSleepDisabled(""))
    }

    func testCommandsMatchRule() {
        let rule = PrivilegedPmset.ruleText(user: "me")
        for command: PrivilegedPmset.Command in [.disableSleep(true), .lowPowerOnBattery(false), .lowPowerOnAdapter(true)] {
            // Команда с маской [01] вместо значения должна быть в правиле дословно.
            var args = command.arguments
            args[args.count - 1] = "[01]"
            XCTAssertTrue(rule.contains("/usr/bin/pmset " + args.joined(separator: " ")), "\(command)")
        }
    }
}
