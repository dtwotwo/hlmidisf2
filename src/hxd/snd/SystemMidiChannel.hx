package hxd.snd;

/**
	Minimal Heaps channel wrapper for OS-level MIDI playback.

	This channel is used when a MIDI `hxd.res.Sound` falls back to the
	system synth instead of rendered SoundFont playback.
**/
final class SystemMidiChannel extends Channel {
	var released = false;
	var startedAt = 0.0;

	/**
		Creates a channel bound to active system MIDI playback.
	**/
	public function new(sound:hxd.res.Sound, ?loop = false, ?volume = 1.0) {
		super();
		this.sound = sound;
		this.loop = loop;
		this.volume = volume;
		startedAt = haxe.Timer.stamp();
		position = 0.0;
		duration = 0.0;
	}

	inline function syncState():Void {
		if (released)
			return;

		if (midisf2.Midi.isSystemSynthPlaying()) {
			position = haxe.Timer.stamp() - startedAt;
			return;
		}

		released = true;
	}

	override function set_position(v:Float) {
		syncState();
		return position;
	}

	override function set_pause(v:Bool) {
		if (v && !released)
			stop();
		return pause = v;
	}

	/**
		Stops system MIDI playback and releases this channel.
	**/
	public override function stop() {
		if (!released)
			midisf2.Midi.stopSystemSynth();
		released = true;
	}

	/**
		Returns `true` once system playback has finished or was stopped.
	**/
	public override function isReleased() {
		syncState();
		return released;
	}
}
