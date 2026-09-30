# Voice chat

**Rule of the room: people inside a building can hear each other; passersby outside cannot.**
Proximity voice never crosses a wall.
The only exception is an open doorway, where someone standing right at the door hears a muffled voice (see "Walls and doors").
Crew radio ignores walls and distance, but only ever reaches your own crew.
Crew phones carry proximity voice between two phones, but only from right next to one phone ("Phone calls" below).

## What the player gets
- **Proximity chat is the default and the intended way to play: an open mic.**
  - Speak and people within 35 m of you hear you, with 3D falloff and direction.
  - A noise gate keeps silence off the wire, and the settings toggle says "Open mic (recommended)".
- **Optional push-to-talk for proximity:** turn open mic off in Settings and hold **N** to talk to people nearby.
- **Crew radio: hold Y.**
  - While Y is held, your voice goes to your crew mates only, at any distance, through a radio-filtered channel with a squelch click on key-down and key-up.
  - **You are muted in proximity while Y is held**, so a nearby enemy or bystander hears nothing.
  - The host enforces this too: a proximity frame from someone who sent a radio frame within the last 300 ms is dropped.
  - Someone with no crew has no radio and speaks in proximity as usual.
- **Phone calls: press P.** Hold a crew phone, press P (pad: D-pad left), pick a crew, and talk near the phone.
  See "Phone calls".
- **HUD (small text):** "MIC (nearby)", "RADIO (crew only)", or "push to talk: hold to speak" for you, plus a line "Name speaking" (prefixed "(radio)" for radio) for whoever you hear.
- **Settings menu:** voice on/off, open mic, voice volume, microphone level.
  - They are saved in `settings.cfg` under `[voice]`.
  - `FastVoice.set_peer_muted(id, bool)` mutes one player (no UI yet).
- **Keys.** The brief asked for V, but V is already the vehicle camera and B is buy, so:
  - radio = **Y**, proximity push-to-talk = **N** (`voice_radio` and `voice_ptt` in `main.gd` `_setup_input`);
  - rebind by changing the two entries in that `keys` dictionary.

## Design

```
mic -> AudioStreamMicrophone -> "VoiceCapture" bus (muted, AudioEffectCapture)
    -> mono, resample to 16 kHz -> 40 ms frames (640 samples)
    -> gain -> noise gate (RMS threshold + 8-frame hangover; the radio key bypasses the gate)
    -> IMA-ADPCM 4 bit -> FastNet.send_voice(mode, frame)
client -> host: unreliable_ordered RPC, transfer channel 2         (net.gd _host_voice)
host: gate (joined, budget, 40/s), validate, route                 (net.gd _h_voice + voice_relay.gd)
host -> listeners: unreliable_ordered RPC, channel 2, real sender id stamped in   (_relay_voice)
listener: decode -> AudioStreamGenerator -> AudioStreamPlayer3D (proximity) or "VoiceRadio" bus (crew)
```

Files:

| file | role |
|---|---|
| `scripts/voice_codec.gd` | ADPCM encode/decode, resampler, noise gate, SNR helper (pure) |
| `scripts/voice_relay.gd` | who hears whom (pure), including `phone_targets` for phone calls |
| `scripts/phone_calls.gd` | the call state machine between two phones (pure; the host owns it) |
| `scripts/voice.gd` | capture, mode choice, HUD, playback (`FastVoice`, created in `main.gd`) |
| `scripts/net.gd` | voice RPCs, host validation, `voice_frame` signal, `voice_space` / `voice_doors` hooks |
| `scripts/main.gd` | actions, settings UI and persistence, provides `voice_space` and `voice_doors` |
| `scripts/net_security.gd` | `PROTOCOL` bumped 3 -> 4 (the RPC list changed, so old builds are refused at the handshake) |
| `project.godot` | `audio/driver/enable_input=true` (see below) |
| `tests/voice.gd` | 119+ checks |
| `tests/voice_perf.gd` | grid vs plain scan, routing equivalence, 1,000-frame benchmark |

