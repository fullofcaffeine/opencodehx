package opencodehx.externs.aws;

import genes.ts.Unknown;
import genes.ts.Undefinable;

/**
 * Opaque AWS credential provider accepted by the Bedrock AI SDK.
 *
 * The function shape is package-owned and we never inspect credentials in Haxe;
 * using the exact TS field type avoids leaking nullable Haxe optional fields
 * into a security-sensitive auth boundary.
 */
@:ts.type("NonNullable<import('@ai-sdk/amazon-bedrock').AmazonBedrockProviderSettings['credentialProvider']>")
abstract AwsCredentialProvider(Unknown) from Unknown to Unknown {}

typedef AwsNodeProviderChainOptions = {
	final profile:Undefinable<String>;
}

typedef AwsNodeProviderChainFactory = AwsNodeProviderChainOptions->AwsCredentialProvider;
