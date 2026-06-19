package opencodehx.tui;

enum TuiRoute {
	Home;
	Session(sessionID:String);
	Plugin(name:String);
}

typedef TuiPluginRoute = {
	final name:String;
	final label:String;
}

class TuiRouteStore {
	var currentRoute:TuiRoute;
	final pluginRoutes:Array<TuiPluginRoute>;

	public function new(initial:TuiRoute) {
		currentRoute = initial;
		pluginRoutes = [];
	}

	public static function demo():TuiRouteStore {
		final store = new TuiRouteStore(Home);
		store.register([{name: "themes", label: "Theme List"}]);
		return store;
	}

	public function current():TuiRoute {
		return currentRoute;
	}

	public function navigate(route:TuiRoute):Void {
		currentRoute = route;
	}

	public function register(routes:Array<TuiPluginRoute>):Void {
		for (route in routes)
			pluginRoutes.push(route);
	}

	public function currentName():String {
		return switch currentRoute {
			case Home:
				"home";
			case Session(_):
				"session";
			case Plugin(name):
				name;
		}
	}

	public function currentLabel():String {
		return switch currentRoute {
			case Home:
				"Home";
			case Session(sessionID):
				'Session ${sessionID}';
			case Plugin(name):
				pluginLabel(name);
		}
	}

	public function pluginLabel(name:String):String {
		for (i in 0...pluginRoutes.length) {
			final route = pluginRoutes[pluginRoutes.length - 1 - i];
			if (route.name == name)
				return route.label;
		}
		return 'Missing route ${name}';
	}
}
