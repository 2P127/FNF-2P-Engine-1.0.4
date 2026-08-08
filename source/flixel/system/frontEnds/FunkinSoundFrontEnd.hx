package flixel.system.frontEnds;

/**
 * Backports the perceptually even volume steps used by the FNF V-Slice engine
 * without requiring the project's HaxeFlixel version to be replaced.
 */
@:access(flixel.system.frontEnds.SoundFrontEnd)
class FunkinSoundFrontEnd extends SoundFrontEnd
{
	public function new()
	{
		super();
	}

	override public function changeVolume(amount:Float):Void
	{
		muted = false;
		volume = linearToLog(logToLinear(volume) + amount);
		showSoundTray(amount > 0);
	}

	public function linearToLog(value:Float, minValue:Float = 0.001):Float
	{
		if (value <= 0)
			return 0;

		value = Math.min(1, value);
		return Math.exp(Math.log(minValue) * (1 - value));
	}

	public function logToLinear(value:Float, minValue:Float = 0.001):Float
	{
		if (value <= 0)
			return 0;

		value = Math.min(1, value);
		return 1 - (Math.log(Math.max(value, minValue)) / Math.log(minValue));
	}
}
