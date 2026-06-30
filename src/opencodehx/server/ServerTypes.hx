package opencodehx.server;

import js.lib.Promise;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.sync.SyncRouteRuntime;

typedef ServerLiveAiSdkOptions = {
	final provider:ProviderInfo;
	final model:ProviderModel;
	final language:AiLanguageModel;
	@:optional final agent:String;
	@:optional final system:Array<String>;
}

typedef ServerLiveConfigOptions = {
	final enabled:Bool;
}

typedef ServerOptions = {
	final directory:String;
	final dbPath:String;
	@:optional final hostname:String;
	@:optional final syncTypes:Array<String>;
	@:optional final syncRuntime:SyncRouteRuntime;
	@:optional final liveAiSdk:ServerLiveAiSdkOptions;
	@:optional final liveConfig:ServerLiveConfigOptions;
}

typedef ServerListener = {
	final port:Int;
	final hostname:String;
	final url:String;
	final stop:(?close:Bool) -> Promise<Void>;
}
