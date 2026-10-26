# Native input QA driver

This driver controls only the explicitly selected app. It does not call the business API or create accounts. Run writing scenarios in an isolated QA app and a local `STORE_DRIVER=memory` backend. Do not replace the installed production app with a test app that uses the same bundle ID.

## Prepare the isolated app

Use a disposable copy of the current source after generation, with separate build directories:

- Runner bundle: `com.jingchang.eatwise.qa`, display name `EatWise QA`.
- RunnerUITests bundle: `com.jingchang.eatwise.qa.uitests`.
- API: `http://<Mac-LAN-IP>:3011/v1`; register the QA account only against this memory backend.
- Keep the production workspace's signing and bundle configuration intact. Check the built Info.plist, production-address absence and signature before installing.
- The existing development wildcard profile can cover the QA bundle, but does not grant HealthKit. If needed, use empty entitlements only in the disposable copy. That run does not validate HealthKit.

`integration_test/ui_walkthrough_test.dart` uses `tester.enterText` and writes records/water. It is not a native keyboard connection regression. Do not run its old production-URL example. The native driver below supports typing without reacquiring focus.

## Start transport

From `eatwise_app/`:

```bash
python3 tool/native_ui_driver.py serve \
  --bind <Mac-LAN-IP> \
  --directory /tmp/eatwise-native-qa-141
```

For a simulator, use `127.0.0.1`. A specific private LAN IPv4 is required for an iPhone; wildcard/public binds are rejected. Use a fresh directory for each run. The server prints the origin, artifact directory and token-file path. The token file is mode 0600, the directory mode 0700. Only this small directory is exposed through the command protocol; there is no general file server.

Inject these variables **into the XCTest runner's environment**, not only the shell that runs `xcodebuild`:

```text
UI_DRIVER_URL=http://<Mac-LAN-IP>:8899/cmd.json
UI_DRIVER_TOKEN=<contents of the printed access-token file>
EATWISE_UI_BUNDLE_ID=com.jingchang.eatwise.qa
EATWISE_INPUT_QA=1
```

A practical route is `xcodebuild build-for-testing` with a dedicated DerivedData directory, then set the RunnerUITests entry's `EnvironmentVariables` in the generated `.xctestrun` and run `xcodebuild test-without-building -xctestrun ... -only-testing:RunnerUITests -destination id=<device>`. The exact `.xctestrun` schema depends on Xcode; inspect its target entries first. Do not assume arbitrary shell variables propagate into a test runner.

Without an explicit `UI_DRIVER_URL`, `testRemoteDriver` skips. Without an explicit `.qa` target plus `EATWISE_INPUT_QA=1`, all activation/tap/swipe/typing commands fail. Read-only inspection does not automatically launch or foreground any app.

Once a driver URL is supplied, a nonempty `UI_DRIVER_TOKEN` is required. HTTP authentication/path errors and malformed command envelopes fail immediately; continuous network/server failures stop the run after 30 seconds. A timed-out request discards late completion data, and a failed ACK stops further actions.

## Send one command and await its acknowledgement

```bash
python3 tool/native_ui_driver.py send \
  --url http://<Mac-LAN-IP>:8899 \
  --token-file /tmp/eatwise-native-qa-141/access-token \
  --json '{"action":"activate"}'
```

Use `--command-file` for multiline input. The command timeout defaults to 40 seconds; an absent ACK is a failure, never success. A second command is rejected while the first is pending. Every request has a sequence, a session identity and an expiry. Artifacts include command/ack JSON, native screenshots and UI trees. QA login commands can contain the local test password, so keep these files local and do not commit them.

Supported commands (send each JSON object separately):

```json
{"action":"dump"}
{"action":"screenshot"}
{"action":"tapLabel","label":"记录"}
{"action":"tapElement","elementType":"textField","index":0}
{"action":"type","elementType":"secureTextField","index":0,"text":"local-test-password"}
{"action":"typeFocused","text":"米饭"}
{"action":"assertValue","elementType":"textField","index":0,"expected":"米饭"}
{"action":"assertKeyboard","expected":true}
{"action":"assertVisible","elementType":"button","label":"确认记录"}
{"action":"assertAboveKeyboard","elementType":"button","label":"确认记录"}
{"action":"tap","x":0.5,"y":0.4}
{"action":"swipeUp"}
{"action":"quit"}
```

Selectors accept `elementType` (`any`, `button`, `staticText`, `textField`, `secureTextField`, `searchField`, `textView`), exact `identifier`, exact `label`, and a zero-based `index`. Obtain selectors from `dump`; do not guess Flutter accessibility labels. `tapLabel` uses exact, hittable labels and can handle the QA app/SpringBoard permission alert buttons. `back` is only for an actual native navigation-bar button; use an observed selector for Flutter back buttons.

`typeFocused` sends native typing to the already foreground app. It does not activate or tap, and fails if the keyboard/focused field is absent. `type` intentionally taps a selected input first and is suitable for login setup, **not** for proving a surviving input connection. `assertValue` supports `"contains":true`; keyboard/value/visibility assertions accept a `timeout` of up to 20 seconds.

Failures create both `XCTFail` and `ok:false` ACKs. XCTest's own execution issues also produce a failed ACK. A run that performs interactions must include at least one explicit assertion before `quit`. Preserve the `.xcresult` and the ACKs for evidence; a completed driver alone is not a full UI pass.

## Minimal input scenarios

1. In the isolated QA app, complete onboarding and log into the local account. Inspect the UI tree, then select the record search input.
2. Native-type the first food, assert the value/keyboard, open details, enter a valid amount and assert the confirm action is hittable and above the keyboard. Save to the local backend.
3. Tap the next search input once, then send successive `typeFocused` commands while keyboard/sync UI changes. Assert the full accumulated text; never use `type` to repair a lost focus before the assertion.
4. Record the second food; verify the local backend has exactly the two intended records. Edit a portion and verify an update rather than a duplicate.
5. Capture the details screen with the keyboard visible, and repeat the relevant paths in dark mode/English/large type. These are separate scenarios, not implied by a single successful run.

If the OS keyboard uses phonetic composition, validate the composition/candidate interaction separately; `typeText` alone is not evidence that every input-method composing sequence works.

## AI boundary

No model download is started by the driver. Verify missing-model, declined-permission and manual-entry exits first. Existing unit-test image/WAV bytes are fake fixtures, not accuracy evidence. Controlled label images or synthetic speech can validate transport/parsing/capability, but real-photo accuracy and human-speech quality require representative fixtures and an installed model. A simulator does not replace an Android/iPhone device performance or memory test.
