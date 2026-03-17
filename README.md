# hlmidisf2

MIDI + SF2 support for HashLink, with Heaps integration.

This library is built around:

- `midifile` for MIDI parsing
- `TinySoundFont` for SF2 synthesis

It gives you two main playback paths:

- accurate rendered playback: MIDI -> PCM via SF2
- Windows system MIDI playback: MIDI -> OS synth

The accurate path is the recommended one.

## Features

- decode `.mid` / `.midi` with `.sf2` into PCM16 or float PCM
- set one default SoundFont and reuse it everywhere
- use MIDI files as `hxd.res.Sound` in Heaps
- probe MIDI and SoundFont files before decoding
- optional Windows system MIDI playback helpers

## Formats

- MIDI: `mid`, `midi`
- SoundFont: `sf2`

Helpers:

- `midisf2.format.MidiFormat`
- `midisf2.format.SoundFontFormat`

## Main API

The main entry point is `midisf2.Midi`.

Useful methods:

- `setDefaultSoundFont(bytes)`
- `setDefaultSoundFontFromFile(path)`
- `trySetDefaultSoundFontFromFile(path)`
- `clearDefaultSoundFont()`
- `hasDefaultSoundFont()`
- `getDefaultSoundFontPath()`
- `probeMidi(bytes)`
- `probeSoundFont(bytes)`
- `preparePlayback(midiBytes, ?soundFontBytes, ?format, ?loop, ?fileNameHint)`
- `preparePlaybackFromFile(path, ?soundFontBytes, ?format, ?loop)`
- `preparePlaybackPCM16(midiBytes, ?soundFontBytes, ?loop, ?fileNameHint)`
- `preparePlaybackPCMFloat(midiBytes, ?soundFontBytes, ?loop, ?fileNameHint)`
- `preparePlaybackPCM16FromFile(path, ?soundFontBytes, ?loop)`
- `preparePlaybackPCMFloatFromFile(path, ?soundFontBytes, ?loop)`
- `decodeToPCM16(midiBytes, ?soundFontBytes)`
- `decodeToPCMFloat(midiBytes, ?soundFontBytes)`
- `describeLastError()`

Windows-only system playback helpers:

- `isSystemPlaybackSupported()`
- `playWithSystemSynth(path, ?loop)`
- `playBytesWithSystemSynth(bytes, ?loop, ?fileNameHint)`
- `stopSystemSynth()`
- `isSystemSynthPlaying()`

## Accurate MIDI + SF2 usage

Decode with an explicit SoundFont:

```haxe
final midiBytes = sys.io.File.getBytes("music.mid");
final sf2Bytes = sys.io.File.getBytes("soundfont.sf2");
final decoded = midisf2.Midi.decodeToPCMFloat(midiBytes, sf2Bytes);

if (decoded == null)
	throw midisf2.Midi.describeLastError();
```

Set a default SoundFont once:

```haxe
midisf2.Midi.setDefaultSoundFontFromFile("soundfont.sf2");

final decoded = midisf2.Midi.decodeToPCM16(sys.io.File.getBytes("music.mid"));

if (decoded == null)
	throw midisf2.Midi.describeLastError();
```

`decodeToPCM16()` and `decodeToPCMFloat()` return:

```haxe
{
	bytes:haxe.io.Bytes,
	channels:Int,
	sampleRate:Int,
	samples:Int,
	floatFormat:Bool,
}
```

## Heaps usage

If Heaps is present and `midisf2.Boot.setup()` is enabled, `.mid` and `.midi` resources are registered as `hxd.res.Sound`.

Minimal setup:

```haxe
// optional: with SoundFont set, MIDI is rendered through SF2
midisf2.Midi.setDefaultSoundFontFromFile("soundfont.sf2");

final sound = hxd.Res.music; // midi
final channel = sound.play();
```

What happens internally:

- `midisf2.Macro` hooks `hxd.res.Sound`
- MIDI files are detected through `midisf2.format.MidiFormat`
- Heaps sound data is provided by `hxd.snd.MidiData`

Important:

- if a default SoundFont is set, Heaps playback uses rendered MIDI + SF2
- if no default SoundFont is set and system MIDI playback is available, `sound.play()` falls back to the OS synth
- direct `hxd.snd.MidiData` usage still requires a SoundFont because it produces PCM data

## Plain HashLink usage

For non-Heaps HashLink code, use the unified prepare helpers:

```haxe
final prepared = midisf2.Midi.preparePlaybackFromFile("music.mid");
if (prepared == null)
	throw midisf2.Midi.describeLastError();

switch (prepared) {
	case System:
		// playing through the OS synth already started
	case Rendered(decoded):
		// feed decoded.bytes / decoded.channels / decoded.sampleRate into your audio backend
}
```

Use `midisf2.PlaybackFormat.PCMFloat` when your backend prefers float PCM.

Behavior:

- if a SoundFont is passed or configured by default, you get decoded PCM data
- if no SoundFont is available and system MIDI playback is supported, the OS synth starts automatically
- if neither path is available, the call returns `null` and `describeLastError()` explains why

## Windows system MIDI playback

There is also a Windows system MIDI path:

```haxe
if (midisf2.Midi.isSystemPlaybackSupported())
	midisf2.Midi.playWithSystemSynth("music.mid");
```

This path uses the OS synthesizer and is not the reference playback path.

Use it when you specifically want system MIDI behavior.
Use the SF2-rendered path when you want consistent output.

## Build

Dependencies are fetched automatically by CMake:

- `midifile`
- `TinySoundFont`

Requirements:

- CMake 3.10+
- Ninja
- MSVC build tools
- `HASHLINK` environment variable pointing to your HashLink installation

Build:

```sh
cmake --preset release
cmake --build --preset release
```

Outputs:

- `midisf2.hdll`
- `midisf2.lib` on Windows

Place `midisf2.hdll` next to your `.hl` output, or otherwise make sure HashLink can load it.

## Tests

Test launchers:

- `tests\test-miniaudio.bat`
- `tests\test-openal.bat`
- `tests\test-heaps.bat`
- `tests\run-tests.bat`

Test assets:

- MIDI fixture: `tests\testMain\midi\test.mid`
- SoundFont folder: `tests\testMain\sf2\`

By default the `sf2` folder is empty.
Put a `.sf2` file there before running SoundFont-based playback tests.

Current test coverage includes:

- MIDI probing
- invalid input handling
- missing SoundFont handling
- Windows system MIDI playback sequencing
- rendered MIDI + SF2 playback through Miniaudio
- rendered MIDI + SF2 playback through OpenAL
- rendered MIDI + SF2 playback through Heaps sound

## Notes

- rendered output is stereo, 48 kHz
- a tail is rendered after the last MIDI event to preserve note releases
- accurate playback is the MIDI + SF2 path
- system MIDI playback is a convenience path and may differ from SF2 rendering

## TODO

- Linux support
- macOS support
- Linux system MIDI playback support
- macOS system MIDI playback support
