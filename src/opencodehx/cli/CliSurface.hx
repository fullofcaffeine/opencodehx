package opencodehx.cli;

import opencodehx.BuildInfo;

typedef CliOptionInfo = {
	final name:String;
	final aliases:Array<String>;
	final value:Bool;
	final positional:Bool;
	final description:String;
}

typedef CliCommandInfo = {
	final name:String;
	final usage:String;
	final description:String;
	final aliases:Array<String>;
	final options:Array<CliOptionInfo>;
	final subcommands:Array<CliCommandInfo>;
	final implemented:Bool;
	final visible:Bool;
}

typedef CliSurfaceMatch = {
	final command:CliCommandInfo;
	final path:Array<String>;
}

class CliSurface {
	static final NETWORK_OPTIONS:Array<CliOptionInfo> = [
		opt("port", "port to listen on", true),
		opt("hostname", "hostname to listen on", true),
		opt("mdns", "enable mDNS service discovery (defaults hostname to 0.0.0.0)", false),
		opt("mdns-domain", "custom domain name for mDNS service (default: opencode.local)", true),
		opt("cors", "additional domains to allow for CORS", true),
	];

	static final COMMANDS:Array<CliCommandInfo> = [
		cmd("acp", "acp", "start ACP (Agent Client Protocol) server", {
			options: NETWORK_OPTIONS.concat([opt("cwd", "working directory", true)])
		}),
		cmd("mcp", "mcp", "manage MCP (Model Context Protocol) servers", {
			subcommands: [
				cmd("list", "mcp list", "list MCP servers and their status", {aliases: ["ls"]}),
				cmd("auth", "mcp auth [name]", "authenticate with an OAuth-enabled MCP server", {
					options: [arg("name", "name of the MCP server")]
				}),
				cmd("logout", "mcp logout [name]", "remove OAuth credentials for an MCP server", {
					options: [arg("name", "name of the MCP server")]
				}),
				cmd("add", "mcp add", "add an MCP server"),
				cmd("debug", "mcp debug <name>", "debug OAuth connection for an MCP server", {
					options: [arg("name", "name of the MCP server")]
				}),
			]
		}),
		cmd("run", "run [message..]", "run opencode with a message", {
			implemented: true,
			options: [
				arg("message", "message to send"),
				opt("command", "the command to run, use message for args", true),
				opt("continue", "continue the last session", false, ["c"]),
				opt("session", "session id to continue", true, ["s"]),
				opt("fork", "fork the session before continuing (requires --continue or --session)", false),
				opt("share", "share the session", false),
				opt("model", "model to use in the format of provider/model", true, ["m"]),
				opt("agent", "agent to use", true),
				opt("format", "format: default (formatted) or json (raw JSON events)", true),
				opt("file", "file(s) to attach to message", true, ["f"]),
				opt("title", "title for the session (uses truncated prompt if no value provided)", true),
				opt("attach", "attach to a running opencode server (e.g., http://localhost:4096)", true),
				opt("password", "basic auth password (defaults to OPENCODE_SERVER_PASSWORD)", true, ["p"]),
				opt("dir", "directory to run in, path on remote server if attaching", true),
				opt("port", "port for the local server (defaults to random port if no value provided)", true),
				opt("variant", "model variant (provider-specific reasoning effort, e.g., high, max, minimal)", true),
				opt("thinking", "show thinking blocks", false),
				opt("dangerously-skip-permissions", "auto-approve permissions that are not explicitly denied (dangerous!)", false),
			]
		}),
		cmd("generate", "generate", "generate OpenAPI output"),
		cmd("debug", "debug", "debugging and troubleshooting tools", {
			subcommands: [
				cmd("config", "debug config", "show resolved configuration"),
				cmd("lsp", "debug lsp", "LSP debugging utilities", {
					subcommands: [
						cmd("diagnostics", "debug lsp diagnostics <file>", "get diagnostics for a file", {options: [arg("file", "file path")]}),
						cmd("symbols", "debug lsp symbols <query>", "search workspace symbols", {options: [arg("query", "symbol query")]}),
						cmd("document-symbols", "debug lsp document-symbols <uri>", "get symbols from a document", {options: [arg("uri", "document URI")]}),
					]
				}),
				cmd("rg", "debug rg", "ripgrep debugging utilities", {
					subcommands: [
						cmd("tree", "debug rg tree", "show file tree using ripgrep", {options: [opt("limit", "maximum results", true)]}),
						cmd("files", "debug rg files", "list files using ripgrep", {
							options: [
								opt("query", "file query", true),
								opt("glob", "glob filter", true),
								opt("limit", "maximum results", true),
							]
						}),
						cmd("search", "debug rg search <pattern>", "search file contents using ripgrep", {
							options: [
								arg("pattern", "search pattern"),
								opt("glob", "glob filter", true),
								opt("limit", "maximum results", true),
							]
						}),
					]
				}),
				cmd("file", "debug file", "file system debugging utilities",
					{
						subcommands: [
							cmd("search", "debug file search <query>", "search files by query", {options: [arg("query", "search query")]}),
							cmd("read", "debug file read <path>", "read file contents as JSON", {options: [arg("path", "file path")]}),
							cmd("status", "debug file status", "show file status information"),
							cmd("list", "debug file list <path>", "list files in a directory", {options: [arg("path", "directory path")]}),
							cmd("tree", "debug file tree [dir]", "show directory tree", {options: [arg("dir", "directory path")]}),
						]
					}),
				cmd("scrap", "debug scrap", "list all known projects"),
				cmd("skill", "debug skill", "list all available skills"),
				cmd("snapshot", "debug snapshot", "snapshot debugging utilities", {
					subcommands: [
						cmd("track", "debug snapshot track", "track current snapshot state"),
						cmd("patch", "debug snapshot patch <hash>", "show patch for a snapshot hash", {
							options: [arg("hash", "snapshot hash")]
						}),
						cmd("diff", "debug snapshot diff <hash>", "show diff for a snapshot hash", {options: [arg("hash", "snapshot hash")]}),
					]
				}),
				cmd("agent", "debug agent <name>", "show agent configuration details", {
					options: [
						arg("name", "agent name"),
						opt("tool", "tool name", true),
						opt("params", "tool params", true),
					]
				}),
				cmd("paths", "debug paths", "show global paths (data, config, cache, state)"),
				cmd("wait", "debug wait", "wait indefinitely (for debugging)"),
			]
		}),
		cmd("console", "console", "manage console accounts", {
			visible: false,
			subcommands: [
				cmd("login", "console login <url>", "log in to console", {options: [arg("url", "server URL")]}),
				cmd("logout", "console logout [email]", "log out from console", {options: [arg("email", "account email to log out from")]}),
				cmd("switch", "console switch", "switch active org"),
				cmd("orgs", "console orgs", "list orgs"),
				cmd("open", "console open", "open active console account"),
			]
		}),
		cmd("providers", "providers", "manage AI providers and credentials", {
			aliases: ["auth"],
			subcommands: [
				cmd("list", "providers list", "list providers and credentials", {aliases: ["ls"]}),
				cmd("login", "providers login [url]", "log in to a provider", {
					options: [
						arg("url", "opencode auth provider"),
						opt("provider", "provider id or name to log in to (skips provider selection)", true, ["p"]),
						opt("method", "login method label (skips method selection)", true, ["m"]),
					]
				}),
				cmd("logout", "providers logout", "log out from a configured provider"),
			]
		}),
		cmd("agent", "agent", "manage agents", {
			subcommands: [
				cmd("create", "agent create", "create a new agent", {
					options: [
						opt("path", "directory path to generate the agent file", true),
						opt("description", "what the agent should do", true),
						opt("mode", "agent mode", true),
						opt("tools", "comma-separated list of tools to enable", true),
						opt("model", "model to use in the format of provider/model", true, ["m"]),
					]
				}),
				cmd("list", "agent list", "list all available agents"),
			]
		}),
		cmd("upgrade", "upgrade [target]", "upgrade opencode to the latest or a specific version", {
			options: [
				arg("target", "version to upgrade to, for ex '0.1.48' or 'v0.1.48'"),
				opt("method", "installation method to use", true, ["m"]),
			]
		}),
		cmd("uninstall", "uninstall", "uninstall opencode and remove all related files",
			{
				options: [
					opt("keep-config", "keep configuration files", false, ["c"]),
					opt("keep-data", "keep session data and snapshots", false, ["d"]),
					opt("dry-run", "show what would be removed without removing", false),
					opt("force", "skip confirmation prompts", false, ["f"]),
				]
			}),
		cmd("serve", "serve", "starts a headless opencode server", {options: NETWORK_OPTIONS}),
		cmd("web", "web", "start opencode server and open web interface", {options: NETWORK_OPTIONS}),
		cmd("models", "models [provider]", "list all available models", {
			options: [
				arg("provider", "provider ID to filter models by"),
				opt("verbose", "use more verbose model output (includes metadata like costs)", false),
				opt("refresh", "refresh the models cache from models.dev", false),
			]
		}),
		cmd("stats", "stats", "show token usage and cost statistics", {
			options: [
				opt("days", "show stats for the last N days (default: all time)", true),
				opt("tools", "number of tools to show (default: all)", true),
				opt("models", "show model statistics (default: hidden). Pass a number to show top N, otherwise shows all", true),
				opt("project", "filter by project (default: all projects, empty string: current project)", true),
			]
		}),
		cmd("export", "export [sessionID]", "export session data as JSON", {
			options: [
				arg("sessionID", "session id to export"),
				opt("sanitize", "redact sensitive transcript and file data", false),
			]
		}),
		cmd("import", "import <file>", "import session data from JSON file or URL", {
			options: [arg("file", "path to JSON file or share URL")]
		}),
		cmd("github", "github", "manage GitHub agent", {
			subcommands: [
				cmd("install", "github install", "install the GitHub agent"),
				cmd("run", "github run", "run the GitHub agent", {
					options: [
						opt("event", "GitHub mock event to run the agent for", true),
						opt("token", "GitHub personal access token (github_pat_********)", true),
					]
				}),
			]
		}),
		cmd("pr", "pr <number>", "fetch and checkout a GitHub PR branch, then run opencode", {
			options: [arg("number", "PR number to checkout")]
		}),
		cmd("session", "session", "manage sessions", {
			subcommands: [
				cmd("delete", "session delete <sessionID>", "delete a session", {options: [arg("sessionID", "session ID to delete")]}),
				cmd("list", "session list", "list sessions", {
					options: [
						opt("max-count", "limit to N most recent sessions", true, ["n"]),
						opt("format", "output format", true),
					]
				}),
			]
		}),
		cmd("plugin", "plugin <module>", "install plugin and update config", {
			aliases: ["plug"],
			options: [
				arg("module", "npm module name"),
				opt("global", "install in global config", false, ["g"]),
				opt("force", "replace existing plugin version", false, ["f"]),
			]
		}),
		cmd("db", "db", "database tools", {
			subcommands: [
				cmd("query", "db [query]", "open an interactive sqlite3 shell or run a query", {
					visible: false,
					options: [arg("query", "SQL query to execute"), opt("format", "Output format", true)]
				}),
				cmd("path", "db path", "print the database path"),
				cmd("migrate", "db migrate", "migrate JSON data to SQLite (merges with existing data)"),
			]
		}),
		cmd("completion", "completion", "generate shell completion script"),
	];

