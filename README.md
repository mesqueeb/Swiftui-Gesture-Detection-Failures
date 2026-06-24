# swiftui-gesture-detection-failures

Minimal, single-file macOS SwiftUI app (no deps) showing two gesture-recognition failures,
with live on-screen evidence.

macOS 26.3.1 · Xcode 26.4.1 · Swift 6.3.1 · Apple Silicon, trackpad required.

## Findings

1. **A held `DragGesture` is permanently cancelled by a trackpad magnify.** Drag, then
   pinch without lifting: `onChanged` stops, `onEnded` never fires, and the still-pressed
   finger isn't re-detected — while AppKit's `NSEvent` stream keeps delivering
   `leftMouseDragged`. The OS still has the drag; SwiftUI dropped it.
2. **`MagnifyGesture` drops magnifies that `NSEvent` sees.** The "SwiftUI missed an NSEvent
   magnify" counter climbs whenever an `NSEvent` magnify begins/ends without
   `MagnifyGesture` ever recognizing it.

## Run

```sh
./build.sh run
```

Or paste `GestureReproApp.swift` into a fresh Xcode macOS → App project. Events also log to
the console under `[Repro]`.

## UI

- **Counters** (top): live SwiftUI vs AppKit event counts + the missed-magnify counter.
- **Ball**: drag / pinch it. **control ball with SwiftUI / AppKit** switches only what
  moves it; both sources are always logged and counted.
- **Flow charts** (`drag`, `magnify`, `drag and magnify`): each line goes ✅ when its event
  fires. In a pinch-mid-drag, `Drag onEnded` stays ⬜️ — the bug.
- **Start / Stop** arms/clears a chart. **Reset** clears counters/ball/log (not checkmarks).
  Switching control mode resets state and stops all charts.
