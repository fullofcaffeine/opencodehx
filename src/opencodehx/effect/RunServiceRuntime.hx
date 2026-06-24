package opencodehx.effect;

class RunServiceRuntime<TService> {
	final factory:Void->TService;
	final services:Array<TService> = [];

	public function new(factory:Void->TService) {
		this.factory = factory;
	}

	public static function make<TService>(factory:Void->TService):RunServiceRuntime<TService> {
		return new RunServiceRuntime(factory);
	}

	public function run<TResult>(fn:TService->TResult):TResult {
		return fn(service());
	}

	function service():TService {
		if (services.length == 0)
			services.push(factory());
		return services[0];
	}
}
