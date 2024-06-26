package globals;

import openfl.events.Event;
import base.*;
import base.Overlay.Console;
import base.dependency.Discord;
import base.utils.FNFUtils.FNFGame;
import base.utils.FNFUtils.FNFTransition;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.FlxGraphic;
import flixel.tweens.*;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import lime.graphics.Image.fromFile;
import haxe.CallStack;
import haxe.Json;
import haxe.io.Path;
import lime.app.Application;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.UncaughtErrorEvent;
import openfl.system.System;
import openfl.utils.AssetCache;
import states.MusicBeatState;
import states.ScriptableState;
import states.ScriptableState.ScriptableSubstate;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
#if cpp
import cpp.NativeGc;
import cpp.vm.Gc;
#elseif hl
import hl.Gc;
#elseif java
import java.vm.Gc;
#elseif neko
import neko.vm.Gc;
#end

typedef GameWeek =
{
	var songs:Array<WeekSong>;
	var characters:Array<String>;
	@:optional var difficulties:Array<String>; // wip
	var attachedImage:String;
	var storyName:String;
	var startsLocked:Bool;
	var hideOnStory:Bool;
	var hideOnFreeplay:Bool;
	var hideUntilUnlocked:Bool;
}

typedef WeekSong =
{
	var name:String;
	var opponent:String;
	var ?player:String; // wanna do something with this later haha;
	var colors:Array<Int>;
}

// Here we actually import the states and metadata, and just the metadata.
// It's nice to have modularity so that we don't have ALL elements loaded at the same time.
// at least that's how I think it works. I could be stupid!
class Main extends Sprite
{
	public static var game = {
		width: 1280, // game window width
		height: 720, // game window height
		zoom: -1.0, // defines the game's state bounds, -1.0 usually means automatic setup
		initialState: states.TitleState, // state the game should start at
		framerate: 60, // the game's default framerate
		skipSplash: true, // whether to skip the flixel splash screen that appears on release mode
		fullscreen: false, // whether the game starts at fullscreen mode
		version: "0.2.1", // version of the engine
	};

	public static var baseGame:FNFGame;

	// i really need this
	public static var globalElapsed(default, set):Float = 0;

	/**
	 * The desing width of this game. You will use either this or the design heigh
	 */
	private static inline var DESIGN_WIDTH:Int = 1280;

	/**
	 * The desing height of this game. You will use either this or the design width
	 */
	private static inline var DESIGN_HEIGHT:Int = 720;

	private static var infoCounter:Overlay; // initialize the heads up display that shows information before creating it.
	private static var infoConsole:Console; // intiialize the on-screen console for script debug traces before creating it.

	var oldVol:Float = 1.0;
	var newVol:Float = 0.3;

	public static var focused:Bool = true;

	public static var focusMusicTween:FlxTween;

	// weeks set up!
	public static var weeksMap:Map<String, GameWeek> = [];
	public static var weeks:Array<String> = [];

	/* public static function loadHardcodedWeeks()
		{
			weeksMap = [
				"myWeek" => {
					songs: [
						{
							"name": "Bopeebo",
							"opponent": "dad",
							"colors": [129, 100, 223]
						}
					],

					attachedImage: "week1",
					storyName: "vs. DADDY DEAREST",
					characters: ["dad", "bf", "gf"],

					startsLocked: false,
					hideOnStory: false,
					hideOnFreeplay: false,
					hideUntilUnlocked: false
				}
			];
			gameWeeks.push('myWeek');
	}*/
	public static function loadGameWeeks(isStory:Bool)
	{
		weeksMap.clear();
		weeks = [];

		// loadHardcodedWeeks();

		var weekList:Array<String> = CoolUtil.coolTextFile(Paths.txt('data/weekList'));
		for (i in 0...weekList.length)
		{
			if (!weeksMap.exists(weekList[i]))
			{
				if (weekList[i].length > 1)
				{
					var week:GameWeek = parseGameWeeks(Paths.file('data/weeks/' + weekList[i] + '.json'));
					if (week != null)
					{
						if ((isStory && (!week.hideOnStory && !week.hideUntilUnlocked))
							|| (!isStory && (!week.hideOnFreeplay && !week.hideUntilUnlocked)))
						{
							weeksMap.set(weekList[i], week);
							weeks.push(weekList[i]);
						}
					}
				}
				else
					weeks = null;
			}
		}
	}

