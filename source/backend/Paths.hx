package backend;

import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;
import flixel.system.FlxAssets;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.geom.Rectangle;

import lime.utils.Assets;
import flash.media.Sound;

import haxe.Json;


#if MODS_ALLOWED
import backend.Mods;
#end

@:access(openfl.display.BitmapData)
class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	public static function excludeAsset(key:String) {
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static var dumpExclusions:Array<String> = ['assets/shared/music/freakyMenu.$SOUND_EXT'];

	private static var secondLayerTrackedAssets:Map<String, FlxGraphic> = new Map();
	private static var secondLayerTrackedSounds:Map<String, Sound> = new Map();
	private static var secondLayerTrackedCharacterData:Map<String, Dynamic> = new Map();
	private static var secondLayerPendingAtlasText:Map<String, String> = new Map();
	private static var cacheSignalsInitialized:Bool = false;

	public static function initCacheSignals():Void
	{
		if (cacheSignalsInitialized) return;
		FlxG.signals.preStateSwitch.add(moveTrackedAssetsToSecondLayer);
		FlxG.signals.postStateSwitch.add(onPostStateSwitch);
		cacheSignalsInitialized = true;
	}

	static function onPostStateSwitch():Void
		clearSecondLayerMemory();

	public static function moveTrackedAssetsToSecondLayer():Void
	{
		clearSecondLayerMemory(false);

		secondLayerTrackedAssets = currentTrackedAssets;
		secondLayerTrackedSounds = currentTrackedSounds;
		secondLayerTrackedCharacterData = currentTrackedCharacterData;
		secondLayerPendingAtlasText = pendingAtlasText;

		currentTrackedAssets = new Map();
		currentTrackedSounds = new Map();
		currentTrackedFrames = new Map();
		currentTrackedCharacterData = new Map();
		pendingAtlasText = new Map();
		localTrackedAssets = [];
		clearPathCaches(false);
	}

	public static function clearSecondLayerMemory(?runGC:Bool = true):Void
	{
		var clearedAny:Bool = false;
		for (key in secondLayerTrackedAssets.keys())
		{
			if (currentTrackedAssets.exists(key)) continue;

			var graphic:FlxGraphic = secondLayerTrackedAssets.get(key);
			if (dumpExclusions.contains(key))
			{
				currentTrackedAssets.set(key, graphic);
				continue;
			}
			destroyGraphic(graphic);
			clearedAny = true;
		}

		for (key => asset in secondLayerTrackedSounds)
		{
			if (currentTrackedSounds.exists(key)) continue;

			if (dumpExclusions.contains(key))
			{
				currentTrackedSounds.set(key, asset);
				continue;
			}
			Assets.cache.clear(key);
			clearedAny = true;
		}

		secondLayerTrackedAssets = new Map();
		secondLayerTrackedSounds = new Map();
		secondLayerTrackedCharacterData = new Map();
		secondLayerPendingAtlasText = new Map();

		if (runGC && clearedAny)
		{
			MemoryUtil.clearOpenFLUInt8Pools();
			MemoryUtil.clearMajor();
		}
	}

	inline static function trackLocalAsset(key:String):Void
	{
		if (!localTrackedAssets.contains(key))
			localTrackedAssets.push(key);
	}

	inline public static function markTrackedAsset(key:String):Void
		trackLocalAsset(key);

	public static function getTrackedGraphic(key:String):FlxGraphic
	{
		if (currentTrackedAssets.exists(key))
		{
			var graphic:FlxGraphic = currentTrackedAssets.get(key);
			trackLocalAsset(key);
			cacheGraphicOnState(graphic);
			return graphic;
		}

		return restoreSecondLayerGraphic(key);
	}

	public static function getTrackedSound(file:String):Sound
	{
		if (currentTrackedSounds.exists(file))
		{
			trackLocalAsset(file);
			return currentTrackedSounds.get(file);
		}

		if(secondLayerTrackedSounds.exists(file))
		{
			var sound:Sound = secondLayerTrackedSounds.get(file);
			secondLayerTrackedSounds.remove(file);
			currentTrackedSounds.set(file, sound);
			trackLocalAsset(file);
			return sound;
		}

		return null;
	}

