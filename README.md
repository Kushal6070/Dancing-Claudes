# Dancing Claudes

**The best way to vibe code with Claude.**

Put on some music and your Claude Code agents dance to it. Every agent you have running becomes a little pixel cutie, and every move lands on the beat. One look tells you what each agent is doing and which one needs you.

[![Watch the Dancing Claudes demo on YouTube](https://img.youtube.com/vi/jC9hAP6w2IE/maxresdefault.jpg)](https://www.youtube.com/watch?v=jC9hAP6w2IE)

*▶ Click to watch the demo on YouTube.*

## What you get

- **Claude, synced to your music.** The app listens to whatever your Mac is playing and finds the beat. The cuties switch moves every two bars: floss, dab, disco point, horse-ride trot, noodle flail and more. Behind them, neon waves pump with the bass and flash on every kick.
- **One cutie per agent.** Busy agents dance up front. Agents waiting on you wave a flashing `!` at you. Idle ones nap in the back lounge. When an agent changes state, its cutie hops over to its new spot.
- **Speech bubbles.** Each cutie shows what its agent is doing right now, like `$ npm test`, `Editing App.swift` or `Needs you · $ rm -rf build`. The name tag shows the project and the task. Subagents dance at their parent's feet like tiny helpers.
- **Choose your Cudie.** Go Regular, or go Mexican for sombreros, maracas and a zapateado stomp. The app remembers your pick.
- **Click a cutie** to open its project in VS Code, Cursor or Windsurf. Hover over it for more details.
- **Menu bar icon** shows how many agents are working, or how many need you, plus a quick list.
- **Pin it on top** so your cuties stay in view while you work.

## Get it running

You need macOS 15+ and Xcode 16+ (Swift 6).

```sh
./scripts/build_app.sh          # builds and signs build/Dancing Claudes.app
open "build/Dancing Claudes.app"
```

Open the `.app`. Don't use `swift run`, because macOS only asks for audio permission when it's a real app.

### Let it hear your music

The first time you open it, macOS asks if Dancing Claudes can record system audio. Say yes.

Music is playing but the app says `SILENT`? Turn on Dancing Claudes in **System Settings › Privacy & Security › Screen & System Audio Recording**. The app has a button that takes you right there.

Pick where the sound comes from:

- **Mac audio** (default) hears whatever your Mac is playing.
- **Mic** hears the room around you.
- **Off** stops listening. The cuties keep dancing to their own beat.

The app only listens in memory. Nothing is recorded or sent anywhere.

Heads up: every rebuild gets a new signature, so macOS may ask for permission again.

## How it finds your agents

Claude Code keeps a small file for each running session at `~/.claude/sessions/<pid>.json`. It has the session ID, the folder and the status (`busy`, `idle` or `waiting`). The app checks these every second and skips sessions that have quit.

For the speech bubbles, it reads the end of each session's transcript at `~/.claude/projects/<project>/<sessionId>.jsonl`. That gives it the current tool call, your last prompt and the session title. Running subagents come from `<sessionId>/subagents/*.meta.json`. To open the right editor, it checks `~/.claude/ide`. If you set `CLAUDE_CONFIG_DIR`, it looks there instead of `~/.claude`.

One catch: these are Claude Code's internal files, not a public API. A future Claude Code update could change them and break things here.

## What's inside

```
Sources/VibeClauding/
  VibeClaudingApp.swift          app, window, menu bar icon
  Agents/AgentStore.swift        finds sessions and subagents, opens your editor
  Agents/TranscriptParser.swift  turns the transcript into "what it's doing" text
  Audio/AudioEngine.swift        Mac audio tap, mic, switching between them
  Audio/BeatAnalyzer.swift       FFT, onset detection, BPM, beat clock
  Visuals/WaveView.swift         Metal shader: neon waves, beat rings, mirror floor
  Visuals/Choreography.swift     the dance moves, and who dances what, when
  Visuals/CutieRenderer.swift    draws the pixel cutie and its props
  UI/StageView.swift             dance floor, lounge, bubbles, name tags
  UI/HUDView.swift               top bar: counts, BPM, sound source, Cudie picker, pin
scripts/build_app.sh             build, bundle, sign
scripts/make_icon.swift          draws the app icon
```

The cuties and all their moves come from the "Logo bounce animation" design canvas. Each move is re-timed so the big hits land on the beat.

## Easy on your Mac

Minimize the window, cover it or switch to another Space, and all animation stops. CPU drops to about 0.2%. When you can see it, it runs at 60 fps.