	public static function parseGameWeeks(path:String):GameWeek
	{
		var rawJson:String = null;

		if (FileSystem.exists(path))
			rawJson = File.getContent(path);

		return Json.parse(rawJson);
	}

	public static function set_globalElapsed(value:Float):Float
	{
		return globalElapsed = value;
	}

	// most of these variables are just from the base game!
	// be sure to mess around with these if you'd like.

	public static function main():Void
		Lib.current.addChild(new Main());

	public function new()
	{
		super();

		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	function setupGame()
	{
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);

		#if desktop
		Gc.enable(true);
		#end

		#if linux
		var icon = fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		/**
		 * locking neko platforms on 60 because similar to html5 it cannot go over that
		 * avoids note stutters and stuff
		**/
		#if neko
		framerate = 60;
		#end

		// define the state bounds
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}

		FlxTransitionableState.skipNextTransIn = true;

		// here we set up the base game
		baseGame = new FNFGame(game.width, game.height, Init, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.fullscreen);
		addChild(baseGame); // and create it afterwards
		FlxGraphic.defaultPersist = false;

		FlxG.signals.gameResized.add(onResizeGame);

		FlxGraphic.defaultPersist = false;

		// initialize the game controls;
		Controls.init();

		// begin the discord rich presence
		#if DISCORD_RPC
		Discord.initializeRPC();
		Discord.changePresence('');
		#end

		#if !mobile
		infoCounter = new Overlay(0, 0);
		addChild(infoCounter);
		#end

		#if SHOW_CONSOLE
		infoConsole = new Console();
		addChild(infoConsole);
		#end

		FlxG.stage.application.window.onClose.add(function()
		{
			destroyGame();
		});

