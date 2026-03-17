private enum TestPhase {
	Idle;
	SystemPlayback(label:String);
	HeapsPlayback(label:String);
	Done;
}

final class HeapsSmokeTest extends hxd.App {
	var phase:TestPhase = Idle;
	var channel:hxd.snd.Channel;
	var started = false;
	var systemStarted = false;
	var lastPosition = 0.0;
	var lastProgressAt = 0.0;
	var systemFixtures:Array<TestSupport.MidiFixture> = [];

	override function init():Void {
		try {
			TestSupport.testMidiProbes();
			TestSupport.testPreparedPlaybackFallback();

			if (TestSupport.hasSystemMidiPlayback()) {
				systemFixtures = TestSupport.getMidiFixtures().copy();
				playNextSystemFixture();
				return;
			}

			TestSupport.printSkip(TestSupport.SYSTEM_MIDI_PREFIX + "*", "system MIDI playback is only available on Windows");
			startHeapsPlayback();
		} catch (e) {
			fail(Std.string(e));
		}
	}

	private function startHeapsPlayback():Void {
		midisf2.Midi.stopSystemSynth();

		if (!TestSupport.hasSoundFont()) {
			TestSupport.printSkip(TestSupport.SOUNDFONT_MIDI_PREFIX + "*", TestSupport.missingSoundFontMessage());
			phase = Done;
			return;
		}

		final soundFontPath = TestSupport.getSoundFontPath();
		midisf2.Midi.setDefaultSoundFontFromFile(soundFontPath);
		TestSupport.printInfo("Using SoundFont: " + TestSupport.describeSoundFontSource());

		assertData(new hxd.snd.MidiData(TestSupport.buildGeneratedMidi()), TestSupport.GENERATED_MIDI_NAME);

		final label = "heaps-sound/" + TestSupport.TEST_MIDI_PATH;
		channel = hxd.Res.test.play();
		if (channel == null)
			fail(label + ": channel was not created");

		started = false;
		lastPosition = 0.0;
		lastProgressAt = haxe.Timer.stamp();
		phase = HeapsPlayback(label);
		TestSupport.printPlay(label);
	}

	private function playNextSystemFixture():Void {
		if (systemFixtures.length == 0) {
			startHeapsPlayback();
			return;
		}

		final fixture = systemFixtures.shift();
		final label = TestSupport.SYSTEM_MIDI_PREFIX + fixture.name;

		TestSupport.playSystemFixture(fixture);
		systemStarted = false;
		lastProgressAt = haxe.Timer.stamp();
		phase = SystemPlayback(label);
		TestSupport.printPlay(label);
	}

	private function assertData(data:hxd.snd.MidiData, label:String):Void {
		if (data.samples <= 0)
			fail(label + ": decoded sample count is zero");

		if (data.channels <= 0)
			fail(label + ": decoded channel count is zero");

		TestSupport.printOk("heaps-data/" + label);
	}

	override function update(dt:Float):Void {
		switch (phase) {
			case Idle:
			case Done:
				Sys.println("Heaps MIDI tests passed.");
				Sys.exit(0);
			case SystemPlayback(label):
				updateSystemPlayback(label);
			case HeapsPlayback(label):
				updateHeapsPlayback(label);
		}
	}

	private function updateSystemPlayback(label:String):Void {
		if (hxd.Key.isPressed(hxd.Key.SPACE)) {
			midisf2.Midi.stopSystemSynth();
			TestSupport.printOk(label);
			playNextSystemFixture();
			return;
		}

		final isPlaying = midisf2.Midi.isSystemSynthPlaying();

		if (!systemStarted && isPlaying) {
			systemStarted = true;
			lastProgressAt = haxe.Timer.stamp();
			return;
		}

		if (!systemStarted) {
			if (haxe.Timer.stamp() - lastProgressAt > 1.0)
				fail(label + ": playback never started");
			return;
		}

		if (!isPlaying) {
			midisf2.Midi.stopSystemSynth();
			TestSupport.printOk(label);
			playNextSystemFixture();
		}
	}

	private function updateHeapsPlayback(label:String):Void {
		if (channel == null)
			fail(label + ": channel is null");

		if (hxd.Key.isPressed(hxd.Key.SPACE)) {
			channel.stop();
			TestSupport.printOk(label);
			phase = Done;
			return;
		}

		if (!started && channel.position > 0) {
			started = true;
			lastPosition = channel.position;
			lastProgressAt = haxe.Timer.stamp();
		}

		if (channel.position > lastPosition) {
			lastPosition = channel.position;
			lastProgressAt = haxe.Timer.stamp();
		}

		if (started && channel.isReleased()) {
			TestSupport.printOk(label);
			phase = Done;
			return;
		}

		if (started && haxe.Timer.stamp() - lastProgressAt > 0.5)
			fail(label + ": playback stalled at " + lastPosition);
	}

	private function fail(message:String):Void {
		midisf2.Midi.stopSystemSynth();
		Sys.println("FAIL " + message);
		Sys.exit(1);
	}

	static function main():Void {
		hxd.Res.initLocal();
		new HeapsSmokeTest();
	}
}
