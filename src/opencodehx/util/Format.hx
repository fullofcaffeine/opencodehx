package opencodehx.util;

class Format {
	public static function formatDuration(secs:Int):String {
		if (secs <= 0)
			return "";
		if (secs < 60)
			return '${secs}s';
		if (secs < 3600) {
			final mins = Math.floor(secs / 60);
			final remaining = secs % 60;
			return remaining > 0 ? '${mins}m ${remaining}s' : '${mins}m';
		}
		if (secs < 86400) {
			final hours = Math.floor(secs / 3600);
			final remaining = Math.floor((secs % 3600) / 60);
			return remaining > 0 ? '${hours}h ${remaining}m' : '${hours}h';
		}
		if (secs < 604800) {
			final days = Math.floor(secs / 86400);
			return days == 1 ? "~1 day" : '~${days} days';
		}
		final weeks = Math.floor(secs / 604800);
		return weeks == 1 ? "~1 week" : '~${weeks} weeks';
	}
}
