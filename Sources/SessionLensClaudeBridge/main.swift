import Foundation
import SessionLensCore

let input = FileHandle.standardInput.readDataToEndOfFile()

let output = await ClaudeBridgePipeline.captureAndForward(
    input: input,
    capture: { input in
        let payload = try JSONDecoder().decode(
            ClaudeStatusPayload.self,
            from: input
        )
        try ClaudeBridgeStore.live.write(payload.normalized(observedAt: Date()))
    },
    forward: {
        try await ExistingStatusLineForwarder.live.forward(originalInput: input)
    }
)
FileHandle.standardOutput.write(output)
