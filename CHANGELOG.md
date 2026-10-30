# Changelog

## 0.4.1

- Replace the read-only scene preview with a large multiline editor for adding phrase breaks before creating cues.
- Add cursor placement, selection, arrow navigation, paste, undo/redo, and scrolling.
- Enlarge the default window and widen single-cue and phrase text dialogs.

- Store multiple cues in each project. Add cue appends without replacing existing phrase items.
- Add whole-scene paste and UTF-8 text import, with one cue per speaker turn.
- Recognize plain and Markdown bold speaker labels; keep them out of scrolling dialogue.
- Add cue preview and rough initial timing weighted by dialogue word count.
- Add Previous/Next and a saved cue picker. Count-in beeps follow the selected cue.
- Preserve phrase timing, recorded takes, guide assignment, and recording setup across cue changes.
- Upgrade existing single-cue projects without moving their phrase items.
- Add session, scene parsing, migration, persistence, and transport guard regression tests.

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