	public static function topHelp():String {
		final lines = [
			"opencodehx " + BuildInfo.version,
			"",
			"Usage:",
			"  opencodehx [command]",
			"",
			"Commands:",
		];
		for (command in COMMANDS) {
			if (!command.visible)
				continue;
			lines.push("  " + pad(command.name, 12) + command.description);
		}
		lines.push("");
		lines.push("Options:");
		lines.push("  -h, --help       show help");
		lines.push("  -v, --version    show version number");
		lines.push("  --print-logs     print logs to stderr");
		lines.push("  --log-level      log level: DEBUG, INFO, WARN, ERROR");
		lines.push("  --pure           run without external plugins");
		return lines.join("\n");
	}

	public static function find(args:Array<String>):Null<CliSurfaceMatch> {
		if (args.length == 0)
			return null;
		final first = args[0];
		final top = findIn(COMMANDS, first);
		if (top == null)
			return null;
		final path = [top.name];
		var command = top;
		var i = 1;
		while (i < args.length) {
			final token = args[i];
			if (StringTools.startsWith(token, "-"))
				break;
			final child = findIn(command.subcommands, token);
			if (child == null)
				break;
			command = child;
			path.push(command.name);
			i++;
		}
		return {command: command, path: path};
	}

	public static function help(match:CliSurfaceMatch):String {
		final command = match.command;
		final lines = ["opencodehx " + command.usage, "", command.description,];
		if (command.aliases.length > 0) {
			lines.push("");
			lines.push("Aliases: " + command.aliases.join(", "));
		}
		if (command.subcommands.length > 0) {
			lines.push("");
			lines.push("Commands:");
			for (child in command.subcommands) {
				if (!child.visible)
					continue;
				lines.push("  " + pad(child.name, 16) + child.description);
			}
		}
		if (command.options.length > 0) {
			lines.push("");
			lines.push("Options:");
			for (option in command.options)
				lines.push("  " + pad(optionLabel(option), 28) + option.description);
		}
		return lines.join("\n");
	}

