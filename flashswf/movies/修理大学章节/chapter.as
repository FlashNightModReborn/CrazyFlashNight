stop();
// Data-driven chapter presentation. Game classes and the input gate remain in asLoader.
var chapter:Object = _root.书中当前章节;
if (chapter == null || _root._saveExt.bookRun == null || chapter.slot !== String(_root.savePath)
        || chapter.owner !== _root.gameworld.__stageReturnWorldIdentity
        || typeof _root.书中过场取得暂停 != "function") {
    this.unloadMovie();
} else {
var ownerSlot:String = String(_root.savePath);
var ownerWorld:Object = _root.gameworld.__stageReturnWorldIdentity;
var pauseLease:String = _root.书中过场取得暂停();
var ended:Boolean = false;
var began:Number = getTimer();
var lines:Array = chapter.dialogue instanceof Array ? chapter.dialogue : [];
var cursor:Number = -1;
this.createEmptyMovieClip("veil", 1);
veil.beginFill(0x0c1310, 95); veil.moveTo(0,0); veil.lineTo(1024,0);
veil.lineTo(1024,576); veil.lineTo(0,576); veil.lineTo(0,0); veil.endFill();
this.createTextField("chapterNumber", 2, 120, 183, 784, 40);
this.createTextField("chapterTitle", 3, 100, 242, 824, 90);
this.createTextField("hint", 4, 100, 410, 824, 35);
var small:TextFormat = new TextFormat("_sans", 18, 0xb8b68c); small.align = "center";
var large:TextFormat = new TextFormat("_sans", 43, 0xeee5c8); large.align = "center";
chapterNumber.text = "修理大学  /  " + String(chapter.index + 1) + " · " + String(chapter.total);
chapterTitle.text = String(chapter.title);
hint.text = lines.length > 0 ? "点击继续 · 台词可逐句阅读" : "点击继续";
this.createTextField("speaker", 5, 112, 305, 800, 32);
this.createTextField("speech", 6, 112, 350, 800, 136);
speech.multiline = true; speech.wordWrap = true;
var speakerFormat:TextFormat = new TextFormat("_sans", 20, 0xd8c18b, true);
var speechFormat:TextFormat = new TextFormat("_sans", 23, 0xeee5c8);
speechFormat.leading = 9;
speaker.setNewTextFormat(speakerFormat); speech.setNewTextFormat(speechFormat);
speaker.selectable = speech.selectable = false;
this.createEmptyMovieClip("skipButton", 7);
skipButton.beginFill(0x303831, 100); skipButton.moveTo(850, 26); skipButton.lineTo(990, 26);
skipButton.lineTo(990, 66); skipButton.lineTo(850, 66); skipButton.endFill();
skipButton.createTextField("label", 1, 850, 33, 140, 28);
skipButton.label.text = "跳过本段"; skipButton.label.setTextFormat(small); skipButton.label.selectable = false;
skipButton.onRelease = function():Void { this._parent.finishCard(); };
chapterNumber.setTextFormat(small); chapterTitle.setTextFormat(large); hint.setTextFormat(small);
chapterNumber.selectable = chapterTitle.selectable = hint.selectable = false;
this.finishCard = function():Void {
    if (ended) return;
    ended = true;
    _root.书中过场释放暂停(pauseLease);
    delete this.onEnterFrame;
    this.unloadMovie();
};
this.advanceChapter = function():Void {
    if (++cursor >= lines.length) { this.finishCard(); return; }
    chapterNumber._y = 72; chapterTitle._y = 116;
    speaker.text = String(lines[cursor].speaker); speech.text = String(lines[cursor].text);
    hint._y = 466; hint.text = String(cursor + 1) + " / " + String(lines.length) + " · 点击继续";
    hint.setTextFormat(small);
};
veil.onRelease = function():Void { this._parent.advanceChapter(); };
this.onUnload = function():Void { _root.书中过场释放暂停(pauseLease); };
this.onEnterFrame = function():Void {
    if (ownerSlot !== String(_root.savePath) || ownerWorld !== _root.gameworld.__stageReturnWorldIdentity) { this.finishCard(); return; }
    var elapsed:Number = getTimer() - began;
    this._alpha = Math.min(100, elapsed / 4);
    if (lines.length == 0 && elapsed > 4200) this.finishCard();
};
}
