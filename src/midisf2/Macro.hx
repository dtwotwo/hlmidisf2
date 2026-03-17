package midisf2;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Field;

using Lambda;

/**
	Build macro that extends `hxd.res.Sound` with MIDI-aware behavior.

	It teaches Heaps sound resources to recognize MIDI files, decode them
	through `MidiData`, and fall back to `SystemMidiChannel` when no
	default SoundFont is configured but OS MIDI playback is available.
**/
final class Macro {
	/**
		Patches `hxd.res.Sound` during compilation.
	**/
	public static macro function buildSound():Array<Field> {
		final fields = Context.getBuildFields();

		if (!fields.exists(f -> f.name == "isMidiPath")) {
			fields.push({
				name: "isMidiPath",
				access: [APrivate, AStatic],
				kind: FFun({
					args: [{name: "path", type: macro :String}],
					ret: macro :Bool,
					expr: macro {
						return midisf2.format.MidiFormat.isMidiPath(path);
					}
				}),
				pos: Context.currentPos()
			});
		}

		final getDataField = fields.find(f -> f.name == "getData");
		if (getDataField != null) {
			switch getDataField.kind {
				case FFun(fn):
					final originalExpr = fn.expr;
					fn.expr = macro {
						if (data == null) {
							if (isMidiPath(entry.path)) {
								final bytes = entry.getBytes();
								if (midisf2.Midi.probeMidi(bytes))
									data = new hxd.snd.MidiData(bytes);
							}
						}

						if (data != null)
							return data;

						return $originalExpr;
					};
				default:
			}
		}

		final playField = fields.find(f -> f.name == "play");
		if (playField != null) {
			switch playField.kind {
				case FFun(fn):
					final originalExpr = fn.expr;
					fn.expr = macro {
						if (isMidiPath(entry.path) && !midisf2.Midi.hasDefaultSoundFont() && midisf2.Midi.isSystemPlaybackSupported()) {
							lastPlay = haxe.Timer.stamp();
							stop();
							if (!midisf2.Midi.playBytesWithSystemSynth(entry.getBytes(), loop, entry.path))
								throw midisf2.Midi.describeLastError();
							channel = new hxd.snd.SystemMidiChannel(this, loop, volume);
							return channel;
						}

						return $originalExpr;
					};
				default:
			}
		}

		return fields;
	}
}
