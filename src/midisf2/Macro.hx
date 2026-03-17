package midisf2;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Field;

using Lambda;

class Macro {
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

		return fields;
	}
}
