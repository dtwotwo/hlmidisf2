package midisf2;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import midisf2.format.MidiFormat;
#if heaps
import hxd.res.Config;
#end

/**
	Macro bootstrap for Heaps integration.

	Call `midisf2.Boot.setup()` from your build macros to register MIDI
	resources as `hxd.res.Sound` and install the sound patching macro.
**/
final class Boot {
	/**
		Installs the Heaps resource and macro hooks for MIDI support.
	**/
	public static function setup() {
		#if (haxe_ver >= 5)
		Context.onAfterInitMacros(() -> apply());
		#else
		apply();
		#end

		return null;
	}

	static function apply() {
		#if heaps
		for (ext in MidiFormat.resourceExtensions)
			Config.addExtension(ext, "hxd.res.Sound");
		#end
		Compiler.addMetadata("@:build(midisf2.Macro.buildSound())", "hxd.res.Sound");
	}
}
#else

/**
	Runtime placeholder for non-macro builds.
**/
final class Boot {}
#end
