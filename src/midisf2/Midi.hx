package midisf2;

import haxe.io.Bytes;

/**
	Decoded audio returned by SoundFont rendering.

	The `bytes` field contains interleaved PCM samples.
	Use `channels`, `sampleRate`, `samples`, and `floatFormat`
	to pass the data into your audio backend.
**/
typedef DecodedAudio = {
	bytes:Bytes,
	channels:Int,
	sampleRate:Int,
	samples:Int,
	floatFormat:Bool,
}

/**
	Selects the PCM format used when MIDI is rendered through a SoundFont.

	- `PCM16` returns signed 16-bit interleaved PCM.
	- `PCMFloat` returns 32-bit float interleaved PCM.
**/
enum PlaybackFormat {
	PCM16;
	PCMFloat;
}

/**
	Represents the playback path selected for a MIDI file.

	- `Rendered(decoded)` means the MIDI was converted into PCM data.
	- `System` means playback already started through the OS MIDI synth.
**/
enum PlaybackResult {
	Rendered(decoded:DecodedAudio);
	System;
}

/**
	Contains helpers for working with MIDI files.

	These helpers are used to either decode MIDI files directly into PCM
	data or to prepare them for playback through the system MIDI synth.

	@see https://github.com/craigsapp/midifile
	@see https://github.com/schellingb/TinySoundFont
**/
final class Midi {
	static var defaultSoundFont:Null<Bytes>;
	static var defaultSoundFontPath:Null<String>;
	static var lastHaxeError = "";
	static var systemTempMidiPath:Null<String>;

	static inline function applyDefaultSoundFont(bytes:Bytes, path:Null<String>):Void {
		defaultSoundFont = bytes;
		defaultSoundFontPath = path;
		clearHaxeError();
	}

	static inline function buildDecodedAudio(decoded:hl.Bytes, channels:Int, sampleRate:Int, samples:Int, floatFormat:Bool):DecodedAudio {
		return {
			bytes: @:privateAccess new Bytes(decoded, samples * channels * (floatFormat ? 4 : 2)),
			channels: channels,
			sampleRate: sampleRate,
			samples: samples,
			floatFormat: floatFormat,
		};
	}

	static inline function setHaxeError(message:String):Void {
		lastHaxeError = message;
	}

	static inline function clearHaxeError():Void {
		lastHaxeError = "";
	}

	static inline function isValidBytes(bytes:Null<Bytes>):Bool {
		return bytes != null && bytes.length > 0;
	}

	static inline function decodeToFormat(midiBytes:Bytes, soundFontBytes:Null<Bytes>, format:PlaybackFormat):Null<DecodedAudio> {
		return switch (format) {
			case PCM16: decodeToPCM16(midiBytes, soundFontBytes);
			case PCMFloat: decodeToPCMFloat(midiBytes, soundFontBytes);
		};
	}

	static function resolveSoundFont(soundFontBytes:Null<Bytes>):Null<Bytes> {
		if (soundFontBytes != null && soundFontBytes.length > 0)
			return soundFontBytes;
		if (defaultSoundFont != null && defaultSoundFont.length > 0)
			return defaultSoundFont;
		setHaxeError("No SoundFont provided. Pass .sf2 bytes to decode or call midisf2.Midi.setDefaultSoundFont() / setDefaultSoundFontFromFile() first.");
		return null;
	}

	static function deleteSystemTempMidi():Void {
		if (systemTempMidiPath == null)
			return;

		try {
			if (sys.FileSystem.exists(systemTempMidiPath))
				sys.FileSystem.deleteFile(systemTempMidiPath);
		} catch (_:Dynamic) {}

		systemTempMidiPath = null;
	}

	static function createSystemTempMidiPath(fileNameHint:String):String {
		var baseName = fileNameHint;
		if (baseName == null || baseName.length == 0)
			baseName = "midisf2-system.mid";

		baseName = haxe.io.Path.withoutDirectory(baseName);
		final lowerBaseName = baseName.toLowerCase();
		if (!StringTools.endsWith(lowerBaseName, ".mid") && !StringTools.endsWith(lowerBaseName, ".midi"))
			baseName += ".mid";

		final tempDir = Sys.getEnv("TEMP");
		final directory = tempDir != null && tempDir.length > 0 ? tempDir : Sys.getCwd();
		return haxe.io.Path.join([directory, Std.string(Date.now().getTime()) + "-" + baseName]);
	}