		Application.current.window.onFocusOut.add(onWindowFocusOut);
		Application.current.window.onFocusIn.add(onWindowFocusIn);
	}

	function destroyGame()
	{
		base.Controls.destroy();
		#if DISCORD_RPC
		Discord.shutdownRPC();
		#end
		Sys.exit(1);
	}

	public static function framerateAdjust(input:Float)
	{
		return input * (60 / FlxG.drawFramerate);
	}

	/*  This is used to switch "rooms," to put it basically. Imagine you are in the main menu, and press the freeplay button.
		That would change the game's main class to freeplay, as it is the active class at the moment.
	 */
	public static var lastState:FlxState;

	public static function switchState(curState:FlxState, target:FlxState)
	{
		// Custom made Trans in
		if (!FlxTransitionableState.skipNextTransIn)
		{
			curState.openSubState(new FNFTransition(0.35, false));
			FNFTransition.finishCallback = function()
			{
				FlxG.switchState(target);
			};
			return;
		}
		FlxTransitionableState.skipNextTransIn = false;
		FlxTransitionableState.skipNextTransOut = false;
		// load the state
		FlxG.switchState(target);
	}

	public static function crashSwitchState(curState:FlxState, target:FlxState)
	{
		FlxG.switchState(target);
	}

	public static function updateFramerate(newFramerate:Int)
	{
		// flixel will literally throw errors at me if I dont separate the orders
		if (newFramerate > FlxG.updateFramerate)
		{
			FlxG.updateFramerate = newFramerate;
			FlxG.drawFramerate = newFramerate;
		}
		else
		{
			FlxG.drawFramerate = newFramerate;
			FlxG.updateFramerate = newFramerate;
		}
	}

	/*
	 * Haha, funi Indie Cross Code
	 * Updates music volume if autopause is disabled in your settings
	 */
	function onWindowFocusOut()
	{
		focused = false;

		// Lower global volume when unfocused
		oldVol = FlxG.sound.volume;
		if (oldVol > 0.3)
		{
			newVol = 0.3;
		}
		else
		{
			if (oldVol > 0.1)
			{
				newVol = 0.1;
			}
			else
			{
				newVol = 0;
			}
		}

		if (focusMusicTween != null)
			focusMusicTween.cancel();
		focusMusicTween = FlxTween.tween(FlxG.sound, {volume: newVol}, 0.5);

		// Conserve power by lowering draw framerate when unfocuced
		FlxG.drawFramerate = 60;
		FlxG.updateFramerate = 60;
	}

	function onWindowFocusIn()
	{
		new FlxTimer().start(0.2, function(tmr:FlxTimer)
		{
			focused = true;
		});

		// Lower global volume when unfocused
		// Normal global volume when focused
		if (focusMusicTween != null)
			focusMusicTween.cancel();

		focusMusicTween = FlxTween.tween(FlxG.sound, {volume: oldVol}, 0.5);

		Main.updateFramerate(Init.trueSettings.get("Framerate Cap"));
	}

	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var errMsgPrint:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = StringTools.replace(dateNow, " ", "_");
		dateNow = StringTools.replace(dateNow, ":", "'");

		path = "crash/" + "Spectra_" + dateNow + ".txt";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
					errMsgPrint += file + ":" + line + "\n"; // if you Ctrl+Mouse Click its go to the line.
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: " + e.error + " - Please report this error to the\nGitHub page https://github.com/DEMOLITIONDON96/Spectra-Engine";

		if (!FileSystem.exists("crash/"))
			FileSystem.createDirectory("crash/");

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsgPrint);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		var crashDialoguePath:String = "SE-CrashHandler";

		#if windows
		crashDialoguePath += ".exe";
		#end

		if (FileSystem.exists(crashDialoguePath))
		{
			Sys.println("Found crash dialog: " + crashDialoguePath);
			new Process(crashDialoguePath, [path]);
		}
		else
		{
			Sys.println("No crash dialog found! Making a simple alert instead...");
			Application.current.window.alert(errMsg, "Error!");
		}

		destroyGame();
	}

	// i fucking hate this bullshit it sucks ass but it rarely works :sob:
	public static function optimizeGame(post:Bool = false)
	{
		if (!post)
		{
			Paths.clearStoredMemory(true);
			Paths.clearUnusedMemory();
			FlxG.bitmap.dumpCache();

			gc();

			var cache = cast(Assets.cache, AssetCache);
			for (key => font in cache.font)
			{
				cache.removeFont(key);
				trace('removed font $key');
			}
			for (key => sound in cache.sound)
			{
				cache.removeSound(key);
				trace('removed sound $key');
			}
			cache = null; // nulling the cache moment
		}
		else
		{
			Paths.clearUnusedMemory();
			openfl.Assets.cache.clear('assets/songs');
			openfl.Assets.cache.clear('assets/data');
			openfl.Assets.cache.clear('assets/shaders');
			openfl.Assets.cache.clear('assets/fonts');
			openfl.Assets.cache.clear('assets/images');
			openfl.Assets.cache.clear('assets/music');
			openfl.Assets.cache.clear('assets/videos');
			gc();
			trace(Math.abs(System.totalMemory / 1000000));
		}
	}

	function onResizeGame(w:Int, h:Int)
	{
		if (FlxG.cameras == null)
			return;

		for (cam in FlxG.cameras.list)
		{
			@:privateAccess
			if (cam != null && (cam.filters != null || cam.filters != []))
				fixShaderSize(cam);
		}
	}

	function fixShaderSize(camera:flixel.FlxCamera)
	{
		@:privateAccess {
			var sprite:Sprite = camera.flashSprite;

			if (sprite != null)
			{
				sprite.__cacheBitmap = null;
				sprite.__cacheBitmapData = null;
				sprite.__cacheBitmapData2 = null;
				sprite.__cacheBitmapData3 = null;
				sprite.__cacheBitmapColorTransform = null;
			}
		}
	}

	public static function gc()
	{
		trace("Huh");

		#if cpp
		NativeGc.compact();
		NativeGc.run(true);
		#elseif hl
		Gc.major();
		#elseif (java || neko)
		Gc.run(true);
		#else
		openfl.system.System.gc();
		#end
	}
}
