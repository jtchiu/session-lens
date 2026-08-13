import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct ProcessRunnerTests {
    @Test
    func locatorUsesOnlyExplicitCandidatesAndPathEntries() {
        let fileSystem = FakeExecutableFileSystem(
            executablePaths: ["/opt/homebrew/bin/opencode"]
        )
        let locator = ExecutableLocator(
            fileSystem: fileSystem,
            environmentPath: "/usr/bin:/opt/homebrew/bin"
        )

        #expect(
            locator.resolve(.opencode)
                == URL(fileURLWithPath: "/opt/homebrew/bin/opencode")
        )
        #expect(!fileSystem.probedPaths.contains("/tmp/opencode"))
    }

    @Test
    func runnerReturnsTimedOutWithoutUnboundedStderr() async {
        let runner = FoundationProcessRunner(stderrLimit: 1_024)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await runner.run(
            .init(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: .milliseconds(50)
            )
        )

        #expect(result.termination == .timedOut)
        #expect(result.stderr.count <= 1_024)
        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }

    @Test
    func runnerCapturesOutputAndMergesEnvironmentOverrides() async {
        let runner = FoundationProcessRunner(stderrLimit: 1_024)
        let result = await runner.run(
            .init(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf %s \"$SESSIONLENS_TEST_VALUE\""],
                timeout: .seconds(1),
                environment: ["SESSIONLENS_TEST_VALUE": "local-only"]
            )
        )

        #expect(result.termination == .exited(0))
        #expect(String(decoding: result.stdout, as: UTF8.self) == "local-only")
    }

    @Test
    func runnerDrainsButTruncatesLargeStderr() async {
        let runner = FoundationProcessRunner(stderrLimit: 64)
        let payload = String(repeating: "x", count: 4_096)
        let result = await runner.run(
            .init(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf %s \"$1\" >&2", "sessionlens", payload],
                timeout: .seconds(1)
            )
        )

        #expect(result.termination == .exited(0))
        #expect(result.stderr.count == 64)
    }

    @Test
    func runnerReturnsLaunchFailedInsteadOfThrowing() async {
        let runner = FoundationProcessRunner(stderrLimit: 1_024)
        let result = await runner.run(
            .init(
                executable: URL(
                    fileURLWithPath: "/definitely/not/a/sessionlens-executable"
                ),
                timeout: .seconds(1)
            )
        )

        #expect(result.termination == .launchFailed)
        #expect(result.stdout.isEmpty)
    }
}
