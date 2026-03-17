import haxe.io.Bytes;
import midisf2.Midi;

typedef FixtureDecode = {
	name:String,
	floatDecoded:midisf2.Midi.DecodedAudio,
	pcm16Decoded:midisf2.Midi.DecodedAudio,
}

typedef MidiFixture = {
	name:String,
	bytes:Bytes,
	path:Null<String>,
}

class TestSupport {
	public static final MIDI_DIR = "midi";
	public static final SF2_DIR = "sf2";
	public static final TEST_MIDI_PATH = MIDI_DIR + "/test.mid";
	public static final GENERATED_MIDI_NAME = "generated-midi";
	public static final SYSTEM_MIDI_PREFIX = "system-midi/";
	public static final SOUNDFONT_MIDI_PREFIX = "soundfont-midi/";

	static final GENERATED_MIDI_HEX = "4d546864000000060000000100604d54726b0000000f00c00000903c6460803c4000ff2f00"; // C-5 Piano 1 v127
	static var soundFontPathScanned = false;
	static var cachedSoundFontPath:Null<String>;
	static var soundFontBytesLoaded = false;
	static var cachedSoundFontBytes:Null<Bytes>;

	public static function getMidiFixtures():Array<MidiFixture> {
		return [
			{
				name: GENERATED_MIDI_NAME,
				bytes: buildGeneratedMidi(),
				path: null,
			},
			{
				name: TEST_MIDI_PATH,
				bytes: loadMidiFile(TEST_MIDI_PATH),
				path: TEST_MIDI_PATH,
			},
		];
	}

	public static function getRenderedMidiFixtures():Array<MidiFixture> {
		return getMidiFixtures();
	}

	public static function buildGeneratedMidi():Bytes {
		return Bytes.ofHex(GENERATED_MIDI_HEX);
	}

	public static function loadMidiFile(path:String):Bytes {
		assert(sys.FileSystem.exists(path), "Missing MIDI fixture: " + path);
		return sys.io.File.getBytes(path);
	}

	public static function findLocalSoundFontPath():Null<String> {
		if (soundFontPathScanned)
			return cachedSoundFontPath;

		soundFontPathScanned = true;
		cachedSoundFontPath = null;

		if (!sys.FileSystem.exists(SF2_DIR) || !sys.FileSystem.isDirectory(SF2_DIR))
			return null;

		for (entry in sys.FileSystem.readDirectory(SF2_DIR)) {
			final path = haxe.io.Path.join([SF2_DIR, entry]);
			if (!sys.FileSystem.isDirectory(path) && midisf2.format.SoundFontFormat.isSoundFontPath(path)) {
				cachedSoundFontPath = path;
				return path;
			}
		}

		return null;
	}

	public static function getSoundFontPath():Null<String> {
		return findLocalSoundFontPath();
	}

	public static function loadSoundFont():Null<Bytes> {
		if (soundFontBytesLoaded)
			return cachedSoundFontBytes;

		soundFontBytesLoaded = true;
		final path = getSoundFontPath();
		if (path == null)
			return null;

		cachedSoundFontBytes = sys.io.File.getBytes(path);
		return cachedSoundFontBytes;
	}

	public static function describeSoundFontSource():String {
		final path = getSoundFontPath();
		if (path != null)
			return path;

		return SF2_DIR + "/<put-your-file.sf2-here>";
	}

	public static function missingSoundFontMessage():String {
		return "put a .sf2 file into " + SF2_DIR + "/";
	}

	public static function hasSoundFont():Bool {
		return getSoundFontPath() != null;
	}

	public static function hasSystemMidiPlayback():Bool {
		return Midi.isSystemPlaybackSupported();
	}

