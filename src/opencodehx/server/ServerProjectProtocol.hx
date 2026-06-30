package opencodehx.server;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import opencodehx.project.ProjectRuntime.ProjectCommands;
import opencodehx.project.ProjectRuntime.ProjectIcon;
import opencodehx.project.ProjectRuntime.ProjectID;
import opencodehx.project.ProjectRuntime.ProjectUpdate;
import opencodehx.server.ServerProtocol.DecodeResult;

typedef DecodedProjectUpdate = {
	final name:Null<String>;
	final icon:Null<ProjectIcon>;
	final commands:Null<ProjectCommands>;
}

/**
	Decodes the small project-update JSON body accepted by the server route.

	Hono hands route bodies to Haxe as `Unknown`; this module narrows that
	boundary into `ProjectUpdate` immediately so `OpenCodeServer` and
	`ProjectRuntime` stay on typed records.
**/
function decodeProjectUpdate(projectID:ProjectID, raw:Unknown):DecodeResult<ProjectUpdate> {
	final record = UnknownNarrow.record(raw);
	if (record == null)
		return Rejected("Project update body must be an object");
	return switch decodeFields(record) {
		case Rejected(message):
			Rejected(message);
		case Decoded(fields):
			Decoded({
				projectID: projectID,
				name: fields.name,
				icon: fields.icon,
				commands: fields.commands,
			});
	}
}

function decodeFields(record:UnknownRecord):DecodeResult<DecodedProjectUpdate> {
	return switch optionalString(record, "name") {
		case Rejected(message):
			Rejected(message);
		case Decoded(name):
			switch decodeIcon(record) {
				case Rejected(message):
					Rejected(message);
				case Decoded(icon):
					switch decodeCommands(record) {
						case Rejected(message):
							Rejected(message);
						case Decoded(commands):
							Decoded({
								name: name,
								icon: icon,
								commands: commands,
							});
					}
			}
	}
}

function decodeIcon(record:UnknownRecord):DecodeResult<Null<ProjectIcon>> {
	if (!record.hasOwn("icon") || UnknownNarrow.isUndefined(record.get("icon")))
		return Decoded(null);
	if (UnknownNarrow.isNull(record.get("icon")))
		return Rejected("icon: expected object");
	final icon = UnknownNarrow.record(record.get("icon"));
	if (icon == null)
		return Rejected("icon: expected object");
	return switch optionalString(icon, "url") {
		case Rejected(message):
			Rejected('icon.${message}');
		case Decoded(url):
			switch optionalString(icon, "override") {
				case Rejected(message):
					Rejected('icon.${message}');
				case Decoded(overrideValue):
					switch optionalString(icon, "color") {
						case Rejected(message):
							Rejected('icon.${message}');
						case Decoded(color):
							Decoded({
								url: url,
								overrideValue: overrideValue,
								color: color,
							});
					}
			}
	}
}

function decodeCommands(record:UnknownRecord):DecodeResult<Null<ProjectCommands>> {
	if (!record.hasOwn("commands") || UnknownNarrow.isUndefined(record.get("commands")))
		return Decoded(null);
	if (UnknownNarrow.isNull(record.get("commands")))
		return Rejected("commands: expected object");
	final commands = UnknownNarrow.record(record.get("commands"));
	if (commands == null)
		return Rejected("commands: expected object");
	return switch optionalString(commands, "start") {
		case Rejected(message):
			Rejected('commands.${message}');
		case Decoded(start):
			Decoded({start: start});
	}
}

function optionalString(record:UnknownRecord, field:String):DecodeResult<Null<String>> {
	if (!record.hasOwn(field) || UnknownNarrow.isUndefined(record.get(field)))
		return Decoded(null);
	if (UnknownNarrow.isNull(record.get(field)))
		return Rejected('${field}: expected string');
	final value = UnknownNarrow.string(record.get(field));
	return value == null ? Rejected('${field}: expected string') : Decoded(value);
}
