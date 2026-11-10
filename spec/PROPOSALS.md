# Proposals: gates and first fixes for Ding

These are proposals for the factory's gates. Nothing here has been applied.

## Candidate frozen paths (change only with an explicit owner decision)

These carry security or privacy guarantees that users and App Review rely on. A diff here should fail the gate unless the change
also updates the matching requirement rows.

- `Ding/Ding.entitlements`, `DingMCPHelper/DingMCP.entitlements`: sandbox, calendars and app group only, and no network
  (DING-PLAT-002, DING-PLAT-003). Adding `com.apple.security.network.*` would break the privacy promise.
- `Ding/PrivacyInfo.xcprivacy`: no tracking, no collected data (DING-PLAT-006).
- `Sources/DingIPC/DingIPC.swift` (`codeSigningRequirement`, `helperIdentifier`, `socketURL`) and `Sources/DingIPC/ControlSocket.swift`
  (peer check before the first read, 0600 socket, connection cap, idle timeout): DING-IPC-002 to DING-IPC-010.
- `Sources/DingCore/Control.swift` `MeetingSummary` and `ControlAPI.canOpen`: a summary has no field for notes, attendees,
  locations or links, and assistants open only known services (DING-CTRL-004, DING-CTRL-007, DING-CTRL-010).

## Candidate protected paths (changes need review against the spec)

The policy already protects `Tests/**`, `DingTests/**`, `scripts/*_test.ts`, `Makefile`, `make/**`, `project.yml`, the entitlements,
the privacy manifest, `secrets/**` and the spec generator files. Also worth protecting:

- `Ding/ControlService.swift`: permission checks, the 3 s open rate limit, and no title in refusals (DING-CTRL-001, -002, -012 to -014).
- `Sources/DingMCP/Tools.swift`: the tool descriptions and instructions are what every model reads. They carry the untrusted-title
  warning (DING-MCP-005, DING-MCP-011) and currently contain the `joined` vs `opened` conflict (DING-MCP-019).
- `Ding/Info.plist`, `DingMCPHelper/Info.plist`: one-instance rule, calendar usage text, encryption flag, app group key.
- `listing/metadata.json`, `listing/app.json`, `listing/screenshots/**`: the public store listing, validated by the Deno tests.
- `Sources/DingCore/MeetingLinkDetector.swift` (`LinkPatterns`): the lookalike-host and non-meeting-page rules (DING-LINK-006).

## Review rules

1. A change to any file under `Sources/` or `Ding/` that alters a statement in `spec/requirements.tsv` must update that row in the
   same change (this is SPEC.md's own Decision, DING-PROC-004, which nothing enforces today).
2. A row may be marked `C` only if its evidence names a test that asserts the whole statement. Reviewers should re-read the test body.
   The tests listed in DRIFT_REPORT.md section 4 must not be cited as evidence until they are strengthened.
3. No change may add a network API (URLSession, NWConnection and similar) or a network entitlement (DING-PLAT-009) without an owner decision.
4. Any change to what a control response contains must keep `DingTests/ControlServiceTests.swift`
   "testNoResponseEverContainsALinkOrItsPasscode" passing and extend it to the new field.
5. Conflicts (X rows) are settled by the owner, not by an implementer. The resolution updates both sides and retires or rewrites the row.
6. App tests must not touch the real system. New tests use the existing fakes, and `AppModel()` (the non-test initializer)
   must not appear in tests (DING-TEST-001).

## What to fix first

1. **DING-MCP-019: the `open_meeting` description says `joined: true`, but the reply is `opened: true`.** A model reading the
   description may report failure or retry. That matters doubly because the app refuses a second open within 3 s. The fix is one
   word in `Sources/DingMCP/Tools.swift`, plus a test in `Tests/DingMCPTests/MCPServerTests.swift` asserting the description names the
   real field.
2. **DING-TEST-001: a test builds `AppModel()`.** `DingTests/AssistantsTabTests.swift:47` installs a delegate and categories on the real
   notification center inside the user's running Ding bundle. That is the exact failure the SPEC's rule was written to prevent. Assert the
   default of `startsControlServer` without constructing the real scheduler, or inject fakes.
3. **DING-NOTIF-013: SPEC.md contradicts itself on the default reminder.** The owner decides whether the default is None (as the code
   and tests say) or full screen 1 minute before. Then fix `SPEC.md:99` or the default.
4. **DING-NOTIF-016: the linkless switch is in the wrong place.** It sits under Screen reminder but also changes notifications. Decide
   whether it is one setting or two, then label it to match.
5. **Strengthen the tests that cannot fail** (DRIFT_REPORT.md section 4), starting with
   "testTheSelectionTheUserMadeIsWhatAssistantsSee" (privacy: assistants must see only visible events, DING-CTRL-016) and
   "testHotkeysAndAlertsAreOffByDefault".
6. **DING-REL-002 and DING-REL-019: refresh DISTRIBUTION.md and the SPEC milestones** so the release docs match `make/store.mk`
   (deno in preflight; notarized zip, not DMG; submission tooling exists but has not run on the box).
7. **DING-REL-010:** either add the trademark check to `scripts/listing_metadata.ts validate` or drop the claim from `listing/README.md`.
8. **Add a Linux-runnable lane** for the pure logic (see TEST_LANES.md). Today every Swift test needs macOS, because `DingIPC` imports
   Darwin and Security in the same package as `DingCore`.
