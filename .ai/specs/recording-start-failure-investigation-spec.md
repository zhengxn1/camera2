# Recording Start Failure Investigation Spec

> Status: Draft
> Created: 2026-05-07
> Scope: Native iOS DualCamera recording start failures that surface in JS as `Recording failed: The operation could not be completed`.

## 1. Symptom

When the user taps the video shutter, recording occasionally fails and JS shows:

```text
Recording failed
The operation could not be completed
```

The current JS alert comes from `onRecordingError`, which displays `event.error` directly. Native code often forwards only `NSError.localizedDescription`, so AVFoundation domain, code, and userInfo are lost.

## 2. Official AVFoundation Contracts

Apple's relevant contracts:

- `AVCaptureSession.startRunning` is synchronous and should run on a serial queue because it can block. The current code follows this pattern with `sessionQueue`.
- `AVCaptureMovieFileOutput.startRecordingToOutputFileURL:recordingDelegate:` writes asynchronously, and callers must wait for `captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:` before using the file.
- For `AVCaptureMovieFileOutput`, Apple says the finish delegate may receive an error even when the recording file was written; code must inspect `AVErrorRecordingSuccessfullyFinishedKey`.
- `AVAssetWriterInput.appendSampleBuffer:` requires appending samples in timestamp order. If append fails, the writer status/error must be inspected.
- `AVAssetWriterInputPixelBufferAdaptor.pixelBufferPool` is nil until `AVAssetWriter.startSessionAtSourceTime:` has been called.
- `AVCaptureDataOutputSynchronizer` is the official mechanism for receiving multiple capture outputs as synchronized timestamp-matched collections on a serial queue.
- `AVCaptureMultiCamSession.hardwareCost` over `1.0` prevents the session from running. `systemPressureCost` over `1.0` may run briefly and then stop under pressure.

## 3. Code Findings

### Finding A: Dual-stream AVAssetWriter timestamps can go backward

File: `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Current flow:

- Both front and back `AVCaptureVideoDataOutput` delegates use the same `videoDataOutputQueue`.
- `captureOutput:didOutputSampleBuffer:fromConnection:` stores the latest front/back frame.
- If recording is active, every front or back callback calls:

```objc
[self appendRealtimeVideoFrameAtTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
```

- `appendRealtimeVideoFrameAtTime:` writes a composited pixel buffer using that callback's timestamp.

This is fragile with two camera streams. A serial queue preserves callback execution order, but it does not guarantee that front/back sample presentation timestamps are globally monotonic. At recording start, a common interleaving can be:

```text
front PTS 10.033 -> append
back  PTS 10.000 -> append after newer frame
```

That violates Apple's `AVAssetWriterInput` timestamp-order contract and can make `appendPixelBuffer:withPresentationTime:` fail. Because the code then forwards `writer.error.localizedDescription`, the JS user sees the generic message.

This is the strongest match for an intermittent failure immediately after tapping start.

### Finding B: Dual recording reports "started" before the writer actually starts

`startRealtimeRecordingWithCanvasSize:` emits `onRecordingStarted` after preparing the writer, before:

- `startWriting`
- `startSessionAtSourceTime`
- first successful `appendPixelBuffer`

So JS can show a recording state while native has only prepared state. The first real writer failure then appears as a start-time failure to the user.

### Finding C: Single-camera finish handling treats every error as fatal

In `captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:`, native immediately emits an error for any non-nil `error`.

Apple's media-capture guide explicitly says to inspect `AVErrorRecordingSuccessfullyFinishedKey`; a non-nil error does not always mean the resulting file is unusable. This is not the main dual-cam start issue, but it is an official-contract mismatch.

### Finding D: Error payload is under-instrumented

Native emits only localized strings for writer/movie errors. That hides:

- `NSError.domain`
- `NSError.code`
- `NSError.userInfo`
- `AVAssetWriter.status`
- last appended video PTS
- incoming sample PTS
- source output that triggered the append

This makes intermittent AVFoundation failures appear identical in the UI.

### Finding E: MultiCam pressure is only partially checked

The code checks `hardwareCost > 1.0` after configuration. It does not log or react to `systemPressureCost`. Apple notes that pressure over budget may allow brief operation before interruption. This is a secondary risk, especially with two BGRA video outputs plus Core Image composition.

## 4. Proposed Design

### Phase 1: Add diagnostics before changing behavior

Emit structured native logs and JS event details for recording failures:

- `domain`
- `code`
- `localizedDescription`
- `localizedFailureReason`
- `userInfo`
- writer status
- current state enum
- last appended PTS
- rejected PTS
- triggering output: front/back/audio
- hardware/system pressure cost

Keep the UI message friendly, but preserve technical details in logs.

### Phase 2: Make dual recording timestamps monotonic

Minimum fix:

- Add `CMTime lastRealtimeVideoPTS`.
- Before append, compare incoming PTS with the last appended PTS.
- If incoming PTS is `<= lastRealtimeVideoPTS`, either drop it or synthesize the next frame time from a stable frame clock.
- Append only strictly increasing times.

Better fix:

- Use one camera stream as the recording clock, preferably back camera or whichever is primary.
- Store latest frames from both streams, but append a composited frame only when the clock stream produces a callback.

Best AVFoundation-aligned fix:

- Introduce `AVCaptureDataOutputSynchronizer` for front/back `AVCaptureVideoDataOutput`.
- Compose from synchronized front/back sample buffers in the synchronizer delegate.
- Append once per synchronized collection using that collection's video PTS.

### Phase 3: Move "recording started" to first successful frame

For dual recording, emit `onRecordingStarted` only after:

- `startWriting` succeeded,
- `startSessionAtSourceTime` was called,
- first `appendPixelBuffer` succeeded.

This makes JS state reflect actual native recording state.

### Phase 4: Fix single-camera delegate contract

In `didFinishRecording...error:`, inspect `AVErrorRecordingSuccessfullyFinishedKey`.

- If `recordedSuccessfully == YES`, emit `onRecordingFinished`.
- Otherwise emit a structured recording error.

### Phase 5: Pressure handling

Log `hardwareCost` and `systemPressureCost` when configuring and starting recording. If pressure is high, reduce cost before recording by lowering frame rate, dimensions, or composition frequency.

## 5. Acceptance Checks

- Rapidly tap video start in LR/SX/PiP dual modes 30 times; no generic "operation could not be completed" alert.
- If a writer append fails, the log includes domain/code/userInfo and PTS values.
- `onRecordingStarted` fires only after the first successful frame write.
- No appended pixel buffer has a presentation timestamp less than or equal to the previous appended video frame.
- Single-camera short recordings do not fail solely because `error` is non-nil when `AVErrorRecordingSuccessfullyFinishedKey` is true.

## 6. Target File List

| File | Action |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | Main fixes: monotonic/synchronized dual recording timestamps, move dual start event, structured error details, single-camera finish contract, pressure logs. |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h` | Optional: extend recording error payload API beyond a string. |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m` | Optional: emit structured recording error body while preserving `error` for UI compatibility. |
| `my-app/App.js` | Optional: display a friendly message and log structured native error details for debugging. |
| `.ai/project.md` | Record ADR/change note after implementation. |
