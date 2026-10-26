import XCTest

/// Native UI command driver. Explicit URL opts in; normal test runs skip it.
/// Business-data interactions require an isolated `.qa` app and INPUT_QA=1.
/// A successful driver run proves only its acknowledged assertions, not a full walkthrough.
final class RunnerUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment
    private var commandURL: URL!
    private var lastSequence = 0
    private var mutationCount = 0
    private var assertionCount = 0
    private var recordedIssueCount = 0

    private var bundleID: String {
        environment["EATWISE_UI_BUNDLE_ID"] ?? "com.jingchang.eatwise"
    }

    private enum DriverError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let message): return message }
        }
    }

    private enum TransportError: Error, CustomStringConvertible {
        case unavailable(String)
        var description: String {
            switch self { case .unavailable(let message): return message }
        }
    }

    private struct HTTPResult {
        let data: Data?
        let status: Int?
        let error: String?
    }

    /// URLSession can finish after cancellation. Closing this box under the lock
    /// makes timeout results final and prevents a late callback racing the reader.
    private final class HTTPResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var closed = false
        private var result: HTTPResult?

        func complete(_ value: HTTPResult) {
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return }
            result = value
        }

        func finish(timedOut: Bool) -> HTTPResult {
            lock.lock()
            defer { lock.unlock() }
            closed = true
            if timedOut {
                return HTTPResult(data: nil, status: nil, error: "HTTP request timed out")
            }
            return result ?? HTTPResult(data: nil, status: nil, error: "HTTP request returned no result")
        }
    }

    override func record(_ issue: XCTIssue) {
        recordedIssueCount += 1
        super.record(issue)
    }

    func testRemoteDriver() throws {
        guard let endpoint = environment["UI_DRIVER_URL"],
              let url = URL(string: endpoint),
              ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil else {
            throw XCTSkip("Set UI_DRIVER_URL explicitly to run the native QA driver")
        }
        guard let token = environment["UI_DRIVER_TOKEN"],
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalid("UI_DRIVER_TOKEN is required for the native QA driver")
        }
        commandURL = url
        continueAfterFailure = true
        NSLog("[ui-driver] target=%@", bundleID)
        let deadline = Date().addingTimeInterval(25 * 60)
        var networkFailureSince: Date?
        while Date() < deadline {
            let requestStarted = Date()
            let remaining = networkFailureSince.map { 30 - requestStarted.timeIntervalSince($0) } ?? 30
            guard remaining > 0 else {
                throw DriverError.invalid("Driver transport unavailable for 30 seconds")
            }
            let command: [String: Any]
            do {
                command = try fetchCommand(timeout: min(10, remaining))
                networkFailureSince = nil
            } catch let error as TransportError {
                networkFailureSince = networkFailureSince ?? requestStarted
                if Date().timeIntervalSince(networkFailureSince!) >= 30 {
                    throw DriverError.invalid("Driver transport unavailable for 30 seconds: \(error)")
                }
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            guard let sequence = (command["seq"] as? NSNumber)?.intValue,
                  sequence > lastSequence else {
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            lastSequence = sequence
            let action = command["action"] as? String ?? "noop"
            var result: [String: Any] = [
                "seq": sequence, "action": action, "bundleId": bundleID,
                "session": command["session"] as? String ?? "", "ok": true,
            ]
            let issuesBefore = recordedIssueCount
            do {
                if let expiry = command["expiresAt"] as? Double,
                   expiry < Date().timeIntervalSince1970 {
                    throw DriverError.invalid("Command expired before execution")
                }
                if action == "quit" {
                    if mutationCount > 0 && assertionCount == 0 {
                        throw DriverError.invalid("A mutating QA run must include explicit assertions")
                    }
                } else {
                    result.merge(try execute(command, action: action)) { _, new in new }
                }
            } catch {
                result["ok"] = false
                result["error"] = String(describing: error)
                XCTFail("Command \(sequence) \(action): \(error)")
            }
            if recordedIssueCount > issuesBefore && result["ok"] as? Bool == true {
                result["ok"] = false
                result["error"] = "XCTest reported an execution issue; inspect the xcresult attachment"
            }
            result["assertionCount"] = assertionCount
            result["mutationCount"] = mutationCount
            guard acknowledge(result) else {
                XCTFail("Failed to acknowledge command \(sequence); stopping to prevent unobserved actions")
                return
            }
            if action == "quit" { return }
        }
        XCTFail("Driver deadline reached without an acknowledged quit")
    }

    private func execute(_ command: [String: Any], action: String) throws -> [String: Any] {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        let mutations: Set<String> = [
            "activate", "tap", "tapLabel", "tapElement", "swipeUp", "swipeDown", "back", "type", "typeFocused",
        ]
        if mutations.contains(action) {
            guard environment["EATWISE_INPUT_QA"] == "1",
                  environment["EATWISE_UI_BUNDLE_ID"] == bundleID,
                  bundleID.hasSuffix(".qa"), bundleID != "com.jingchang.eatwise" else {
                throw DriverError.invalid("Writes require EATWISE_INPUT_QA=1 and an explicit isolated .qa bundle")
            }
            mutationCount += 1
        }
        if action == "activate" {
            app.activate()
            guard app.wait(for: .runningForeground, timeout: 5) else {
                throw DriverError.invalid("QA app did not enter foreground")
            }
            return [:]
        }
        if action == "noop" { return [:] }
        guard app.state == .runningForeground else {
            throw DriverError.invalid("App is not foreground; activate the QA app explicitly")
        }
        let timeout = min(max((command["timeout"] as? NSNumber)?.doubleValue ?? 5, 0.1), 20)
        switch action {
        case "tap":
            guard let x = (command["x"] as? NSNumber)?.doubleValue,
                  let y = (command["y"] as? NSNumber)?.doubleValue,
                  (0...1).contains(x), (0...1).contains(y) else {
                throw DriverError.invalid("tap needs normalized x/y between 0 and 1")
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        case "tapLabel":
            let label = try requiredString(command, "label")
            let candidates = [app.alerts.buttons[label].firstMatch,
                              XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons[label].firstMatch,
                              app.buttons[label].firstMatch, app.staticTexts[label].firstMatch]
            guard waitUntil(timeout, { candidates.contains { $0.exists && $0.isHittable } }),
                  let target = candidates.first(where: { $0.exists && $0.isHittable }) else {
                throw DriverError.invalid("No hittable exact label: \(label)")
            }
            target.tap()
        case "tapElement":
            let target = try element(command, in: app)
            guard waitUntil(timeout, { target.exists && target.isHittable }) else {
                throw DriverError.invalid("Selected element is not hittable")
            }
            target.tap()
        case "swipeUp", "swipeDown":
            let window = app.windows.firstMatch
            guard window.waitForExistence(timeout: timeout) else {
                throw DriverError.invalid("App window missing")
            }
            if action == "swipeUp" { window.swipeUp() } else { window.swipeDown() }
        case "back":
            let back = app.navigationBars.buttons.firstMatch
            guard back.waitForExistence(timeout: timeout), back.isHittable else {
                throw DriverError.invalid("Native back button missing; use the observed Flutter element instead")
            }
            back.tap()
        case "type":
            let target = try element(command, in: app, defaultType: "textField")
            guard target.waitForExistence(timeout: timeout), target.isHittable else {
                throw DriverError.invalid("Selected input is missing or not hittable")
            }
            target.tap()
            guard waitUntil(timeout, { target.hasFocus && app.keyboards.firstMatch.exists }) else {
                throw DriverError.invalid("Input did not acquire keyboard focus")
            }
            app.typeText(try requiredString(command, "text"))
        case "typeFocused":
            // Never activate/tap/re-focus here: that would conceal the lost-input regression.
            guard app.keyboards.firstMatch.exists, let target = focusedInput(in: app) else {
                throw DriverError.invalid("No focused input with a visible keyboard; focus was not repaired")
            }
            let before = safeValue(of: target)
            app.typeText(try requiredString(command, "text"))
            guard target.exists, target.hasFocus else {
                throw DriverError.invalid("Input lost focus during native typing")
            }
            return ["before": before, "after": safeValue(of: target), "keyboardVisible": app.keyboards.firstMatch.exists]
        case "assertKeyboard":
            let expected = command["expected"] as? Bool ?? true
            guard waitUntil(timeout, { app.keyboards.firstMatch.exists == expected }) else {
                throw DriverError.invalid("Keyboard visibility did not become \(expected)")
            }
            assertionCount += 1
        case "assertValue":
            let target = try element(command, in: app, defaultType: "textField")
            let expected = try requiredString(command, "expected", allowEmpty: true)
            let contains = command["contains"] as? Bool ?? false
            guard waitUntil(timeout, {
                guard target.exists else { return false }
                let actual = target.value as? String ?? ""
                return contains ? actual.contains(expected) : actual == expected
            }) else {
                throw DriverError.invalid("Input value assertion failed; actual=\(safeValue(of: target))")
            }
            assertionCount += 1
        case "assertVisible":
            let target = try element(command, in: app)
            let expected = command["expected"] as? Bool ?? true
            guard waitUntil(timeout, { (target.exists && target.isHittable) == expected }) else {
                throw DriverError.invalid("Element hittability assertion failed")
            }
            assertionCount += 1
        case "assertAboveKeyboard":
            let target = try element(command, in: app)
            let keyboard = app.keyboards.firstMatch
            guard waitUntil(timeout, {
                target.exists && target.isHittable && keyboard.exists && !target.frame.isEmpty &&
                    target.frame.maxY <= keyboard.frame.minY + 1
            }) else {
                throw DriverError.invalid("Element is missing, not hittable or overlaps the keyboard")
            }
            assertionCount += 1
        case "dump":
            return ["tree": app.debugDescription,
                    "systemAlerts": XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.debugDescription,
                    "keyboardVisible": app.keyboards.firstMatch.exists]
        case "screenshot":
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "qa-command-\(lastSequence)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return ["screenshotBase64": shot.pngRepresentation.base64EncodedString()]
        default:
            throw DriverError.invalid("Unknown action: \(action)")
        }
        return ["keyboardVisible": app.keyboards.firstMatch.exists]
    }

    private func element(_ command: [String: Any], in app: XCUIApplication,
                         defaultType: String = "any") throws -> XCUIElement {
        let kind = command["elementType"] as? String ?? defaultType
        var query: XCUIElementQuery
        switch kind {
        case "textField": query = app.textFields
        case "secureTextField": query = app.secureTextFields
        case "textView": query = app.textViews
        case "searchField": query = app.searchFields
        case "button": query = app.buttons
        case "staticText": query = app.staticTexts
        case "any": query = app.descendants(matching: .any)
        default: throw DriverError.invalid("Unknown elementType: \(kind)")
        }
        if let identifier = command["identifier"] as? String {
            query = query.matching(identifier: identifier)
        }
        if let label = command["label"] as? String {
            query = query.matching(NSPredicate(format: "label == %@", label))
        }
        let index = (command["index"] as? NSNumber)?.intValue ?? 0
        guard index >= 0 else { throw DriverError.invalid("Element index must be nonnegative") }
        return query.element(boundBy: index)
    }

    private func focusedInput(in app: XCUIApplication) -> XCUIElement? {
        [app.textFields, app.secureTextFields, app.textViews, app.searchFields]
            .flatMap { $0.allElementsBoundByIndex }.first { $0.exists && $0.hasFocus }
    }

    private func safeValue(of element: XCUIElement) -> String {
        if element.elementType == .secureTextField { return "<secure>" }
        return element.value as? String ?? ""
    }

    private func requiredString(_ command: [String: Any], _ key: String, allowEmpty: Bool = false) throws -> String {
        guard let value = command[key] as? String, allowEmpty || !value.isEmpty else {
            throw DriverError.invalid("Missing string: \(key)")
        }
        return value
    }

    private func waitUntil(_ seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return predicate()
    }

    private func request(_ url: URL, body: [String: Any]? = nil, timeout: TimeInterval = 10) -> HTTPResult {
        let resultBox = HTTPResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: timeout)
        if let token = environment["UI_DRIVER_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let task = URLSession.shared.dataTask(with: request) { received, response, error in
            resultBox.complete(HTTPResult(data: received,
                                          status: (response as? HTTPURLResponse)?.statusCode,
                                          error: error?.localizedDescription))
            semaphore.signal()
        }
        task.resume()
        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        let result = resultBox.finish(timedOut: timedOut)
        if timedOut { task.cancel() }
        return result
    }

    private func fetchCommand(timeout: TimeInterval) throws -> [String: Any] {
        let response = request(commandURL, timeout: timeout)
        guard let status = response.status else {
            throw TransportError.unavailable(response.error ?? "Missing HTTP response")
        }
        if (500...599).contains(status) {
            throw TransportError.unavailable("Driver returned HTTP \(status)")
        }
        guard status == 200 else {
            throw DriverError.invalid("Driver command endpoint returned HTTP \(status)")
        }
        guard let bytes = response.data,
              let result = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let sequence = result["seq"] as? NSNumber,
              sequence.doubleValue.isFinite, sequence.intValue >= 0,
              sequence.doubleValue == Double(sequence.intValue),
              let action = result["action"] as? String, !action.isEmpty,
              let session = result["session"] as? String, !session.isEmpty else {
            throw DriverError.invalid("Driver returned an invalid command envelope")
        }
        if sequence.intValue > 0 {
            guard let expiry = result["expiresAt"] as? Double, expiry.isFinite else {
                throw DriverError.invalid("Driver command is missing a valid expiry")
            }
        } else if action != "noop" {
            throw DriverError.invalid("Driver idle envelope must use noop")
        }
        return result
    }

    private func acknowledge(_ result: [String: Any]) -> Bool {
        let endpoint = commandURL.deletingLastPathComponent().appendingPathComponent("ack")
        return request(endpoint, body: result).status == 200
    }
}
