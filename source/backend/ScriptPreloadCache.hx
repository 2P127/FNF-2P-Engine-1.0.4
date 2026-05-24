package backend;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.thread.Mutex;
#end

typedef ScriptPreloadEntry =
{
	var modified:Float;
	var content:String;
}

class ScriptPreloadCache
{
	#if sys
	static var fileCache:Map<String, ScriptPreloadEntry> = new Map();
	static var directoryCache:Map<String, Array<String>> = new Map();
	static var mutex:Mutex = new Mutex();
	#end

	public static function normalize(path:String):String
	{
		return path == null ? null : StringTools.replace(path, '\\', '/');
	}

	public static function clear():Void
	{
		#if sys
		mutex.acquire();
		fileCache = new Map();
		directoryCache = new Map();
		mutex.release();
		#end
	}

	public static function preloadDirectory(folder:String):Array<String>
	{
		#if sys
		folder = normalize(folder);
		if (folder == null || folder.length < 1 || !FileSystem.exists(folder) || !FileSystem.isDirectory(folder))
			return [];

		var cached:Array<String> = getDirectoryFiles(folder);
		if (cached != null)
			return cached;

		var files:Array<String> = [];
		try
		{
			files = FileSystem.readDirectory(folder);
		}
		catch(e:Dynamic)
		{
			return [];
		}

		mutex.acquire();
		directoryCache.set(folder, files.copy());
		mutex.release();
		return files;
		#else
		return [];
		#end
	}

	public static function getDirectoryFiles(folder:String):Array<String>
	{
		#if sys
		folder = normalize(folder);
		if (folder == null)
			return null;

		mutex.acquire();
		var files:Array<String> = directoryCache.get(folder);
		var copy:Array<String> = files != null ? files.copy() : null;
		mutex.release();
		return copy;
		#else
		return null;
		#end
	}

	public static function preloadFile(path:String):Bool
	{
		#if sys
		path = normalize(path);
		if (path == null || path.length < 1 || !FileSystem.exists(path) || FileSystem.isDirectory(path))
			return false;

		var modified:Float = getModifiedTime(path);
		mutex.acquire();
		var cached:ScriptPreloadEntry = fileCache.get(path);
		var fresh:Bool = cached != null && cached.modified == modified;
		mutex.release();
		if (fresh)
			return true;

		var content:String = null;
		try
		{
			content = File.getContent(path);
		}
		catch(e:Dynamic)
		{
			return false;
		}

		mutex.acquire();
		fileCache.set(path, {modified: modified, content: content});
		mutex.release();
		return true;
		#else
		return false;
		#end
	}

	public static function consumeText(path:String):String
	{
		#if sys
		path = normalize(path);
		if (path == null)
			return null;

		mutex.acquire();
		var cached:ScriptPreloadEntry = fileCache.get(path);
		mutex.release();
		if (cached == null)
			return null;

		if (!FileSystem.exists(path) || getModifiedTime(path) != cached.modified)
		{
			remove(path);
			return null;
		}

		remove(path);
		return cached.content;
		#else
		return null;
		#end
	}

	#if sys
	static function getModifiedTime(path:String):Float
	{
		try
			return FileSystem.stat(path).mtime.getTime()
		catch(e:Dynamic)
			return -1;
	}

	static function remove(path:String):Void
	{
		mutex.acquire();
		fileCache.remove(path);
		mutex.release();
	}
	#end
}
