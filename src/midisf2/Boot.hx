package midisf2;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import midisf2.format.MidiFormat;
#if heaps
import hxd.res.Config;
#end

class Boot {
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
		Compiler.addGlobalMetadata("hxd.res.Sound", "@:build(midisf2.Macro.buildSound())", false, true, false);
	}
}
#else
class Boot {}
#end
