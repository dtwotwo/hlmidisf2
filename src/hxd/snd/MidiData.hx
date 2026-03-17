package hxd.snd;

import haxe.io.Bytes;

/**
	Heaps sound data implementation for MIDI resources.

	This class renders MIDI bytes into PCM16 through `midisf2.Midi`
	and exposes the result as regular `hxd.snd.Data`.
	A SoundFont must be available for this path.
**/
final class MidiData extends hxd.snd.Data {
	final rawData:Bytes;

	/**
		Creates sound data from MIDI bytes.

		Throws when the MIDI cannot be rendered, for example when no
		default SoundFont is configured.
	**/
	public function new(bytes:Bytes) {
		final decoded = midisf2.Midi.decodeToPCM16(bytes);
		if (decoded == null)
			throw midisf2.Midi.describeLastError();

		rawData = decoded.bytes;
		channels = decoded.channels;
		samplingRate = decoded.sampleRate;
		samples = decoded.samples;
		sampleFormat = I16;
	}

	override function decodeBuffer(out:Bytes, outPos:Int, sampleStart:Int, sampleCount:Int):Void {
		final bytesPerSample = getBytesPerSample();
		out.blit(outPos, rawData, sampleStart * bytesPerSample, sampleCount * bytesPerSample);
	}
}
