import miniaudio.Miniaudio;
import miniaudio.Miniaudio.Buffer;
import miniaudio.Miniaudio.Sound;
import miniaudio.Miniaudio.SoundGroup;

private function main() {
	if (!Miniaudio.init()) {
		Sys.println("FAIL init: " + Miniaudio.describeLastError());
		Sys.exit(1);
	}

	var failed = false;
	final group = new SoundGroup();

	failed = runCheck("probe-midi", TestSupport.testMidiProbes, failed);
	failed = runCheck("invalid", TestSupport.testInvalidInput, failed);
	failed = runCheck("missing-soundfont", TestSupport.testMissingSoundFont, failed);

	if (TestSupport.hasSystemMidiPlayback()) {
		for (fixture in TestSupport.getMidiFixtures())
			failed = runSystemFixture(fixture, failed);
	} else
		TestSupport.printSkip(TestSupport.SYSTEM_MIDI_PREFIX + "*", "system MIDI playback is only available on Windows");

	if (TestSupport.hasSoundFont()) {
		TestSupport.printInfo("Using SoundFont: " + TestSupport.describeSoundFontSource());
		for (fixture in TestSupport.getRenderedMidiFixtures())
			failed = runRenderedFixture(group, fixture, failed);
	} else
		TestSupport.printSkip(TestSupport.SOUNDFONT_MIDI_PREFIX + "*", TestSupport.missingSoundFontMessage());

	group.dispose();
	Miniaudio.uninit();

	if (failed)
		Sys.exit(1);

	Sys.println("Miniaudio MIDI tests passed.");
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

private function runRenderedFixture(group:SoundGroup, fixture:TestSupport.MidiFixture, failed:Bool):Bool {
	final label = TestSupport.SOUNDFONT_MIDI_PREFIX + fixture.name;

	try {
		final decoded = TestSupport.decodeFixture(fixture);
		TestSupport.printPlay(label);
		playDecodedAudio(decoded.floatDecoded, group);
		TestSupport.printOk(label);
		return failed;
	} catch (e) {
		TestSupport.printFail(label, Std.string(e));
		return true;
	}
}

private function playDecodedAudio(decoded:midisf2.Midi.DecodedAudio, group:SoundGroup):Void {
	final buffer = Buffer.fromPCMFloat(decoded.bytes, decoded.channels, decoded.sampleRate);
	TestSupport.assert(buffer != null, "fromPCMFloat failed: " + Miniaudio.describeLastError());

	final sound = new Sound(buffer, group);
	TestSupport.assert(sound != null, "sound init failed: " + Miniaudio.describeLastError());
	TestSupport.assert(sound.start(), "playback start failed");
	TestSupport.assert(waitUntil(() -> return sound.isPlaying(), 0.25), "playback never started");

	final startCursor = sound.getCursorSamples();
	TestSupport.assert(waitUntil(() -> return sound.getCursorSamples() > startCursor, 0.5), "playback cursor did not advance");

	waitForBufferPlayback(sound, decoded.samples);

	sound.dispose();
	buffer.dispose();
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

private function waitForBufferPlayback(sound:Sound, totalSamples:Int):Void {
	var lastCursor = sound.getCursorSamples();
	var lastProgressAt = haxe.Timer.stamp();

	while (true) {
		if (TestInput.pollSpace()) {
			sound.stop();
			waitUntil(() -> return !sound.isPlaying(), 0.25);
			return;
		}

		if (!sound.isPlaying())
			return;

		final cursor = sound.getCursorSamples();
		if (cursor > lastCursor) {
			lastCursor = cursor;
			lastProgressAt = haxe.Timer.stamp();
		} else if (haxe.Timer.stamp() - lastProgressAt > 0.5)
			throw "playback stalled at sample " + lastCursor + " of " + totalSamples;

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
