package opencodehx.provider;

import haxe.Exception;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;

enum ProviderFailure {
	ModelNotFound(providerID:ProviderID, modelID:ModelID, suggestions:Array<String>);
	NoProviders;
}

class ProviderException extends Exception {
	public final failure:ProviderFailure;

	public function new(failure:ProviderFailure) {
		this.failure = failure;
		super(messageFor(failure));
	}

	static function messageFor(failure:ProviderFailure):String {
		return switch failure {
			case ModelNotFound(providerID, modelID, suggestions):
				final suffix = suggestions.length == 0 ? "" : " suggestions: " + suggestions.join(", ");
				'Provider model not found: ${providerID.toString()}/${modelID.toString()}${suffix}';
			case NoProviders:
				"no providers found";
		}
	}
}
