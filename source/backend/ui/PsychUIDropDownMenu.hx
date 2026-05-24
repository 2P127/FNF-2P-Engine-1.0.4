package backend.ui;

import backend.ui.PsychUIBox.UIStyleData;

class PsychUIDropDownMenu extends PsychUIInputText
{
	public static final CLICK_EVENT = "dropdown_click";

	public var list(default, set):Array<String> = [];
	public var button:FlxSprite;
	public var onSelect:Int->String->Void;

	public var maxVisibleItems:Int = 12;

	public var selectedIndex(default, set):Int = -1;
	public var selectedLabel(default, set):String = null;

	var _curFilterIndices:Array<Int>;
	var _allIndices:Array<Int> = [];
	var _itemPool:Array<PsychUIDropDownItem> = [];
	var _itemWidth:Float = 0;
	public function new(x:Float, y:Float, initialList:Array<String>, callback:Int->String->Void, ?width:Float = 100)
	{
		super(x, y);
		if(initialList == null) initialList = [];

		_itemWidth = width - 2;
		setGraphicSize(width, 20);
		updateHitbox();
		textObj.y += 2;

		button = new FlxSprite(behindText.width + 1, 0).loadGraphic(Paths.image('psych-ui/dropdown_button', 'embed'), true, 20, 20);
		button.animation.add('normal', [0], false);
		button.animation.add('pressed', [1], false);
		button.animation.play('normal', true);
		add(button);

		initItemPool();

		onSelect = callback;

		onChange = function(old:String, cur:String)
		{
			if(old != cur)
			{
				var lowered = cur.toLowerCase();
				_curFilterIndices = [];
				for (i in 0...list.length)
					if(list[i].toLowerCase().indexOf(lowered) != -1)
						_curFilterIndices.push(i);
				showDropDown(true, 0, _curFilterIndices);
			}
		}
		unfocus = function()
		{
			showDropDownClickFix();
			showDropDown(false);
		}

		this.list = initialList;
		selectedIndex = (list.length > 0) ? 0 : -1;
		showDropDown(false);
	}

	function set_selectedIndex(v:Int)
	{
		selectedIndex = v;
		if(selectedIndex < 0 || selectedIndex >= list.length) selectedIndex = -1;

		if(selectedIndex >= 0)
		{
			@:bypassAccessor selectedLabel = list[selectedIndex];
			text = selectedLabel;
		}
		else
		{
			@:bypassAccessor selectedLabel = null;
			text = '';
		}
		return selectedIndex;
	}

	function set_selectedLabel(v:String)
	{
		var id:Int = list.indexOf(v);
		if(id >= 0)
		{
			@:bypassAccessor selectedIndex = id;
			selectedLabel = v;
			text = selectedLabel;
		}
		else
		{
			@:bypassAccessor selectedIndex = -1;
			selectedLabel = null;
			text = '';
		}
		return selectedLabel;
	}

	public var curScroll:Int = 0;
	override function update(elapsed:Float)
	{
		var lastFocus = PsychUIInputText.focusOn;
		super.update(elapsed);
		if(FlxG.mouse.justPressed)
		{
			if(FlxG.mouse.overlaps(button, camera))
			{
				button.animation.play('pressed', true);
				if(lastFocus != this)
					PsychUIInputText.focusOn = this;
				else if(PsychUIInputText.focusOn == this)
					PsychUIInputText.focusOn = null;
			}
		}
		else if(FlxG.mouse.released && button.animation.curAnim != null && button.animation.curAnim.name != 'normal') button.animation.play('normal', true);

		if(lastFocus != PsychUIInputText.focusOn)
		{
			showDropDown(PsychUIInputText.focusOn == this, curScroll, _curFilterIndices);
		}
		else if(PsychUIInputText.focusOn == this)
		{
			var wheel:Int = FlxG.mouse.wheel;
			if(FlxG.keys.pressed.UP) wheel++;
			if(FlxG.keys.pressed.DOWN) wheel--;
			if(wheel != 0) showDropDown(true, curScroll - wheel, _curFilterIndices);
		}
	}

	private function showDropDownClickFix()
	{
		if(FlxG.mouse.justPressed)
		{
			for (item in _itemPool) //extra update to fix a little bug where it wouldnt click on any option if another input text was behind the drop down
				if(item != null && item.active && item.visible)
					item.update(0);
		}
	}

