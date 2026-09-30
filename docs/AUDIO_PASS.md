# Audio pass

Owner: audio (scripts/sfx.gd, tests/sfx_audio.gd). Everything is still synthesised in code at start-up.
The game ships no audio files, and no samples were downloaded or copied. All synthesis is seeded, so every peer builds a
byte-identical bank (`bank_checksum()`).

Feel target: gritty, boomy, punchy gunplay with grounded distance, in a late-90s city.

## What changed

### Gunshots (all 15 firearm sounds, rebuilt)
Each shot is layered, then saturated:

1. A 3-sample click, then a high-passed noise **crack**. Decay is per gun, from 280/s for a shotgun to 950/s for a MAC-10.
2. Quantised "grit" noise (a 3-level staircase), which gives the crunchy edge.
3. Low-passed noise **blast body**.
4. A **pitch-dropping thump** (about 62-220 Hz) with a long decay, plus a **sub layer** (44-72 Hz, 9/s decay) for low-end boom.
5. A noise-based **action tick** (slide/bolt clack). It has no pitched ping.
6. The dry shot goes through a tanh saturator (drive 2.4, or 1.6 for `suppressed`). This adds grit and fattens the low end.
7. Street **slap-back echoes** (2-3 low-passed taps, 50-380 ms) with a heavier tail than before, then a final soft clip. Peaks stay at or below 0.92 after normalisation.

Per-weapon character:
- Handguns (`pistol`, `m1911`, `revolver`): crisp.
- SMGs (`smg`, `mac`, `tommy`): short and rattly.
- Rifles (`rifle`, `ak`, `marksman`, `dmr`): a longer crack with a sizzle, and a long street slap.
- Shotguns (`shotgun`, `double`, `auto12`): huge and low, with a wide echo.
- `suppressed`: a dull "thup" with the action louder than the shot.

The saturated shots are about 8 dB hotter (RMS) than before, so `GUN_TRIM_DB = -6` is applied to their gain hints to keep the mix level.

### Distant variants
Every gun has a `<name>_far` sample: no crack, low-passed twice, 4 ms onset, 4 rolling echoes at 130-680 ms, and about 1.5x the length.
`shot_sound()` and `play_shot_at()` choose between near and far. The distance threshold is `FAR_SHOT_DISTANCE` (55 m).
The `_far` samples are built lazily (see "Build cost").

### Weapon handling (no more beeps)
The old versions used sine "pings", which read as childish beeps. All handling sounds are now noise-led.
Sound types: filtered-noise bursts, stick-slip steel scrapes, low thuds, and inharmonic metal partials.
The partials sit far under the noise and die in a few ms, so nothing reads as a clean pitched tone.

Rebuilt (same names, so no call-site changes):
- `bolt`
- `pump`
- `mag_in`
- `mag_out`
- `dry`
- `shell`
- `draw`
- `break_open`
- `cylinder`

Also changed:
- Hit feedback (`hit`, `headshot`, `kill`) is now noise impacts instead of a sine click, a bell and a sweep.
- `steel` (a bullet on steel) is now a noise clang with an inharmonic ring instead of a clean bell.

New names, not yet called by the game:
- `slide` (pistol slide rack)
- `safety` (selector click)
- `holster`

### Ambient
- `ambience` (10 s loop, was 3.5 s) now has:
  - distant traffic rumble and hiss;
  - one car pass-by;
  - gusting wind;
  - harbor water lap (about every 2.5 s);
  - one very faint far siren wail.
  Slow modulators use whole cycles per loop and are crossfaded, so the loop point is seamless. Its level is close to the old bed (RMS 0.22 vs 0.29).
- `club_bass`: 124 BPM four-on-the-floor thump heard through a wall, exactly 8 beats long and wrapped, so it loops on the beat. A gain hint of -14 dB.
- `room_tone`: 60/120/180 Hz mains hum plus air noise (4 s loop). A gain hint of -22 dB.
- `dog_far`: three muffled barks, one-shot.
- `siren_far`: a distant emergency siren, one-shot, 4 s.

### Reverb "spaces"
`set_space("outdoor" | "alley" | "indoor" | "hall")` sets a reverb on the `SfxSpace` audio bus. Only gunfire, `crash`, `glass` and `door` voices are routed through that bus.
UI, footsteps and engines are not. Default is `outdoor`, a light send.

## New public API (sfx.gd)
`play`, `play_at`, `stream`, `has_sound`, `master_db` and `volume` are unchanged.