Codec:
- IMA-ADPCM, 16 kHz.
- Each frame is `[predictor s16][step index u8][nibbles]`.
- A frame is 323 bytes, and the header makes every frame decodable on its own, so packet loss never desyncs the decoder.
- `MAX_FRAME_BYTES` is 643, and the host and clients both reject anything outside 4..643 bytes.
- The round-trip SNR on a speech-like test signal is above 20 dB. Decoding gives one padding sample per even-length frame.

### Bandwidth
- **Payload:** 323 bytes x 25 frames/s = 8.1 kB/s = **64.6 kbit/s per active talker**, before ENet/UDP framing (about 70-75 kbit/s on the wire).
- **Silence sends nothing** in open-mic mode, apart from the gate's 8-frame hangover, so a normal conversation averages well under half of that.
- **Host upload** is the talker's rate times the number of listeners in range (or crew mates). With 8 players in a proximity crowd that is at most 7 x 65 = about 455 kbit/s per talker, and proximity keeps most rooms far below that.
- Frame rate can be halved later by dropping to 8 kHz (about 33 kbit/s) if needed.

### Routing (`voice_relay.gd`, decided by the host from its own view of positions)
- **Proximity:**
  - the listener is within 35 m by the host's positions;
  - listener and talker are both alive or both dead;
  - plus the wall rule below.
- **Crew:** same non-empty crew, any distance, dead or alive. **Never anyone outside the crew.** An empty crew has no radio.
- **Dead players:**
  - Proximity is dead-to-dead only. The living cannot hear the dead and the dead cannot hear the living, so the dead cannot leak information by listening.
  - The crew radio still works for the dead, so a downed player can call out to their crew.

### Walls and doors (proximity occlusion)
- `main.gd` gives the host two hooks:
  - `net.voice_space(pos) -> int` is `-1` outdoors, else the id of the walk-in building around that point. It uses the same `interior_half` footprints as `_building_around_player`, via the new `_building_at(pos)`.
  - `net.voice_doors() -> Array` lists the positions of currently open `world.interactable_doors`.
- Same space: normal distance falloff. Outdoor to outdoor: plain distance.
- Different spaces (inside vs outside, or two buildings): dropped, **unless both people are within 4 m of the same open doorway**. In that case the voice is delivered flagged `muffled`, and the listener plays it 8 dB down and low-passed at 900 Hz.
- Not done: raycast line-of-sight dampening for thin walls, or for windows and glass. It could be added in `voice_relay.gd` if the host is given a physics query.

### Security (same model as the rest of `net.gd`)
- Clients send to the host only. The RPC is `any_peer` on the host, and clients accept `_relay_voice` from the host (peer 1) only. Godot itself refuses a client-to-client `authority` RPC.
- The host checks, in order:
  - the sender has completed the handshake;
  - the message budget, and the voice rate limit of 40 frames/s (5x that for two windows is a kick);
  - that the mode is exactly 0 or 1. A "both modes" value is rejected, with a strike;
  - the frame size, with strikes on violations;
  - the sender is a known player.
- The sender id always comes from `get_remote_sender_id()`. It is never taken from the payload.
- The relay stamps the real sender and the distance. The client cannot choose who hears it.
- Voice needs no new trust in the client's position. It uses the host's `_latest` snapshots, the same ones that validate movement.

## Phone calls

**Design.** A call joins two crew PHONES (the physical items of docs/LEAD_DESIGN_DECISIONS.md section 2), not two people.
No chat tab and no key to hold: you hold a phone, dial, and talk.

| Step | What happens |
|---|---|
| Dial | Hold a phone and press **P** (pad: D-pad left). A strip on the HUD lists the other crews' phones ("1 MORRIS  2 SOL NEGRO  3 KINGSWAY"). **1-3** (pad: D-pad left/right) pick, **P** (pad: **A**) dials, **ESC** (pad: **B**) cancels. The strip closes by itself after 4 s. P with no phone shows "No phone in hand...". |
| Ring | The callee phone rings for **20 s**, in 3D at the phone's position (its holder, or wherever it lies), so everyone near it hears it (sound `ring`). The callee holder's HUD says "MORRIS PHONE CALLING - P to answer". The caller is told "No answer." after 20 s. |
| Answer | P while holding the ringing phone, **or picking the ringing phone up**. The call goes LIVE. |
| Live | HUD "ON CALL: MORRIS PHONE 0:42". **P hangs up.** |
| End | Either side hangs up, nobody answers, **3 minutes**, the Day ends or the phones reset (`_host_place_phones`), or a phone's holder disconnects. A dead holder drops the phone and the call goes on as a speakerphone. |

