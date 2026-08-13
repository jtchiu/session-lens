import Darwin
import Foundation
import SessionLensCore

let input = FileHandle.standardInput.readDataToEndOfFile()

do {
    let payload = try JSONDecoder().decode(ClaudeStatusPayload.self, from: input)
    try ClaudeBridgeStore.live.write(payload.normalized(observedAt: Date()))
    let output = try await ExistingStatusLineForwarder.live.forward(
        originalInput: input
    )
    FileHandle.standardOutput.write(output)
} catch {
    exit(EXIT_FAILURE)
}