| function | purpose |
|---|---|
| `play_shot_at(weapon, at, listener, pitch=1.0, gain_db=0.0)` | positional shot; picks near or `_far` by distance |
| `shot_sound(weapon, distance) -> String` | the sample name that would play |
| `set_space(name)` / `current_space()` | reverb space for gunfire |
| `gain_hint(sound)` | the dB level `play` applies (use it when driving `stream()` yourself) |
| `duration(sound)`, `bank_seconds()`, `sound_names()` | introspection |
| `bank_checksum()`, `rebuild()` | determinism checks |
| `build_ms` | milliseconds the last bank build took |

## Build cost
- Before: about 0.40-0.44 s to build, 22.3 s of audio (47 sounds).
- After: about 0.97 s to build (measured on this 4-core box under load), 69 s of audio (69 sounds, 2.9 MB).
- Far shots, `dog_far` and `siren_far` (17 sounds, about 35 s of that audio) are built lazily, one per frame at idle after boot.
  `has_sound` is true for them immediately, and `stream`, `play` and `play_at` build a pending sound on demand.
  Building on demand gives identical bytes; this is asserted in the test.

## Lead hooks needed
None are required: everything works with the existing call sites. These are optional upgrades in files I do not own.

1. **Distance-aware gunshots.**
   - `scripts/online.gd` (net owner has been messaged), lines ~351/354. Replace
     `game.sfx.play_at(str(stats.get("sound", weapon)), origin, 1.0, 3.0)` with
     `game.sfx.play_shot_at(str(stats.get("sound", weapon)), origin, game.player.global_position, 1.0, 3.0)`.
     The `"suppressed"` call becomes `game.sfx.play_shot_at("suppressed", origin, game.player.global_position)`.
   - `scripts/main.gd` `_guard_shot` (~line 2215): replace
     `sfx.play_at("guard_shot", origin)` with `sfx.play_shot_at("guard_shot", origin, player.global_position)`.
2. **Interior and outdoor reverb.**
   - Call `sfx.set_space("indoor")` when the player enters a building interior and `sfx.set_space("outdoor")` when they leave.
     For example, in the `main.gd` door enter/exit code near `sfx.play("door")` (~lines 768 and 839).
   - Use `"alley"` in narrow streets, and `"hall"` for big rooms such as the nightclub floor.
3. **Ambient zones.** In `main.gd`, next to where `ambience_player.stream` is set (~line 2343: `stream_player.stream = sfx.call("stream", sound)`):
   - Inside a club, start a second looping `AudioStreamPlayer` with `sfx.stream("club_bass")` at `sfx.master_db(sfx.gain_hint("club_bass") + 3.0 * (1.0 - wall_distance / 30.0))`.
     The bass rises towards the door. Use `master_db(-14.0)` outdoors, and fade it out over about 0.5 s when you go inside.
   - In a generic interior, loop `room_tone` at `sfx.master_db(sfx.gain_hint("room_tone"))`, and lower the `ambience` volume by about 8 dB indoors.
4. **Occasional far-off events.** From `main.gd`'s `_process`, every 25-60 s of unhurried play:
   `sfx.play_at("dog_far" if randf() < 0.7 else "siren_far", player.global_position + random_dir * 90.0, 1.0, -3.0)`,
   where `random_dir` is a random horizontal unit vector.
5. **Handling names.** `slide` (pistol rack on reload), `safety` (weapon-mode toggle) and `holster` (weapon away) exist but nothing calls them yet.
   - Call `sfx.play("slide")` at the end of the pistol reload sequence, where `main.gd` plays `"mag_in"`.
   - Call `sfx.play("holster")` when a weapon is switched away.

## Testing
- `tests/sfx_audio.gd`: 219 checks, 0 failures. It covers:
  - every legacy and new name, plus `_far` twins;
  - the weapon `"sound"` names in `player.gd`;
  - non-empty streams, peaks at or below 1.0, and mono 16-bit 22.05 kHz;
  - loop flags and loop seams;
  - far shots duller and longer than near shots;
  - handling sounds broadband and short;
  - distance selection, reverb spaces, playback calls that do not crash;
  - determinism across rebuild and across a second instance.
- Run it with `godot --headless --path . --script res://tests/sfx_audio.gd`.
- Set `SFX_DUMP=1` to write every sound to `work/audio/<name>.wav`, which is git-ignored, for listening.