	public static function assert(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	public static function assertEquals<T>(expected:T, actual:T, message:String):Void {
		if (expected != actual)
			throw '$message (expected=$expected, actual=$actual)';
	}

	public static function decodeFixture(fixture:MidiFixture):FixtureDecode {
		final soundFont = loadSoundFont();
		assert(soundFont != null, "Missing SoundFont fixture. " + missingSoundFontMessage() + ".");

		assert(Midi.probeMidi(fixture.bytes), "probeMidi failed for fixture " + fixture.name);
		assert(Midi.probeSoundFont(soundFont), "probeSoundFont failed for SoundFont fixture " + describeSoundFontSource());

		final floatDecoded = Midi.decodeToPCMFloat(fixture.bytes, soundFont);
		assert(floatDecoded != null, "float decode failed for " + fixture.name + ": " + Midi.describeLastError());
		assertDecodedAudio(floatDecoded, true);

		final pcm16Decoded = Midi.decodeToPCM16(fixture.bytes, soundFont);
		assert(pcm16Decoded != null, "s16 decode failed for " + fixture.name + ": " + Midi.describeLastError());
		assertDecodedAudio(pcm16Decoded, false);

		assertEquals(floatDecoded.channels, pcm16Decoded.channels, "channel mismatch between decode paths for " + fixture.name);
		assertEquals(floatDecoded.sampleRate, pcm16Decoded.sampleRate, "sample rate mismatch between decode paths for " + fixture.name);
		assert(floatDecoded.samples > 0, "float decode produced zero samples for " + fixture.name);
		assert(pcm16Decoded.samples > 0, "s16 decode produced zero samples for " + fixture.name);

		return {
			name: fixture.name,
			floatDecoded: floatDecoded,
			pcm16Decoded: pcm16Decoded,
		};
	}

	public static function assertDecodedAudio(decoded:midisf2.Midi.DecodedAudio, floatFormat:Bool):Void {
		final bytesPerSample = floatFormat ? 4 : 2;

		assert(decoded.channels > 0, "invalid channel count");
		assert(decoded.sampleRate > 0, "invalid sample rate");
		assert(decoded.samples > 0, "invalid sample count");
		assertEquals(floatFormat, decoded.floatFormat, "unexpected format flag");
		assertEquals(decoded.samples * decoded.channels * bytesPerSample, decoded.bytes.length, "unexpected decoded byte count");
	}

	public static function testMidiProbes():Void {
		for (fixture in getMidiFixtures())
			assert(Midi.probeMidi(fixture.bytes), "MIDI fixture should probe successfully: " + fixture.name);
	}

	public static function testInvalidInput():Void {
		final invalid = Bytes.ofString("not midi data");

		assert(!Midi.probeMidi(invalid), "invalid MIDI probe should return false");
		assert(!Midi.probeSoundFont(invalid), "invalid SoundFont probe should return false");
		assert(Midi.decodeToPCM16(invalid, invalid) == null, "invalid decode should fail");
		assert(Midi.describeLastError().length > 0, "invalid decode should populate error");
	}

	public static function testMissingSoundFont():Void {
		Midi.clearDefaultSoundFont();
		assert(Midi.decodeToPCM16(buildGeneratedMidi()) == null, "decode without SoundFont should fail");
		assertEquals("No SoundFont provided. Pass .sf2 bytes to decode or call midisf2.Midi.setDefaultSoundFont() / setDefaultSoundFontFromFile() first.", Midi.describeLastError(), "missing SoundFont should explain failure");
	}

	public static function testPreparedPlaybackFallback():Void {
		Midi.clearDefaultSoundFont();
		final prepared = Midi.preparePlaybackPCM16(buildGeneratedMidi(), null, false, GENERATED_MIDI_NAME + ".mid");

		if (hasSystemMidiPlayback()) {
			assert(prepared != null, "prepared playback should succeed with system synth fallback");
			switch (prepared) {
				case System:
				case Rendered(_):
					throw "prepared playback should use system synth when no SoundFont is set";
			}
			Midi.stopSystemSynth();
			return;
		}

		assert(prepared == null, "prepared playback without SoundFont should fail when system synth is unavailable");
		assertEquals("No SoundFont provided. Pass .sf2 bytes to decode or call midisf2.Midi.setDefaultSoundFont() / setDefaultSoundFontFromFile() first.", Midi.describeLastError(),
			"missing SoundFont should still explain the failure when no fallback is available");
	}

	public static function playSystemFixture(fixture:MidiFixture):Void {
		final ok = fixture.path != null ? Midi.playWithSystemSynth(fixture.path) : Midi.playBytesWithSystemSynth(fixture.bytes, false, fixture.name + ".mid");
		assert(ok, "system MIDI playback failed for " + fixture.name + ": " + Midi.describeLastError());
	}

	public static function stopSystemFixturePlayback():Void {
		Midi.stopSystemSynth();
	}

	public static function printPlay(label:String):Void {
		Sys.println("PLAY " + label + " [space = skip]");
	}

	public static function printInfo(message:String):Void {
		Sys.println("INFO " + message);
	}

	public static function printOk(label:String):Void {
		Sys.println("OK   " + label);
	}

	public static function printSkip(label:String, message:String):Void {
		Sys.println("SKIP " + label + ": " + message);
	}

	public static function printFail(label:String, message:String):Void {
		Sys.println("FAIL " + label + ": " + message);
	}
}
