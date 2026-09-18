import XCTest

/// 远程点屏驱动：轮询 Mac 上的 cmd.json，把命令翻译成 XCUITest 动作，
/// 用于 devicectl 截屏 + 命令行驱动的真机 UI 走查（可点自家 App 与第三方 App）。
final class RunnerUITests: XCTestCase {

    private let commandURL = URL(string: "http://172.23.28.168:8899/cmd.json")!
    private let bundleIds: [String: String] = [
        "eatwise": "com.jingchang.eatwise",
        "boohee": "com.boohee.food",
    ]

    func testRemoteDriver() {
        let deadline = Date().addingTimeInterval(25 * 60)
        var lastSeq = 0

        driverLoop: while Date() < deadline {
            guard let cmd = fetchCommand(),
                  let seq = (cmd["seq"] as? NSNumber)?.intValue,
                  seq > lastSeq
            else {
                Thread.sleep(forTimeInterval: 0.8)
                continue
            }
            lastSeq = seq

            let action = cmd["action"] as? String ?? "noop"
            if action == "quit" {
                break driverLoop
            }
            execute(cmd: cmd, action: action)
        }

        XCTAssertTrue(true, "remote driver loop finished")
    }

    private func execute(cmd: [String: Any], action: String) {
        let appKey = cmd["app"] as? String ?? "eatwise"
        let bundleId = bundleIds[appKey] ?? bundleIds["eatwise"]!
        let app = XCUIApplication(bundleIdentifier: bundleId)

        switch action {
        case "activate":
            app.activate()

        case "tap":
            bringToForeground(app)
            let x = (cmd["x"] as? NSNumber)?.doubleValue ?? 0.5
            let y = (cmd["y"] as? NSNumber)?.doubleValue ?? 0.5
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()

        case "swipeUp":
            bringToForeground(app)
            let win = app.windows.element(boundBy: 0)
            if win.waitForExistence(timeout: 5) {
                win.swipeUp()
            }

        case "swipeDown":
            bringToForeground(app)
            let win = app.windows.element(boundBy: 0)
            if win.waitForExistence(timeout: 5) {
                win.swipeDown()
            }

        case "back":
            bringToForeground(app)
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 3) {
                back.tap()
            }

        case "tapLabel":
            bringToForeground(app)
            guard let label = cmd["label"] as? String, !label.isEmpty else {
                NSLog("[ui-driver] tapLabel: missing label")
                break
            }
            NSLog("[ui-driver] tapLabel: looking for '%@'", label)
            let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", label, label)
            let fuzzy = app.descendants(matching: .any).matching(predicate).firstMatch
            if fuzzy.waitForExistence(timeout: 2) {
                NSLog("[ui-driver] tapLabel: found (fuzzy), tapped '%@'", label)
                fuzzy.tap()
                break
            }
            let exactStatic = app.staticTexts[label].firstMatch
            if exactStatic.waitForExistence(timeout: 2) {
                NSLog("[ui-driver] tapLabel: found (staticText exact), tapped '%@'", label)
                exactStatic.tap()
                break
            }
            let exactButton = app.buttons[label].firstMatch
            if exactButton.waitForExistence(timeout: 2) {
                NSLog("[ui-driver] tapLabel: found (button exact), tapped '%@'", label)
                exactButton.tap()
                break
            }
            NSLog("[ui-driver] tapLabel: notfound '%@'", label)

        case "type":
            bringToForeground(app)
            guard let text = cmd["text"] as? String, !text.isEmpty else {
                NSLog("[ui-driver] type: missing text")
                break
            }
            let field = app.textFields.element(boundBy: 0)
            let search = app.searchFields.element(boundBy: 0)
            if search.waitForExistence(timeout: 2) {
                if !search.hasFocus {
                    search.tap()
                    Thread.sleep(forTimeInterval: 0.5)
                }
                search.typeText(text)
                NSLog("[ui-driver] type: typed into searchField '%@'", text)
            } else if field.waitForExistence(timeout: 2) {
                if !field.hasFocus {
                    field.tap()
                    Thread.sleep(forTimeInterval: 0.5)
                }
                field.typeText(text)
                NSLog("[ui-driver] type: typed into textField '%@'", text)
            } else {
                NSLog("[ui-driver] type: nofield for '%@'", text)
            }

        default:
            break
        }
    }

    private func bringToForeground(_ app: XCUIApplication) {
        if app.state != .runningForeground {
            app.activate()
        }
        _ = app.wait(for: .runningForeground, timeout: 5)
    }

    /// UI test bundle 里没有 RunLoop 驱动的异步环境，用 semaphore 同步等 URLSession。
    private func fetchCommand() -> [String: Any]? {
        var result: [String: Any]?
        let semaphore = DispatchSemaphore(value: 0)
        let request = URLRequest(url: commandURL,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 3)
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = obj
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }
}