	static function restoreSecondLayerGraphic(key:String):FlxGraphic
	{
		var graphic:FlxGraphic = secondLayerTrackedAssets.get(key);
		if (graphic == null) return null;

		secondLayerTrackedAssets.remove(key);
		currentTrackedAssets.set(key, graphic);
		trackLocalAsset(key);

		if (secondLayerPendingAtlasText.exists(key))
		{
			pendingAtlasText.set(key, secondLayerPendingAtlasText.get(key));
			secondLayerPendingAtlasText.remove(key);
		}

		cacheGraphicOnState(graphic);
		return graphic;
	}

	public static function getTrackedCharacterData(path:String):Dynamic
	{
		var data:Dynamic = currentTrackedCharacterData.get(path);
		if (data != null) return data;

		data = secondLayerTrackedCharacterData.get(path);
		if (data != null)
		{
			secondLayerTrackedCharacterData.remove(path);
			currentTrackedCharacterData.set(path, data);
		}
		return data;
	}

	inline public static function setTrackedCharacterData(path:String, data:Dynamic):Void
		currentTrackedCharacterData.set(path, data);

	static function cacheGraphicOnState(graphic:FlxGraphic):Void
	{
		if (graphic == null || FlxG.state == null || !Std.isOfType(FlxG.state, MusicBeatState))
			return;
		cast(FlxG.state, MusicBeatState).graphicCache.cacheGraphic(graphic);
	}