	public static function notImplemented(match:CliSurfaceMatch):String {
		return 'Command not implemented yet: ${match.path.join(" ")}\n\n${help(match)}';
	}

	static function findIn(commands:Array<CliCommandInfo>, token:String):Null<CliCommandInfo> {
		for (command in commands) {
			if (command.name == token || command.aliases.indexOf(token) != -1)
				return command;
		}
		return null;
	}

	static function optionLabel(option:CliOptionInfo):String {
		if (option.positional)
			return "<" + option.name + ">";
		final labels = [];
		for (alias in option.aliases) {
			labels.push("-" + alias);
		}
		final value = option.value ? " <value>" : "";
		labels.push("--" + option.name + value);
		return labels.join(", ");
	}

	static function pad(value:String, width:Int):String {
		if (value.length >= width)
			return value + "  ";
		var result = value;
		while (result.length < width)
			result += " ";
		return result;
	}

	static function arg(name:String, description:String):CliOptionInfo {
		return {
			name: name,
			aliases: [],
			value: true,
			positional: true,
			description: description
		};
	}

	static function opt(name:String, description:String, value:Bool, ?aliases:Array<String>):CliOptionInfo {
		return {
			name: name,
			aliases: aliases == null ? [] : aliases,
			value: value,
			positional: false,
			description: description
		};
	}

	static function cmd(name:String, usage:String, description:String, ?spec:{
		?aliases:Array<String>,
		?options:Array<CliOptionInfo>,
		?subcommands:Array<CliCommandInfo>,
		?implemented:Bool,
		?visible:Bool,
	}):CliCommandInfo {
		return {
			name: name,
			usage: usage,
			description: description,
			aliases: spec == null || spec.aliases == null ? [] : spec.aliases,
			options: spec == null || spec.options == null ? [] : spec.options,
			subcommands: spec == null || spec.subcommands == null ? [] : spec.subcommands,
			implemented: spec != null && spec.implemented == true,
			visible: spec == null || spec.visible != false,
		};
	}
}
