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
// you can set it for soundfont playback, or skip it for system playback
midisf2.Midi.setDefaultSoundFontFromFile("soundfont.sf2");

final sound = hxd.Res.music; // midi
final channel = sound.play();
```

What happens internally:

- `midisf2.Macro` hooks `hxd.res.Sound`
- MIDI files are detected through `midisf2.format.MidiFormat`
- Heaps sound data is provided by `hxd.snd.MidiData`

Important:

- Heaps playback uses rendered MIDI + SF2
- a default SoundFont must be set before loading/playing MIDI resources

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