	// haya I love you for the base cache dump I took to the max
	public static function clearUnusedMemory()
	{
		// Build a fast O(1) lookup set from localTrackedAssets array
		var localSet:Map<String, Bool> = new Map();
		for (k in localTrackedAssets) localSet.set(k, true);

		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!localSet.exists(key) && !dumpExclusions.contains(key))
			{
				destroyGraphic(currentTrackedAssets.get(key)); // get rid of the graphic
				currentTrackedAssets.remove(key); // and remove the key from local cache map
				currentTrackedFrames.remove(key); // also clear cached atlas frames for this key
			}
		}

		MemoryUtil.clearMinor();
	}

	// define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];

	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	public static function clearStoredMemory()
	{
		// clear anything not in the tracked assets list
		for (key in FlxG.bitmap._cache.keys())
		{
			if (!currentTrackedAssets.exists(key) && !secondLayerTrackedAssets.exists(key))
				destroyGraphic(FlxG.bitmap.get(key));
		}

		// Build a fast O(1) lookup set from localTrackedAssets array
		var localSet:Map<String, Bool> = new Map();
		for (k in localTrackedAssets) localSet.set(k, true);

		// clear all sounds that are cached
		for (key => asset in currentTrackedSounds)
		{
			if (!localSet.exists(key) && !dumpExclusions.contains(key) && asset != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}
		// flags everything to be cleared out next unused memory clear
		localTrackedAssets = [];
		currentTrackedFrames = new Map(); // clear atlas frames cache on state transition
		currentTrackedCharacterData = new Map();
		pendingAtlasText = new Map();
		clearPathCaches();
		#if !html5 openfl.Assets.cache.clear("songs"); #end
	}

	public static function freeGraphicsFromMemory()
	{
		var protectedGfx:Array<FlxGraphic> = [];
		function checkForGraphics(spr:Dynamic)
		{
			try
			{
				var grp:Array<Dynamic> = Reflect.getProperty(spr, 'members');
				if(grp != null)
				{
					//trace('is actually a group');
					for (member in grp)
					{
						checkForGraphics(member);
					}
					return;
				}
			}

			//trace('check...');
			try
			{
				var gfx:FlxGraphic = Reflect.getProperty(spr, 'graphic');
				if(gfx != null)
				{
					protectedGfx.push(gfx);
					//trace('gfx added to the list successfully!');
				}
			}
			//catch(haxe.Exception) {}
		}

		for (member in FlxG.state.members)
			checkForGraphics(member);

		if(FlxG.state.subState != null)
			for (member in FlxG.state.subState.members)
				checkForGraphics(member);

		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!dumpExclusions.contains(key))
			{
				var graphic:FlxGraphic = currentTrackedAssets.get(key);
				if(!protectedGfx.contains(graphic))
				{
					destroyGraphic(graphic); // get rid of the graphic
					currentTrackedAssets.remove(key); // and remove the key from local cache map
					currentTrackedFrames.remove(key); // also clear cached atlas frames
					//trace('deleted $key');
				}
			}
		}
	}

	inline static function destroyGraphic(graphic:FlxGraphic)
	{
		if (graphic == null) return;
		// free some gpu memory
		if (graphic != null && graphic.bitmap != null && graphic.bitmap.__texture != null)
			graphic.bitmap.__texture.dispose();
		FlxG.bitmap.remove(graphic);
	}

	static public var currentLevel:String;
	static public function setCurrentLevel(name:String) {
		currentLevel = name.toLowerCase();
		clearPathCaches(false);
	}

	private static var _pathCache:Map<String, String> = new Map();
	private static var _songPathCache:Map<String, String> = new Map();
	private static final _invalidChars = ~/[~&;:<>#\s]/g;
	private static final _hideChars = ~/[.,'"%?!]/g;

	public static function clearPathCaches(?includeSongPath:Bool = true):Void
	{
		_pathCache = new Map();
		if (includeSongPath)
			_songPathCache = new Map();
	}

	public static function getPath(file:String, ?type:AssetType = TEXT, ?parentfolder:String, ?modsAllowed:Bool = true):String
	{
		var cacheKey:String = '$file\x00${parentfolder ?? ""}\x00${modsAllowed ? 1 : 0}\x00${currentLevel ?? ""}';
		#if MODS_ALLOWED
		cacheKey += '\x00${Mods.currentModDirectory ?? ""}\x00${Mods.getGlobalMods().join("|")}';
		#end
		var cached:String = _pathCache.get(cacheKey);
		if (cached != null) return cached;

		#if MODS_ALLOWED
		if(modsAllowed)
		{
			// When parentfolder is set (e.g. 'shared'), try with it first (for cases where mods mirror the structure)
			if (parentfolder != null)
			{
				var modded:String = modFolders('$parentfolder/$file');
				if(FileSystem.exists(modded)) { _pathCache.set(cacheKey, modded); return modded; }
			}
			// Always try without parentfolder: mods store assets directly as 'images/...' not 'shared/images/...'
			var modded:String = modFolders(file);
			if(FileSystem.exists(modded)) { _pathCache.set(cacheKey, modded); return modded; }
		}
		#end

		var result:String;
		if (parentfolder != null)
			result = getFolderPath(file, parentfolder);
		else if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath = getFolderPath(file, currentLevel);
			result = OpenFlAssets.exists(levelPath, type) ? levelPath : getSharedPath(file);
		}
		else
			result = getSharedPath(file);

		_pathCache.set(cacheKey, result);
		return result;
	}

	inline static public function getFolderPath(file:String, folder = "shared")
		return 'assets/$folder/$file';

	inline public static function getSharedPath(file:String = '')
		return 'assets/shared/$file';

	inline static public function txt(key:String, ?folder:String)
		return getPath('data/$key.txt', TEXT, folder, true);

	inline static public function xml(key:String, ?folder:String)
		return getPath('data/$key.xml', TEXT, folder, true);

	inline static public function json(key:String, ?folder:String)
		return getPath('data/$key.json', TEXT, folder, true);

	inline static public function shaderFragment(key:String, ?folder:String)
		return getPath('shaders/$key.frag', TEXT, folder, true);

	inline static public function shaderVertex(key:String, ?folder:String)
		return getPath('shaders/$key.vert', TEXT, folder, true);

	inline static public function lua(key:String, ?folder:String)
		return getPath('$key.lua', TEXT, folder, true);

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if(FileSystem.exists(file)) return file;
		#end
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	inline static public function sound(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('sounds/$key', modsAllowed);

	inline static public function music(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('music/$key', modsAllowed);

	inline static public function inst(song:String, ?modsAllowed:Bool = true):Sound
		return returnSound('${formatToSongPath(song)}/Inst', 'songs', modsAllowed);

	inline static public function voices(song:String, postfix:String = null, ?modsAllowed:Bool = true):Sound
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		//trace('songKey test: $songKey');
		return returnSound(songKey, 'songs', modsAllowed, false);
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?modsAllowed:Bool = true)
		return sound(key + FlxG.random.int(min, max), modsAllowed);

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	public static var currentTrackedFrames:Map<String, FlxAtlasFrames> = new Map();
	public static var currentTrackedCharacterData:Map<String, Dynamic> = new Map();
	public static var pendingAtlasText:Map<String, String> = new Map();
	static function disposeUnusedBitmap(bitmap:BitmapData, ?cached:FlxGraphic):Void
	{
		if (bitmap == null || (cached != null && cached.bitmap == bitmap)) return;

		if (bitmap.__texture != null)
			bitmap.__texture.dispose();
		bitmap.dispose();
	}

	static public function image(key:String, ?parentFolderOrAllowGPU:Dynamic = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var parentFolder:String = null;
		if (Std.isOfType(parentFolderOrAllowGPU, Bool))
			allowGPU = cast parentFolderOrAllowGPU;
		else if (parentFolderOrAllowGPU != null)
			parentFolder = cast parentFolderOrAllowGPU;

		key = Language.getFileTranslation('images/$key') + '.png';
		var bitmap:BitmapData = null;
		var trackedGraphic:FlxGraphic = getTrackedGraphic(key);
		if (trackedGraphic != null)
			return trackedGraphic;

		return cacheBitmap(key, bitmap, parentFolder, allowGPU);
	}

	public static function cacheBitmap(key:String, ?bitmap:BitmapData, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var trackedGraphic:FlxGraphic = getTrackedGraphic(key);
		if (trackedGraphic != null)
		{
			disposeUnusedBitmap(bitmap, trackedGraphic);
			return trackedGraphic;
		}

		if (bitmap == null)
		{
			var file:String = getPath(key, IMAGE, parentFolder, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(file))
				bitmap = allowGPU && ClientPrefs.data.cacheOnGPU ? OptimizedBitmapData.fromFile(file) : BitmapData.fromFile(file);
			else #end if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);

			if (bitmap == null)
			{
				trace('Bitmap not found: $file | key: $key');
				return null;
			}
		}

		if (allowGPU && ClientPrefs.data.cacheOnGPU)
			pushBitmapToGPU(bitmap);

		var graph:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, key);
		graph.persist = true;
		graph.destroyOnNoUse = false;

		currentTrackedAssets.set(key, graph);
		trackLocalAsset(key);
		cacheGraphicOnState(graph);
		return graph;
	}

	static function pushBitmapToGPU(bitmap:BitmapData):Void
	{
		if (bitmap == null || bitmap.image == null || FlxG.stage == null || FlxG.stage.context3D == null)
			return;

		bitmap.lock();
		if (bitmap.__texture == null)
		{
			bitmap.image.premultiplied = true;
			bitmap.getTexture(FlxG.stage.context3D);
		}
		bitmap.getSurface();
		bitmap.readable = true;
		bitmap.image = null;
	}

	inline static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		var path:String = getPath(key, TEXT, null, !ignoreMods);
		#if sys
		return (FileSystem.exists(path)) ? File.getContent(path) : null;
		#else
		return (OpenFlAssets.exists(path, TEXT)) ? Assets.getText(path) : null;
		#end
	}

	inline static public function font(key:String)
	{
		var folderKey:String = Language.getFileTranslation('fonts/$key');
		#if MODS_ALLOWED
		var file:String = modFolders(folderKey);
		if(FileSystem.exists(file)) return file;
		#end
		return 'assets/$folderKey';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?parentFolder:String = null)
	{
		#if MODS_ALLOWED
		if(!ignoreMods)
		{
			var modKey:String = key;
			if(parentFolder == 'songs') modKey = 'songs/$key';

			for(mod in Mods.getGlobalMods())
				if (FileSystem.exists(mods('$mod/$modKey')))
					return true;

			if (FileSystem.exists(mods(Mods.currentModDirectory + '/' + modKey)) || FileSystem.exists(mods(modKey)))
				return true;
		}
		#end
		return (OpenFlAssets.exists(getPath(key, type, parentFolder, false)));
	}

	static public function getAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		if (imageLoaded == null) return null;

		var framesKey:String = imageLoaded.key;
		if (currentTrackedFrames.exists(framesKey))
			return currentTrackedFrames.get(framesKey);

		// Check if atlas text was pre-read by LoadingState background thread
		if (pendingAtlasText.exists(framesKey))
		{
			var text:String = pendingAtlasText.get(framesKey);
			pendingAtlasText.remove(framesKey);
			var result:FlxAtlasFrames = StringTools.ltrim(text).startsWith('<')
				? FlxAtlasFrames.fromSparrow(imageLoaded, text)
				: FlxAtlasFrames.fromTexturePackerJson(imageLoaded, text);
			if (result != null)
				currentTrackedFrames.set(framesKey, result);
			return result;
		}

		var useMod = false;
		var result:FlxAtlasFrames;

		var myXml:Dynamic = getPath('images/$key.xml', TEXT, parentFolder, true);
		if(OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end )
		{
			#if MODS_ALLOWED
			result = FlxAtlasFrames.fromSparrow(imageLoaded, (useMod ? File.getContent(myXml) : myXml));
			#else
			result = FlxAtlasFrames.fromSparrow(imageLoaded, myXml);
			#end
		}
		else
		{
			var myJson:Dynamic = getPath('images/$key.json', TEXT, parentFolder, true);
			if(OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end )
			{
				#if MODS_ALLOWED
				result = FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (useMod ? File.getContent(myJson) : myJson));
				#else
				result = FlxAtlasFrames.fromTexturePackerJson(imageLoaded, myJson);
				#end
			}
			else
				result = getPackerAtlas(key, parentFolder);
		}

		if (result != null)
			currentTrackedFrames.set(framesKey, result);
		return result;
	}
	
	static public function getMultiAtlas(keys:Array<String>, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		
		var parentFrames:FlxAtlasFrames = Paths.getAtlas(keys[0].trim());
		if(keys.length > 1)
		{
			var original:FlxAtlasFrames = parentFrames;
			parentFrames = new FlxAtlasFrames(parentFrames.parent);
			parentFrames.addAtlas(original, true);
			for (i in 1...keys.length)
			{
				var extraFrames:FlxAtlasFrames = Paths.getAtlas(keys[i].trim(), parentFolder, allowGPU);
				if(extraFrames != null)
					parentFrames.addAtlas(extraFrames, true);
			}
		}
		return parentFrames;
	}

	static public function getSparrowAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		if (imageLoaded == null) return null;

		var framesKey:String = imageLoaded.key;
		if (currentTrackedFrames.exists(framesKey))
			return currentTrackedFrames.get(framesKey);

		var result:FlxAtlasFrames;
		#if MODS_ALLOWED
		var xml:String = modsXml(key);
		if(FileSystem.exists(xml))
			result = FlxAtlasFrames.fromSparrow(imageLoaded, File.getContent(xml));
		else
			result = FlxAtlasFrames.fromSparrow(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.xml', TEXT, parentFolder));
		#else
		result = FlxAtlasFrames.fromSparrow(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.xml', TEXT, parentFolder));
		#end

		currentTrackedFrames.set(framesKey, result);
		return result;
	}

	static public function getPackerAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		if (imageLoaded == null) return null;

		var framesKey:String = imageLoaded.key;
		if (currentTrackedFrames.exists(framesKey))
			return currentTrackedFrames.get(framesKey);

		var result:FlxAtlasFrames;
		#if MODS_ALLOWED
		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt))
			result = FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, File.getContent(txt));
		else
			result = FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder));
		#else
		result = FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder));
		#end

		currentTrackedFrames.set(framesKey, result);
		return result;
	}

	static public function getAsepriteAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		if (imageLoaded == null) return null;

		var framesKey:String = imageLoaded.key;
		if (currentTrackedFrames.exists(framesKey))
			return currentTrackedFrames.get(framesKey);

		var result:FlxAtlasFrames;
		#if MODS_ALLOWED
		var json:String = modsImagesJson(key);
		if(FileSystem.exists(json))
			result = FlxAtlasFrames.fromTexturePackerJson(imageLoaded, File.getContent(json));
		else
			result = FlxAtlasFrames.fromTexturePackerJson(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.json', TEXT, parentFolder));
		#else
		result = FlxAtlasFrames.fromTexturePackerJson(imageLoaded, getPath(Language.getFileTranslation('images/$key') + '.json', TEXT, parentFolder));
		#end

		currentTrackedFrames.set(framesKey, result);
		return result;
	}

	static public function formatToSongPath(path:String):String {
		var cached:String = _songPathCache.get(path);
		if (cached != null) return cached;
		var result:String = _hideChars.replace(_invalidChars.replace(path, '-'), '').trim().toLowerCase();
		_songPathCache.set(path, result);
		return result;
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];
	public static function returnSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true)
	{
		var file:String = getPath(Language.getFileTranslation(key) + '.$SOUND_EXT', SOUND, path, modsAllowed);

		//trace('precaching sound: $file');
		var trackedSound:Sound = getTrackedSound(file);
		if(trackedSound != null)
			return trackedSound;

		if(!currentTrackedSounds.exists(file))
		{
			#if sys
			if(FileSystem.exists(file))
				currentTrackedSounds.set(file, Sound.fromFile(file));
			#else
			if(OpenFlAssets.exists(file, SOUND))
				currentTrackedSounds.set(file, OpenFlAssets.getSound(file));
			#end
			else if(beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		trackLocalAsset(file);
		return currentTrackedSounds.get(file);
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = '')
		return 'mods/' + key;

	inline static public function modsJson(key:String)
		return modFolders('data/' + key + '.json');

	inline static public function modsVideo(key:String)
		return modFolders('videos/' + key + '.' + VIDEO_EXT);

	inline static public function modsSounds(path:String, key:String)
		return modFolders(path + '/' + key + '.' + SOUND_EXT);

	inline static public function modsImages(key:String)
		return modFolders('images/' + key + '.png');

	inline static public function modsXml(key:String)
		return modFolders('images/' + key + '.xml');

	inline static public function modsTxt(key:String)
		return modFolders('images/' + key + '.txt');

	inline static public function modsImagesJson(key:String)
		return modFolders('images/' + key + '.json');

	static public function modFolders(key:String)
	{
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods(Mods.currentModDirectory + '/' + key);
			if(FileSystem.exists(fileToCheck))
				return fileToCheck;
		}

		for(mod in Mods.getGlobalMods())
		{
			var fileToCheck:String = mods(mod + '/' + key);
			if(FileSystem.exists(fileToCheck))
				return fileToCheck;
		}
		return 'mods/' + key;
	}
	#end

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, spriteJson:Dynamic = null, animationJson:Dynamic = null)
	{
		var changedAnimJson = false;
		var changedAtlasJson = false;
		var changedImage = false;
		
		if(spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if(animationJson != null) 
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		// is folder or image path
		if(Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = '$i';
				if(i == 0) st = '';

				if(!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if(spriteJson != null)
					{
						//trace('found Sprite Json');
						changedImage = true;
						changedAtlasJson = true;
						folderOrImg = image('$originalPath/spritemap$st');
						break;
					}
				}
				else if(fileExists('images/$originalPath/spritemap$st.png', IMAGE))
				{
					//trace('found Sprite PNG');
					changedImage = true;
					folderOrImg = image('$originalPath/spritemap$st');
					break;
				}
			}

			if(!changedImage)
			{
				//trace('Changing folderOrImg to FlxGraphic');
				changedImage = true;
				folderOrImg = image(originalPath);
			}

			if(!changedAnimJson)
			{
				//trace('found Animation Json');
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		//trace(folderOrImg);
		//trace(spriteJson);
		//trace(animationJson);
		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}
	#end
}
