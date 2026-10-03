stop();
// Standalone chapter-card sample. Game classes remain owned by asLoader.
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
this.createEmptyMovieClip("veil", 1);
veil.beginFill(0x0c1310, 95); veil.moveTo(0,0); veil.lineTo(1024,0);
veil.lineTo(1024,576); veil.lineTo(0,576); veil.lineTo(0,0); veil.endFill();
this.createTextField("chapterNumber", 2, 120, 183, 784, 40);
this.createTextField("chapterTitle", 3, 100, 242, 824, 90);
this.createTextField("hint", 4, 100, 410, 824, 35);
var small:TextFormat = new TextFormat("_sans", 18, 0xb8b68c); small.align = "center";
var large:TextFormat = new TextFormat("_sans", 43, 0xeee5c8); large.align = "center";
chapterNumber.text = "修理大学  /  " + String(chapter.index + 1) + " · 7";
chapterTitle.text = String(chapter.title);
hint.text = "点击继续";
chapterNumber.setTextFormat(small); chapterTitle.setTextFormat(large); hint.setTextFormat(small);
chapterNumber.selectable = chapterTitle.selectable = hint.selectable = false;
this.finishCard = function():Void {
    if (ended) return;
    ended = true;
    _root.书中过场释放暂停(pauseLease);
    delete this.onEnterFrame;
    this.unloadMovie();
};
veil.onRelease = function():Void { this._parent.finishCard(); };
this.onUnload = function():Void { _root.书中过场释放暂停(pauseLease); };
this.onEnterFrame = function():Void {
    if (ownerSlot !== String(_root.savePath) || ownerWorld !== _root.gameworld.__stageReturnWorldIdentity) { this.finishCard(); return; }
    var elapsed:Number = getTimer() - began;
    this._alpha = Math.min(100, Math.min(elapsed / 4, Math.max(0, (4200 - elapsed) / 5)));
    if (elapsed > 4200) this.finishCard();
};
}
