# Vibe Clauding

A macOS app that turns every running Claude Code agent into a pixel cutie dancing to whatever your Mac is playing.

- **One cutie per agent.** Working agents dance up front, agents waiting on you wave with a flashing `!`, and idle agents nap in the back lounge. When an agent's status changes, its cutie hops to its new spot.
- **Live activity.** A speech bubble shows what each agent is doing right now (`$ npm test`, `Editing App.swift`, `Needs you · $ rm -rf build`). The name tag shows the project and the session's task title. Subagents dance at their parent's feet as little helpers.
- **Synced to your music.** The app captures Mac audio (or the microphone) and runs an FFT, onset detection and a tempo tracker. Dance moves land on the beat and switch every two bars. Twisting neon wave ribbons on a black stage swell with the bass and pulse on every kick.
- **Click a cutie** to open its project in your editor (VS Code, Cursor or Windsurf, read from `~/.claude/ide`). Hover for details.
- **Menu bar extra** shows how many agents are working, or how many need you, with a quick list.

## Build and run

Requires macOS 15+ and Xcode 16+ (Swift 6 toolchain).

```sh
./scripts/build_app.sh          # builds and ad-hoc signs build/Vibe Clauding.app
open "build/Vibe Clauding.app"
```

Use the `.app` rather than `swift run`, because macOS only shows the audio permission prompt to a bundled app.

### Permissions

- **Mac audio** (default source) uses a Core Audio process tap (macOS 14.2+). On first launch macOS asks to allow *System Audio Recording*. If the HUD stays on `SILENT` while music plays, enable Vibe Clauding under **System Settings › Privacy & Security › Screen & System Audio Recording**. The app shows a shortcut button for this.
- **Mic** listens to the room instead.
- **Off** stops audio capture. The agents keep dancing to their own beat.

Audio is analyzed in memory and never recorded or sent anywhere.

Each rebuild is ad-hoc signed with a new signature, so macOS may ask for permission again after a rebuild.

## How agents are detected

Claude Code writes one file per running process to `~/.claude/sessions/<pid>.json` (fields used: `sessionId`, `cwd`, `status` = `busy` / `idle` / `waiting`). The app polls these every second, skips processes that have exited, and reads the tail of each session's transcript (`~/.claude/projects/<project>/<sessionId>.jsonl`) to find the current tool call, the last prompt and the AI title. Running subagents come from `<sessionId>/subagents/*.meta.json`. `CLAUDE_CONFIG_DIR` is respected.

These are internal Claude Code files rather than a public API, so a future Claude Code release could change them.

## Layout

```
Sources/VibeClauding/
  VibeClaudingApp.swift      app, window, menu bar extra, window visibility
  Agents/AgentStore.swift    session polling, liveness, subagents, open-in-editor
  Agents/TranscriptParser.swift  transcript tail → "what is it doing" text
  Audio/AudioEngine.swift    Core Audio system tap, mic capture, source switching
  Audio/BeatAnalyzer.swift   FFT bands, spectral-flux onsets, autocorrelation BPM, beat clock
  Visuals/WaveView.swift     Metal shader: neon ribbon, helix strands, beat rings, mirror floor
  Visuals/Choreography.swift dance moves (keyframes) + who dances what, when
  Visuals/CutieRenderer.swift draws the pixel mascot
  UI/StageView.swift         dance floor + lounge layout, bubbles, name tags
  UI/HUDView.swift           title, counts, BPM meter, source picker, pin-on-top
scripts/build_app.sh         build + bundle + sign
scripts/make_icon.swift      renders the app icon
```

The dance moves come from the "Logo bounce animation" design canvas (Bounce + clap, Shimmy, Disco point, Twirl hop, Hands-up wave), re-timed so the big hits land on beats.

## Performance

All animation stops while the window is minimized, covered or on another Space, and CPU drops to about 0.2%. While visible it renders at 60 fps.
