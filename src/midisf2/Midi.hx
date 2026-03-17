package midisf2;

import haxe.io.Bytes;

typedef DecodedAudio = {
	bytes:Bytes,
	channels:Int,
	sampleRate:Int,
	samples:Int,
	floatFormat:Bool,
}

class Midi {
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

	public static function setDefaultSoundFont(bytes:Bytes):Void {
		if (bytes == null || bytes.length <= 0)
			throw "Invalid SoundFont data";
		if (!probeSoundFont(bytes))
			throw "Invalid SoundFont data";

		applyDefaultSoundFont(bytes, null);
	}

	public static function setDefaultSoundFontFromFile(path:String):Void {
		if (path == null || path.length == 0)
			throw "Invalid SoundFont path";
		if (!sys.FileSystem.exists(path))
			throw "SoundFont file not found: " + path;

		setDefaultSoundFont(sys.io.File.getBytes(path));
		defaultSoundFontPath = path;
	}

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

	public static function clearDefaultSoundFont():Void {
		defaultSoundFont = null;
		defaultSoundFontPath = null;
	}

	public static inline function hasDefaultSoundFont():Bool {
		return defaultSoundFont != null && defaultSoundFont.length > 0;
	}

	public static inline function getDefaultSoundFontPath():Null<String> {
		return defaultSoundFontPath;
	}

	public static inline function probeMidi(bytes:Bytes):Bool {
		if (bytes == null || bytes.length <= 0)
			return false;
		return _probeMidi(bytes, bytes.length);
	}

	public static inline function probeSoundFont(bytes:Bytes):Bool {
		if (bytes == null || bytes.length <= 0)
			return false;
		return _probeSoundFont(bytes, bytes.length);
	}

	public static inline function isSystemPlaybackSupported():Bool {
		return _systemMidiAvailable();
	}

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

	public static function stopSystemSynth():Void {
		_stopSystemMidi();
		deleteSystemTempMidi();
	}

	public static inline function isSystemSynthPlaying():Bool {
		return _isSystemMidiPlaying();
	}

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
