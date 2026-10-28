# Changelog

## 0.3.1

- Edit mode hides only phrase and count-in tracks.
- Keep the video/location track visible and preserve its audio throughout the scene.
- Recover guide visibility and volume changed by 0.3.0 when reopening in Edit mode.

## 0.3.0

- Add Edit in REAPER / Return to ADR toggle.
- Hide support tracks and silence the guide while editing, without disabling video.
- Restore previous visibility and guide level when returning to ADR.
- Preserve Edit mode across script restarts and project saves.
- Add regression tests for restoration, deleted tracks, and playback guards.

## 0.2.0

First public release.

- One-line ADR cue creation with editable phrase items.
- Three audio beeps and a separate amber count-in strip.
- Rehearse, Perform, Record, and Stop controls.
- Guide and previous-take state restoration.
- Setup, timing, rehearsal, and recording sections.
- Delayed tooltips and built-in Help.
- Take review and comping remain in REAPER fixed item lanes.