	/**
		Sets the SoundFont used by decode helpers and rendered playback.
	**/
	public static function setDefaultSoundFont(bytes:Bytes):Void {
		if (bytes == null || bytes.length <= 0)
			throw "Invalid SoundFont data";
		if (!probeSoundFont(bytes))
			throw "Invalid SoundFont data";

		applyDefaultSoundFont(bytes, null);
	}

	/**
		Loads and stores a default SoundFont from disk.
	**/
	public static function setDefaultSoundFontFromFile(path:String):Void {
		if (path == null || path.length == 0)
			throw "Invalid SoundFont path";
		if (!sys.FileSystem.exists(path))
			throw "SoundFont file not found: " + path;

		setDefaultSoundFont(sys.io.File.getBytes(path));
		defaultSoundFontPath = path;
	}

	/**
		Tries to load a default SoundFont from disk without throwing.
	**/
	public static function trySetDefaultSoundFontFromFile(path:String):Bool {
		if (path == null || path.length == 0) {
			setHaxeError("Invalid SoundFont path");
			return false;
		}

		if (!sys.FileSystem.exists(path)) {
			setHaxeError("SoundFont file not found: " + path);
			return false;
		}

		final bytes = sys.io.File.getBytes(path);
		if (!probeSoundFont(bytes)) {
			setHaxeError("Invalid SoundFont data");
			return false;
		}

		applyDefaultSoundFont(bytes, path);
		return true;
	}

	/**
		Clears the default SoundFont.

		After this, auto-playback falls back to the system synth when available.
	**/
	public static function clearDefaultSoundFont():Void {
		defaultSoundFont = null;
		defaultSoundFontPath = null;
	}

	/**
		Returns `true` when a default SoundFont is configured.
	**/
	public static inline function hasDefaultSoundFont():Bool {
		return defaultSoundFont != null && defaultSoundFont.length > 0;
	}

	/**
		Returns the source path of the default SoundFont when it was loaded from file.
	**/
	public static inline function getDefaultSoundFontPath():Null<String> {
		return defaultSoundFontPath;
	}

	/**
		Checks whether the provided bytes look like valid MIDI data.
	**/
	public static inline function probeMidi(bytes:Bytes):Bool {
		if (bytes == null || bytes.length <= 0)
			return false;
		return _probeMidi(bytes, bytes.length);
	}

	/**
		Checks whether the provided bytes look like valid SoundFont data.
	**/
	public static inline function probeSoundFont(bytes:Bytes):Bool {
		if (bytes == null || bytes.length <= 0)
			return false;
		return _probeSoundFont(bytes, bytes.length);
	}

	/**
		Returns `true` when OS-level MIDI playback is available on the current platform.
	**/
	public static inline function isSystemPlaybackSupported():Bool {
		return _systemMidiAvailable();
	}

	/**
		Starts MIDI playback through the system synth using a file path.
	**/
	public static function playWithSystemSynth(path:String, ?loop = false):Bool {
		if (path == null || path.length == 0) {
			setHaxeError("Invalid MIDI path");
			return false;
		}

		if (!sys.FileSystem.exists(path)) {
			setHaxeError("MIDI file not found: " + path);
			return false;
		}

		stopSystemSynth();
		final pathBytes = Bytes.ofString(path);
		final ok = _playSystemMidi(pathBytes, pathBytes.length, loop);
		if (ok)
			clearHaxeError();

		return ok;
	}