- **Host-authoritative.** `online.gd` owns a `phone_calls.gd` machine. Clients only ask (`net.send_phone_request`: `dial` a
  phone item, `answer`, `hangup`; validated by the host, rate-limited like item requests). The host replicates the calls
  (`net.broadcast_phone_calls`, reliable; a late joiner is caught up when it joins) and sends private lines ("Line busy.",
  "No answer.") with `net.send_phone_notice`.
- **Who may dial.** Only a phone holder (the existing call gate, `_host_may_call`). The phone in play is always the one the
  sender CARRIES, so a stolen phone dials and answers as its owners. One call per phone: a busy phone gives "Line busy.".
  The dead cannot use phones.
- **Live audio (`net.gd _h_voice`).** After the normal proximity relay, if the talker is alive and within
  `PHONE_PICKUP` = **1.2 m** of either phone in a live call, the host ALSO relays the frame as a new mode, `Mode.PHONE`, to every
  living listener within `PHONE_SPEAKER` = **3.5 m** of the OTHER phone (`VoiceRelay.phone_targets`).
  - A held phone is at its holder, so the holder is always picked up; someone standing right next to them can be too, but not
    the room.
  - A dropped phone in a live call still works: radii are measured from the phone (a speakerphone on the table).
  - The talker's normal proximity voice goes out as before. Anyone who already hears the talker directly is not sent a second,
    tinny copy. **Crew radio is never sent down a phone.**
  - Only the host makes PHONE frames: a client frame claiming mode 2 is rejected with a strike (`valid_send_mode`), while
    `valid_mode` (what a listener accepts) includes it.
- **Playback (`voice.gd`).** A PHONE frame plays from a third per-talker stream, an `AudioStreamPlayer3D` at the far phone
  (`phone_locator`, set by `main.gd` from `online.phone_voice_position`: the holder's remote player, or the dropped phone),
  on the new **`VoicePhone`** bus (high-pass 300 Hz, low-pass 3.4 kHz, a little overdrive). It is listed as "(phone) Name"
  and does not light the talker as speaking at your position.
- **Text still works** for players without a mic: ENTER, then TAB to "CALL <crew>" (same call gate).
- **Telemetry.** `voice_calls` (answered calls) and `voice_call_seconds` are tallied in the Day's JSON line.
- `PROTOCOL` is now **5** (new RPCs: `_host_phone_request`, `_phone_calls`, `_phone_notice`).

## Host routing cost

The host routes every voice frame (25-50 a second per talker with open mics). It used to run a full building scan per player
and rebuild a list of all ~1,270 doors per frame, which hitched the host. Now:
- `net.gd` remembers each player's voice space and refreshes it at most every 200 ms unless they moved more than 1 m (it is
  also skipped for anyone beyond earshot, and for crew radio, which ignores walls);
