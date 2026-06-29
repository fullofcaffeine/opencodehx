package opencodehx.util;

using StringTools;

/**
	Attachment media helpers shared by tools that need upstream-compatible
	classification without exposing raw MIME/string checks at each call site.
**/
function isPdfAttachment(mime:String):Bool {
	return mime == "application/pdf";
}

function isImageAttachment(mime:String):Bool {
	return mime.startsWith("image/") && mime != "image/svg+xml" && mime != "image/vnd.fastbidsheet";
}

function isAttachmentMedia(mime:String):Bool {
	return isImageAttachment(mime) || isPdfAttachment(mime);
}

function sniffAttachmentMime(bytes:Array<Int>, fallback:String):String {
	if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
		return "image/png";
	if (startsWith(bytes, [0xff, 0xd8, 0xff]))
		return "image/jpeg";
	if (startsWith(bytes, [0x47, 0x49, 0x46, 0x38]))
		return "image/gif";
	if (startsWith(bytes, [0x42, 0x4d]))
		return "image/bmp";
	if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d]))
		return "application/pdf";
	if (startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWithAt(bytes, 8, [0x57, 0x45, 0x42, 0x50]))
		return "image/webp";
	return fallback;
}

function contentTypeMime(contentType:Null<String>, fallback:String):String {
	if (contentType == null || contentType == "")
		return fallback;
	return contentType.split(";")[0].toLowerCase();
}

function startsWith(bytes:Array<Int>, prefix:Array<Int>):Bool {
	return startsWithAt(bytes, 0, prefix);
}

function startsWithAt(bytes:Array<Int>, offset:Int, prefix:Array<Int>):Bool {
	if (bytes.length < offset + prefix.length)
		return false;
	for (index in 0...prefix.length) {
		if (bytes[offset + index] != prefix[index])
			return false;
	}
	return true;
}
