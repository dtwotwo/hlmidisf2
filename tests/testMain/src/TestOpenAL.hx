import haxe.io.Bytes;
import openal.AL;
import openal.ALC;

private function main() {
	final device = ALC.openDevice(null);
	if (device == null) {
		Sys.println("FAIL init: could not open OpenAL device");
		Sys.exit(1);
	}

	final context = ALC.createContext(device, null);
	if (context == null || !ALC.makeContextCurrent(context)) {
		if (context != null)
			ALC.destroyContext(context);

		ALC.closeDevice(device);
		Sys.println("FAIL init: could not create OpenAL context");
		Sys.exit(1);
	}

	var failed = false;

	failed = runCheck("probe-midi", TestSupport.testMidiProbes, failed);
	failed = runCheck("invalid", TestSupport.testInvalidInput, failed);
	failed = runCheck("missing-soundfont", TestSupport.testMissingSoundFont, failed);
	failed = runCheck("prepared-playback", TestSupport.testPreparedPlaybackFallback, failed);

	if (TestSupport.hasSystemMidiPlayback()) {
		for (fixture in TestSupport.getMidiFixtures())
			failed = runSystemFixture(fixture, failed);
	} else
		TestSupport.printSkip(TestSupport.SYSTEM_MIDI_PREFIX + "*", "system MIDI playback is only available on Windows");

	if (TestSupport.hasSoundFont()) {
		TestSupport.printInfo("Using SoundFont: " + TestSupport.describeSoundFontSource());
		for (fixture in TestSupport.getRenderedMidiFixtures())
			failed = runRenderedFixture(fixture, failed);
	} else
		TestSupport.printSkip(TestSupport.SOUNDFONT_MIDI_PREFIX + "*", TestSupport.missingSoundFontMessage());

	ALC.makeContextCurrent(null);
	ALC.destroyContext(context);
	ALC.closeDevice(device);

	if (failed)
		Sys.exit(1);

	Sys.println("OpenAL MIDI tests passed.");
}

private function runCheck(label:String, check:Void->Void, failed:Bool):Bool {
	try {
		check();
		TestSupport.printOk(label);
		return failed;
	} catch (e) {
		TestSupport.printFail(label, Std.string(e));
		return true;
	}
}

private function runSystemFixture(fixture:TestSupport.MidiFixture, failed:Bool):Bool {
	final label = TestSupport.SYSTEM_MIDI_PREFIX + fixture.name;
	var result = failed;

	try {
		TestSupport.printPlay(label);
		TestSupport.playSystemFixture(fixture);
		waitForSystemPlayback();
		TestSupport.printOk(label);
	} catch (e) {
		TestSupport.printFail(label, Std.string(e));
		result = true;
	}

	TestSupport.stopSystemFixturePlayback();
	return result;
}

private function runRenderedFixture(fixture:TestSupport.MidiFixture, failed:Bool):Bool {
	final label = TestSupport.SOUNDFONT_MIDI_PREFIX + fixture.name;

	try {
		final decoded = TestSupport.decodeFixture(fixture);
		TestSupport.printPlay(label);
		playDecodedAudio(decoded.pcm16Decoded);
		TestSupport.printOk(label);
		return failed;
	} catch (e) {
		TestSupport.printFail(label, Std.string(e));
		return true;
	}
}

private function playDecodedAudio(decoded:midisf2.Midi.DecodedAudio):Void {
	final bufferIdBytes = Bytes.alloc(4);
	AL.genBuffers(1, @:privateAccess bufferIdBytes.b);

	final buffer:openal.Buffer = cast bufferIdBytes.getInt32(0);
	TestSupport.assert(AL.isBuffer(buffer), "generated buffer is invalid");

	final sourceIdBytes = Bytes.alloc(4);
	AL.genSources(1, @:privateAccess sourceIdBytes.b);

	final source:openal.Source = cast sourceIdBytes.getInt32(0);
	TestSupport.assert(AL.isSource(source), "generated source is invalid");

	final format = switch ([decoded.channels, decoded.floatFormat]) {
		case [1, false]: AL.FORMAT_MONO16;
		case [2, false]: AL.FORMAT_STEREO16;
		default: throw "unsupported OpenAL buffer format";
	};

	AL.bufferData(buffer, format, @:privateAccess decoded.bytes.b, decoded.bytes.length, decoded.sampleRate);
	TestSupport.assertEquals(AL.NO_ERROR, AL.getError(), "bufferData failed");

	AL.sourcei(source, AL.BUFFER, cast buffer);
	AL.sourcePlay(source);

	TestSupport.assert(waitUntil(() -> return AL.getSourcei(source, AL.SOURCE_STATE) == AL.PLAYING, 0.25), "source never entered playing state");
	TestSupport.assert(waitUntil(() -> return AL.getSourcei(source, AL.SAMPLE_OFFSET) > 0, 0.5), "sample offset did not advance");

	waitForBufferPlayback(source, decoded.samples);

	AL.sourceStop(source);
	AL.deleteSources(1, @:privateAccess sourceIdBytes.b);
	AL.deleteBuffers(1, @:privateAccess bufferIdBytes.b);

	TestSupport.assertEquals(AL.NO_ERROR, AL.getError(), "cleanup failed");
}

private function waitForSystemPlayback():Void {
	TestSupport.assert(waitUntil(() -> return midisf2.Midi.isSystemSynthPlaying(), 0.5), "system MIDI playback never started");

	var playing = true;
	while (playing) {
		if (TestInput.pollSpace())
			return;

		playing = midisf2.Midi.isSystemSynthPlaying();
		Sys.sleep(0.01);
	}
}

private function waitForBufferPlayback(source:openal.Source, totalSamples:Int):Void {
	var lastOffset = AL.getSourcei(source, AL.SAMPLE_OFFSET);
	var lastProgressAt = haxe.Timer.stamp();

	while (true) {
		if (TestInput.pollSpace()) {
			AL.sourceStop(source);
			return;
		}

		final state = AL.getSourcei(source, AL.SOURCE_STATE);
		if (state != AL.PLAYING)
			return;

		final offset = AL.getSourcei(source, AL.SAMPLE_OFFSET);
		if (offset != lastOffset) {
			lastOffset = offset;
			lastProgressAt = haxe.Timer.stamp();
		} else if (haxe.Timer.stamp() - lastProgressAt > 0.5)
			throw "playback stalled at sample " + lastOffset + " of " + totalSamples;

		Sys.sleep(0.01);
	}
}

private function waitUntil(check:Void->Bool, timeoutSeconds:Float):Bool {
	final deadline = haxe.Timer.stamp() + timeoutSeconds;
	while (haxe.Timer.stamp() < deadline) {
		if (check())
			return true;

		Sys.sleep(0.01);
	}

	return check();
}