	/**
		Starts MIDI playback through the system synth using MIDI bytes.
	**/
	public static function playBytesWithSystemSynth(midiBytes:Bytes, ?loop = false, ?fileNameHint = "midisf2-system.mid"):Bool {
		if (midiBytes == null || midiBytes.length <= 0) {
			setHaxeError("Invalid MIDI data");
			return false;
		}

		if (!probeMidi(midiBytes)) {
			setHaxeError("Invalid MIDI data");
			return false;
		}

		final tempPath = createSystemTempMidiPath(fileNameHint);
		sys.io.File.saveBytes(tempPath, midiBytes);
		if (!playWithSystemSynth(tempPath, loop)) {
			try {
				sys.FileSystem.deleteFile(tempPath);
			} catch (_:Dynamic) {}
			return false;
		}

		systemTempMidiPath = tempPath;
		return true;
	}

	/**
		Stops system MIDI playback if it is currently active.
	**/
	public static function stopSystemSynth():Void {
		_stopSystemMidi();
		deleteSystemTempMidi();
	}

	/**
		Returns `true` while the system synth is still playing.
	**/
	public static inline function isSystemSynthPlaying():Bool {
		return _isSystemMidiPlaying();
	}

	/**
		Prepares MIDI playback with the most convenient available path.

		If a SoundFont is available, returns `Rendered(decoded)`.
		If no SoundFont is available but system MIDI playback exists, starts the OS synth and returns `System`.
		On failure, returns `null` and the reason can be read with `describeLastError()`.

		Example:
		```haxe
		final result = midisf2.Midi.preparePlayback(midiBytes);
		if (result == null)
			throw midisf2.Midi.describeLastError();

		switch (result) {
			case System:
			case Rendered(decoded):
		}
		```
	**/
	public static function preparePlayback(midiBytes:Bytes, ?soundFontBytes:Bytes, ?format = PlaybackFormat.PCM16, ?loop = false, ?fileNameHint = "midisf2-system.mid"):Null<PlaybackResult> {
		final preferRendered = isValidBytes(soundFontBytes) || hasDefaultSoundFont();
		if (preferRendered) {
			final decoded = decodeToFormat(midiBytes, soundFontBytes, format);
			if (decoded == null)
				return null;
			return Rendered(decoded);
		}

		if (!isSystemPlaybackSupported()) {
			decodeToFormat(midiBytes, soundFontBytes, format);
			return null;
		}

		if (!playBytesWithSystemSynth(midiBytes, loop, fileNameHint))
			return null;

		clearHaxeError();
		return System;
	}

	/**
		Convenience wrapper for `preparePlayback()` with `PCM16` output.
	**/
	public static function preparePlaybackPCM16(midiBytes:Bytes, ?soundFontBytes:Bytes, ?loop = false, ?fileNameHint = "midisf2-system.mid"):Null<PlaybackResult> {
		return preparePlayback(midiBytes, soundFontBytes, PCM16, loop, fileNameHint);
	}

	/**
		Convenience wrapper for `preparePlayback()` with `PCMFloat` output.
	**/
	public static function preparePlaybackPCMFloat(midiBytes:Bytes, ?soundFontBytes:Bytes, ?loop = false, ?fileNameHint = "midisf2-system.mid"):Null<PlaybackResult> {
		return preparePlayback(midiBytes, soundFontBytes, PCMFloat, loop, fileNameHint);
	}

	/**
		Loads a MIDI file from disk and applies the same auto-selection as `preparePlayback()`.
	**/
	public static function preparePlaybackFromFile(path:String, ?soundFontBytes:Bytes, ?format = PlaybackFormat.PCM16, ?loop = false):Null<PlaybackResult> {
		if (path == null || path.length == 0) {
			setHaxeError("Invalid MIDI path");
			return null;
		}

		if (!sys.FileSystem.exists(path)) {
			setHaxeError("MIDI file not found: " + path);
			return null;
		}

		return preparePlayback(sys.io.File.getBytes(path), soundFontBytes, format, loop, path);
	}

	/**
		Convenience wrapper for `preparePlaybackFromFile()` with `PCM16` output.
	**/
	public static function preparePlaybackPCM16FromFile(path:String, ?soundFontBytes:Bytes, ?loop = false):Null<PlaybackResult> {
		return preparePlaybackFromFile(path, soundFontBytes, PCM16, loop);
	}

