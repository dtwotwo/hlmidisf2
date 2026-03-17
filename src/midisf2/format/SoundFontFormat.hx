package midisf2.format;

/**
	Known SoundFont file extensions used by the library.
**/
enum abstract SoundFontFormat(String) from String to String {
	final SF2 = "sf2";

	/**
		Extensions that should be treated as SoundFont resources.
	**/
	public static final resourceExtensions:Array<SoundFontFormat> = [SF2];

	/**
		Resolves a SoundFont format from a file extension.
	**/
	public static function fromExtension(extension:String):Null<SoundFontFormat> {
		if (extension == null || extension.length == 0)
			return null;

		return switch (extension.toLowerCase()) {
			case SF2: SF2;
			default: null;
		}
	}

	/**
		Resolves a SoundFont format from a file path.
	**/
	public static inline function fromPath(path:String):Null<SoundFontFormat> {
		return fromExtension(haxe.io.Path.extension(path));
	}

	/**
		Returns `true` when the extension is recognized as SoundFont.
	**/
	public static inline function hasExtension(extension:String):Bool {
		return fromExtension(extension) != null;
	}

	/**
		Returns `true` when the file path points to a SoundFont resource.
	**/
	public static inline function isSoundFontPath(path:String):Bool {
		return fromPath(path) != null;
	}
}
