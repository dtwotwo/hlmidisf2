package midisf2.format;

enum abstract MidiFormat(String) from String to String {
	final MID = "mid";
	final MIDI = "midi";

	public static final values:Array<MidiFormat> = [MID, MIDI];
	public static final resourceExtensions:Array<MidiFormat> = values;

	public static function fromExtension(extension:String):Null<MidiFormat> {
		if (extension == null || extension.length == 0)
			return null;

		return switch (extension.toLowerCase()) {
			case MID: MID;
			case MIDI: MIDI;
			default: null;
		}
	}

	public static inline function fromPath(path:String):Null<MidiFormat> {
		return fromExtension(haxe.io.Path.extension(path));
	}

	public static inline function hasExtension(extension:String):Bool {
		return fromExtension(extension) != null;
	}

	public static inline function isMidiPath(path:String):Bool {
		return fromPath(path) != null;
	}
}