	/**
		Convenience wrapper for `preparePlaybackFromFile()` with `PCMFloat` output.
	**/
	public static function preparePlaybackPCMFloatFromFile(path:String, ?soundFontBytes:Bytes, ?loop = false):Null<PlaybackResult> {
		return preparePlaybackFromFile(path, soundFontBytes, PCMFloat, loop);
	}

	/**
		Renders MIDI into float PCM using the provided or default SoundFont.
	**/
	public static inline function decodeToPCMFloat(midiBytes:Bytes, ?soundFontBytes:Bytes):Null<DecodedAudio> {
		if (midiBytes == null || midiBytes.length <= 0) {
			setHaxeError("Invalid MIDI data");
			return null;
		}

		final sf2 = resolveSoundFont(soundFontBytes);
		if (sf2 == null)
			return null;

		final decoded = _decodeToPCMFloat(midiBytes, midiBytes.length, sf2, sf2.length);
		if (decoded == null)
			return null;

		clearHaxeError();
		return buildDecodedAudio(decoded, _decodedChannels(), _decodedSampleRate(), _decodedSamples(), true);
	}

	/**
		Renders MIDI into 16-bit PCM using the provided or default SoundFont.
	**/
	public static inline function decodeToPCM16(midiBytes:Bytes, ?soundFontBytes:Bytes):Null<DecodedAudio> {
		if (midiBytes == null || midiBytes.length <= 0) {
			setHaxeError("Invalid MIDI data");
			return null;
		}

		final sf2 = resolveSoundFont(soundFontBytes);
		if (sf2 == null)
			return null;

		final decoded = _decodeToPCM16(midiBytes, midiBytes.length, sf2, sf2.length);
		if (decoded == null)
			return null;

		clearHaxeError();
		return buildDecodedAudio(decoded, _decodedChannels(), _decodedSampleRate(), _decodedSamples(), false);
	}

	/**
		Returns the last error message produced by this library.
	**/
	public static inline function describeLastError():String {
		if (lastHaxeError.length > 0)
			return lastHaxeError;
		return @:privateAccess String.fromUTF8(_describeLastError());
	}

	@:hlNative("midisf2", "probe_midi")
	@:noCompletion
	static function _probeMidi(bytes:hl.Bytes, size:Int):Bool {
		return false;
	}

	@:hlNative("midisf2", "probe_soundfont")
	@:noCompletion
	static function _probeSoundFont(bytes:hl.Bytes, size:Int):Bool {
		return false;
	}

	@:hlNative("midisf2", "decode_pcm_float")
	@:noCompletion
	static function _decodeToPCMFloat(midiBytes:hl.Bytes, midiSize:Int, soundFontBytes:hl.Bytes, soundFontSize:Int):hl.Bytes {
		return null;
	}

	@:hlNative("midisf2", "decode_pcm_s16")
	@:noCompletion
	static function _decodeToPCM16(midiBytes:hl.Bytes, midiSize:Int, soundFontBytes:hl.Bytes, soundFontSize:Int):hl.Bytes {
		return null;
	}

	@:hlNative("midisf2", "decoded_channels")
	@:noCompletion
	static function _decodedChannels():Int {
		return 0;
	}

	@:hlNative("midisf2", "decoded_sample_rate")
	@:noCompletion
	static function _decodedSampleRate():Int {
		return 0;
	}

	@:hlNative("midisf2", "decoded_samples")
	@:noCompletion
	static function _decodedSamples():Int {
		return 0;
	}

	@:hlNative("midisf2", "describe_last_error")
	@:noCompletion
	static function _describeLastError():hl.Bytes {
		return null;
	}

	@:hlNative("midisf2", "system_midi_available")
	@:noCompletion
	static function _systemMidiAvailable():Bool {
		return false;
	}

	@:hlNative("midisf2", "play_system_midi")
	@:noCompletion
	static function _playSystemMidi(pathBytes:hl.Bytes, pathSize:Int, loop:Bool):Bool {
		return false;
	}

	@:hlNative("midisf2", "stop_system_midi")
	@:noCompletion
	static function _stopSystemMidi():Void {}

	@:hlNative("midisf2", "is_system_midi_playing")
	@:noCompletion
	static function _isSystemMidiPlaying():Bool {
		return false;
	}
}
