package midisf2.format;

/**
	Known MIDI file extensions used by the library.
**/
enum abstract MidiFormat(String) from String to String {
	final MID = "mid";
	final MIDI = "midi";

	/**
		Extensions that should be treated as MIDI resources.
	**/
	public static final resourceExtensions:Array<MidiFormat> = [MID, MIDI];

	/**
		Resolves a MIDI format from a file extension.
	**/
	public static function fromExtension(extension:String):Null<MidiFormat> {
		if (extension == null || extension.length == 0)
			return null;

		return switch (extension.toLowerCase()) {
			case MID: MID;
			case MIDI: MIDI;
			default: null;
		}
	}

	/**
		Resolves a MIDI format from a file path.
	**/
	public static inline function fromPath(path:String):Null<MidiFormat> {
		return fromExtension(haxe.io.Path.extension(path));
	}

	/**
		Returns `true` when the extension is recognized as MIDI.
	**/
	public static inline function hasExtension(extension:String):Bool {
		return fromExtension(extension) != null;
	}

	/**
		Returns `true` when the file path points to a MIDI resource.
	**/
	public static inline function isMidiPath(path:String):Bool {
		return fromPath(path) != null;
	}
}