	public function showDropDown(vis:Bool = true, scroll:Int = 0, onlyAllowed:Array<Int> = null)
	{
		if(!vis)
		{
			text = selectedLabel;
			_curFilterIndices = null;
			hideAllItems();
			return;
		}

		var source:Array<Int> = (onlyAllowed != null) ? onlyAllowed : (_curFilterIndices != null ? _curFilterIndices : _allIndices);
		if(source == null) source = [];

		var maxVisible:Int = Std.int(Math.max(1, maxVisibleItems));
		var total:Int = source.length;
		var poolCount:Int = _itemPool.length;
		var visibleCount:Int = Std.int(Math.min(poolCount, Math.min(maxVisible, total)));
		if(visibleCount <= 0)
		{
			hideAllItems();
			return;
		}

		curScroll = clampScroll(scroll, total, visibleCount);

		var txtY:Float = behindText.y + behindText.height + 1;
		for (i in 0...poolCount)
		{
			var item = _itemPool[i];
			if(i < visibleCount)
			{
				var actualIndex:Int = source[curScroll + i];
				var label:String = list[actualIndex];
				item.label = label;
				item.onClick = makeOnClick(actualIndex, label);
				item.visible = item.active = true;
				item.forceNextUpdate = true;
				item.x = behindText.x;
				item.y = txtY;
				txtY += item.height;
			}
			else item.active = item.visible = false;
		}

		bg.scale.y = txtY - behindText.y + 2;
		bg.updateHitbox();
	}

	public var broadcastDropDownEvent:Bool = true;
	function clickedOn(num:Int, label:String)
	{
		selectedIndex = num;
		showDropDown(false);
		if(onSelect != null) onSelect(num, label);
		if(broadcastDropDownEvent) PsychUIEventHandler.event(CLICK_EVENT, this);
	}

	function addOption(option:String)
	{
		@:bypassAccessor list.push(option);
		_allIndices.push(list.length - 1);
		if(PsychUIInputText.focusOn == this)
			showDropDown(true, curScroll, _curFilterIndices);
	}

	function set_list(v:Array<String>)
	{
		var selected:String = selectedLabel;
		showDropDown(false);

		@:bypassAccessor list = (v == null) ? [] : v;
		rebuildIndices();

		if(selectedLabel != null) selectedLabel = selected;
		else if(list.length > 0) selectedIndex = 0;
		else selectedIndex = -1;
		return list;
	}

	inline function clampScroll(scroll:Int, total:Int, visibleCount:Int):Int
	{
		var maxScroll = Math.max(0, total - visibleCount);
		return Std.int(Math.max(0, Math.min(maxScroll, scroll)));
	}

	inline function makeOnClick(idx:Int, label:String):Void->Void
	{
		return function() clickedOn(idx, label);
	}

	function hideAllItems():Void
	{
		for (item in _itemPool)
			item.active = item.visible = false;

		bg.scale.y = 20;
		bg.updateHitbox();
	}

	function initItemPool():Void
	{
		if(maxVisibleItems < 1) maxVisibleItems = 1;
		for (i in 0...maxVisibleItems)
		{
			var item = new PsychUIDropDownItem(1, 1, this._itemWidth);
			item.cameras = cameras;
			item.visible = item.active = false;
			item.forceNextUpdate = true;
			_itemPool.push(item);
			insert(1, item);
		}
	}

	function rebuildIndices():Void
	{
		_allIndices.resize(0);
		if(list != null)
			for (i in 0...list.length)
				_allIndices.push(i);
	}
}

class PsychUIDropDownItem extends FlxSpriteGroup
{
	public var hoverStyle:UIStyleData = {
		bgColor: 0xFF0066FF,
		textColor: FlxColor.WHITE,
		bgAlpha: 1
	};
	public var normalStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};

	public var bg:FlxSprite;
	public var text:FlxText;
	public function new(x:Float = 0, y:Float = 0, width:Float = 100)
	{
		super(x, y);

		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.setGraphicSize(width, 20);
		bg.updateHitbox();
		add(bg);

		text = new FlxText(0, 0, width, 8);
		text.color = FlxColor.BLACK;
		add(text);
	}

	public var onClick:Void->Void;
	public var forceNextUpdate:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if(FlxG.mouse.justMoved || FlxG.mouse.justPressed || forceNextUpdate)
		{
			var overlapped:Bool = (FlxG.mouse.overlaps(bg, camera));

			var style = overlapped ? hoverStyle : normalStyle;
			bg.color = style.bgColor;
			text.color = style.textColor;
			bg.alpha = style.bgAlpha;
			forceNextUpdate = false;

			if(overlapped && FlxG.mouse.justPressed)
				onClick();
		}
		
		text.x = bg.x;
		text.y = bg.y + bg.height/2 - text.height/2;
	}

	public var label(default, set):String;
	function set_label(v:String)
	{
		label = v;
		text.text = v;
		bg.scale.y = text.height + 6;
		bg.updateHitbox();
		return v;
	}
}