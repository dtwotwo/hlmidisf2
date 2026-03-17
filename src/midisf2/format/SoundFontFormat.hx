package midisf2.format;

enum abstract SoundFontFormat(String) from String to String {
	final SF2 = "sf2";

	public static final values:Array<SoundFontFormat> = [SF2];
	public static final resourceExtensions:Array<SoundFontFormat> = values;

	public static function fromExtension(extension:String):Null<SoundFontFormat> {
		if (extension == null || extension.length == 0)
			return null;

		return switch (extension.toLowerCase()) {
			case SF2: SF2;
			default: null;
		}
	}

	public static inline function fromPath(path:String):Null<SoundFontFormat> {
		return fromExtension(haxe.io.Path.extension(path));
	}

	public static inline function hasExtension(extension:String):Bool {
		return fromExtension(extension) != null;
	}

	public static inline function isSoundFontPath(path:String):Bool {
		return fromPath(path) != null;
	}
}
