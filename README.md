# DAD 310 ADR Cue

Version 0.4.1. Built for DAD 310: Sound Design for Film at Dakota State University.

A REAPER script for preparing a scene of dialogue cues and recording replacements to picture. It provides scrolling phrase cues, a separate amber three-second count-in strip, three audio beeps, and guide playback control. Everything runs locally.

## Install

[Download ADR Cue v0.4.1](https://github.com/tatecarson/reaper-adr-cue/releases/download/v0.4.1/dad310-adr-cue-v0.4.1.zip). Extract the complete ZIP so the script and its support files stay together.

1. Extract the entire ZIP into a permanent folder. Keep `DAD310_ADR_Cue.lua`, `adr_core.lua`, `adr_text.lua`, and `adr-beep.wav` together.
2. In REAPER 7, open **Actions > Show action list**.
3. Choose **New action > Load ReaScript**, then select `DAD310_ADR_Cue.lua`.
4. Select the new action and click **Run/close**. You can assign it a shortcut or toolbar button.

The script uses features included with REAPER. It does not require SWS, ReaPack, Python, a browser, an account, or an internet connection. It is intended for macOS and Windows; Windows and physical microphone recording still need a classroom-machine check.

## Help inside the tool

Controls are grouped into Setup, Edit timing, Rehearse, and Record. Rest the pointer on a button for 1.2 seconds to see a short hint. Moving or clicking resets the delay. Tooltips stay hidden during playback and recording. Click **Help ?** at the top right for Setup, Recording, and Troubleshooting pages. Click **Close help** or press Escape to return. The `?` key also toggles Help. Opening Help does not stop an active run; Space will stop it. Keep the window at its default size or larger to read all help text.

Neutral controls prepare the cue. Blue controls rehearse it. The red Record button captures audio; the square Stop button ends the run. Labels and icons reinforce color. The larger dialogue area uses a fixed green reading line; amber is reserved for the count-in strip.

## Spot a whole scene before recording

1. Save the project. Import the picture and guide audio, leaving at least four seconds before the first cue. Open the video window.
2. Select the whole scene's time range. Click **Paste scene**, then **Paste text**, or **Load .txt** for a UTF-8 script file.
3. Edit the script in the large, resizable text area. Click to position the cursor and type `|` breaks. Enter starts a new line. Use arrows, drag or Shift to select, Ctrl/Cmd+A to select all, Ctrl/Cmd+V to paste, and Ctrl/Cmd+Z to undo. Long lines wrap without changing the script.

   Use one speaker turn per line, such as:

   ```text
   **Johnny:** They're coming to get you, Barbra.
   **Barbra:** Stop it. You're ignorant.
   Johnny: They're coming for you, Barbra.
   ```

4. Check the preview, then **Add cues**. Each turn becomes a separate recording cue. Speaker names remain in the cue list but are removed from the scrolling dialogue. Names spoken within dialogue, such as Barbra or Johnny, are kept.
5. Initial cue durations are distributed by word count across the selected scene. This is a rough layout, not speech detection. Before the talent arrives, choose each cue, move/trim its phrase items to the actual speech, select that line's exact time range, then click **Use range**.
6. Select the original dialogue track and click **Set guide**. Use a plain track without sends, hardware outputs, or volume automation. Clear track solos.
7. Save the project. During the session, use **Previous**, **Next**, or the cue list to select a prepared line. The three beeps move to that cue automatically. Other cues, phrase edits, and recordings stay in place.

Clipboard access uses SWS if present, otherwise the system clipboard on macOS or Windows. No extension is required. **Load .txt** works if clipboard access is unavailable.

## Add one cue or adjust phrases

Select a line's time range and click **Add cue**. Enter dialogue with an optional `Speaker:` label. New cues append to the session; existing cues are preserved. Older single-cue projects are upgraded in place without moving their phrase items.

Use `|` inside a turn for independently timed scrolling phrases:

```text
Johnny: Do you remember one time when we were small, | we were out here? | It was from right over there.
```

The tool creates `ADR PHRASES`, `ADR COUNT-IN`, and `ADR RECORD` tracks. All prepared phrase items stay on `ADR PHRASES`; only the active cue scrolls in the window. Select an item belonging to that cue and use **Edit phrase** to change its words.

Move each phrase item to its entrance and trim its end to match the guide, leaving natural pauses. The first word crosses the fixed green line at that phrase's start. Words within a phrase are not individually aligned. Shorter phrases provide more timing landmarks. `|` does not create separate recording passes.

**Use range** updates only the active cue's entrance and end from the current time selection and rebuilds its beeps. It does not move phrase items. Switching cues is blocked during playback or recording; stop first.

## Rehearse and record

- **Rehearse** plays the original dialogue. Playback starts four seconds before the entrance. Beeps sound at minus three, minus two, and minus one second. Speak on the silent fourth beat.
- **Perform** uses the same count-in, then turns down the guide audio at the entrance. It does not record. The video stays visible.
- **Record** starts a normal REAPER recording with the count-in and guide silencing. First select a microphone input on `ADR RECORD`, arm that track, and disarm all other tracks. Choose **Options > Record mode: normal**. Use headphones and set a sensible input level. Input monitoring starts disabled; enable it only if you need REAPER monitoring rather than your interface's direct monitoring.
- Playback stops one second after the cue ends. **Stop** finishes early. Pressing Space in the cue window toggles rehearsal and Stop. Escape closes the cue window.
- Existing items on `ADR RECORD` are temporarily muted during a run so old performances do not play over the actor. Their previous mute settings return afterward. New recordings remain available for review.
- Click Record again for another performance. REAPER's existing recording-overlap preference determines whether recordings become takes or separate items. Keep the recordings when REAPER prompts you.

For review, use REAPER's normal transport, mute the original guide, and audition and comp performances with fixed item lanes. Review controls are intentionally kept in REAPER; this tool does not rename takes or alter comp selections.

The tool restores the guide level and repeat setting when you stop, close its window, or switch project tabs. Open the action again to work in a different project. Save the project after editing cues. Close the cue tool before mixing or rendering, and verify that `ADR COUNT-IN` is muted.

## Switch to editing

Stop playback and click **Edit in REAPER** at the top of the window.

- Hides only `ADR PHRASES` and `ADR COUNT-IN` from the track panel and mixer.
- Keeps your video/location track visible and leaves its audio unchanged.
- Leaves `ADR RECORD`, your takes, and other tracks unchanged. Count-in beeps remain muted.

For a scene with one replacement line, retain the location sound before and after that line. On a working copy of the location audio, split around the original line and remove or mute only that section. Fit the ADR there, add matching room tone where needed, and use short fades. Keep the untouched original synchronized on a separate safety track. The button does not cut, mute, or otherwise edit the scene for you.

Click **Return to ADR** to restore the cue tracks' previous visibility when you need another take. Mode changes require stopped playback; rehearsal and recording are blocked in Edit mode.

Edit mode persists after closing the tool and saves with your project. Version 0.3.1 also restores guide visibility and volume saved by 0.3.0 if you reopen the tool while its older Edit mode is active.

## Current limits

- One cue runs at a time. You choose the next cue after stopping; there is no automatic advance or speech alignment.
- The count-in strip and dialogue appear in a companion window, not over the video or in an exported movie.
- Drawing and guide silencing follow REAPER's script refresh cycle. They are not sample-accurate, and smoothness depends on system load. Beeps are audio items on the timeline. Project playback rate must be 1.0.
- Use the tool's Record button for automatic guide control. Starting recording from REAPER's own transport does not start an ADR run.
- Keep metronome/count-in options off for this exercise to avoid adding another count-in. Keep phrase and beep tracks in the time timebase when changing tempo.
- Do not change guide routing or edit cue tracks during a run. After an unexpected interruption, reopen the tool to recover temporary guide and take-mute settings before saving or rendering.
- The automated timing and restoration tests use a simulated REAPER environment. Live scrolling, video playback, microphone recording, and hardware latency need an instructor smoke test before student rollout.

## Development

The script and `adr_core.lua` use REAPER's built-in Lua environment. `adr-beep.wav` is a generated 80 ms, 1 kHz tone at approximately -18 dBFS.

Run `tests/Run_ADR_tests.lua` from REAPER's action list, or run it with Lua 5.4 using:

```sh
lua -e 'reaper={MB=function(text) print(text) end}' tests/Run_ADR_tests.lua
```

The tests simulate REAPER transport and track state; they do not replace audio-interface and video-sync testing.

## Interface

The top row contains **Paste scene**, **Previous**, the saved cue list, and **Next**. The setup, timing, rehearsal, and recording controls remain below it. Speaker names appear in the list, while the scrolling area contains only dialogue.
