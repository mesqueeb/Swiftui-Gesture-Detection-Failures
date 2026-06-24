# swiftui-gesture-detection-failures

Minimal single-file macOS SwiftUI app (no deps) for the Feedback report below. Run `./build.sh run`,
or paste `GestureReproApp.swift` into a new Xcode macOS App. Events also log to the console with the `[Repro]` prefix.

## Feedback report

Title: SwiftUI DragGesture is permanently cancelled (no terminal onEnded) by a trackpad magnify on macOS

- Reproduction video: [./reproduction.mp4](./reproduction.mp4)
![](./reproduction.mp4)

While a SwiftUI DragGesture is held (trackpad click-drag), a two-finger magnify (trackpad pinch) permanently cancels it:

- onChanged stops firing the instant the magnify is recognized.
- onEnded is never delivered — the gesture is torn down with no terminal event.
- Continued motion of the same, still-pressed finger after the pinch is not re-detected.

The drag only recovers after a full release and re-press. Throughout, the AppKit NSEvent stream keeps delivering .leftMouseDragged (and a clean .leftMouseUp on release), so the OS is still tracking the drag — it is SwiftUI's gesture arbitration that discards it. No gesture composition avoids this: .simultaneousGesture, .highPriorityGesture, varying gesture order, and .exclusively(before:) in both directions were all tried; none delivers a terminal onEnded or resumes the drag after the pinch.

## Steps to reproduce

1. Run the attached sample on a Mac with a trackpad.
2. Press-hold and drag the circle (do not release).
3. Without lifting the drag finger, perform a two-finger pinch.
4. End the pinch and keep moving the same finger.

Expected: onChanged continues for the still-pressed finger; onEnded fires when it is lifted.

Actual: after the magnify, onEnded never fires — the "Drag onEnded" line in the on-screen "drag and magnify" checklist (lower part of the window) stays unchecked. SwiftUI's Drag onChanged also stops firing while NSEvent leftMouseDragged keeps firing (visible in the live counters at the top of the window).

Tested on: macOS 26.3.1 (25D771280a) and macOS 27.0 Beta (26A5353q). Apple Silicon, built-in trackpad.

## Workaround

Drive all gestures off AppKit `NSEvent` instead of SwiftUI — flip the app's input-source toggle from SwiftUI to AppKit and everything works correctly.

## Extra findings (not in the Feedback ticket)

- SwiftUI's `MagnifyGesture` occasionally fails to recognize a pinch that the AppKit `NSEvent` stream detects every time. The app's "SwiftUI missed an NSEvent magnify" counter climbs when this happens.