- `main.gd _building_at` looks the interior up in a 32 m grid built once (229 interiors in the real city), so it is O(few);
- doorways are only fetched when someone in earshot stands in a different space, through `net.voice_doors_near(pos, radius)`
  (a 16 m door grid; only the talker's `DOOR_RADIUS` matters; lift doors move so they are checked live). The old
  `voice_doors()` hook still works as the fallback.
- `tests/voice_perf.gd` builds the real city: 1,000 frames to 8 peers took about 60 ms (the old path: over 1 s), with
  identical targets to the plain scan in 240 scenarios.
- Also fixed: clients used to drop any voice from the host itself (peer id 1), so nobody heard a host on the mic.

## Steam (not implemented)
When `transport == "steam"`, GodotSteam's voice API (`startVoiceRecording`, `getVoice`, `decompressVoice`) could replace capture plus the ADPCM codec.
Steam compresses the audio itself and handles the mic, so `FastVoice` would only route and play it.
The host validation and routing in `net.gd` and `voice_relay.gd` stay the same.

## project.godot change
`[audio] driver/enable_input` is now `true`. Without it Godot never opens the microphone.
- On Windows this can trigger the OS "allow microphone access" prompt the first time.
- With no microphone or no permission, `FastVoice` simply never starts capture, and receiving voice still works.
- Headless and dummy-driver runs never touch the mic (`FastVoice` checks `DisplayServer.get_name() == "headless"`).

## Testing
- `tests/voice.gd`: **120 checks** (`VOICE RESULT`), including the phone relay (pickup and speaker radii, bystander, dead,
  dropped phone, radio never on a phone, mode validation) and a real-ENet phone frame and a host talking to a client.
  The call state machine and the host call flow are in `tests/week_flow.gd`. Run it with `godot --headless --path . --script res://tests/voice.gd`.
  - **Codec:**
    - ADPCM round trip, SNR over chained frames, and a frame decoding after its predecessor was lost;
    - frame size and caps;
    - malformed and random input;
    - the resampler, fed in chunks;
    - the noise gate and its hangover.
  - **Relay routing:**
    - proximity range;
    - crew-only, never an enemy;
    - squad key held: an enemy 3 m away hears nothing while a far crew mate does;
    - squad key released: proximity resumes;
    - the dead;
    - a "both modes" frame, and oversized, undersized and empty frames;
    - unknown senders;
    - a flood;
    - inside-hears-inside and passerby-outside-does-not (pure and on the host);
    - the open-doorway exception, flagged muffled.
  - **Voice node:** the open-mic and push-to-talk mode decisions, settings clamping, and headless with no mic (no errors, nothing sent).
  - **Real ENet on localhost, one process:** host plus three clients with real RPCs.
- Other suites kept green after these changes: integration, free_roam, social_features, net_security, remote_player, net_lobby_ui, chat_ui, sfx_audio, net_pair.
- `tests/run_all.sh` does not list `voice` yet. Add it to `ALL` there.

## Needs real-mic and 2-PC validation on Windows
Headless tests cannot cover these:
1. **Capture.**
   - `AudioStreamMicrophone` plus `AudioEffectCapture` actually deliver audio.
   - The mix rate is not assumed to be 48 kHz. The resampler takes it from `AudioServer.get_mix_rate()`.
   - Check for a first-run latency or crackle, and that the muted "VoiceCapture" bus still records.
2. **Level tuning.** Whether the default gate of -42 dB and the 8-frame hangover feel right, on a laptop mic and on a headset. There is a mic level slider but no live level meter.
3. **Playback jitter.** The generator has no jitter buffer beyond a 6400-sample cap. Real internet jitter can cause clicks or gaps. A small pre-buffer (2-3 frames) is the first fix to try.
4. **3D voice:** the range and volume at 35 m, and directional panning, with the attached 3D player.
5. **Radio filter:** whether the band-pass at 1500 Hz plus light overdrive on the "VoiceRadio" bus sounds like a radio, and is intelligible.
6. **Bandwidth:** about 65 kbit/s per talker. Test with several talkers on a real WAN/UPnP link.
7. **Echo.** There is no acoustic echo cancellation, so speakers plus an open mic will feed back. Headsets are recommended, and push-to-talk is the fallback.
8. **Windows mic permission prompt** on the first launch, and a machine with no microphone.
9. **Phones by ear.** Two players, a call, and real mics: the tinny handset sound (is 300-3400 Hz intelligible and not
   annoying?), the 1.2 m pickup and 3.5 m speaker distances (is a phone left on a table clearly heard at 3 m and not at 6?),
   the ring volume across a room, and P / D-pad left feel. Also check for feedback between a speakerphone and its own mic.
10. **Interiors.** Confirm `interior_half` covers each real building, and that doors report `open` as expected, so the inside/outside and doorway rules feel right in the real city.
