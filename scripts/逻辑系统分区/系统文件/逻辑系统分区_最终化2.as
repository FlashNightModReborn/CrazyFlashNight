this.stop();

this.loadtime = getTimer();

this.onEnterFrame = function(){
	if(_root.loaders.current >= _root.loaders.length){
		delete this.onEnterFrame;
		this.loadtime = getTimer() - this.loadtime;
		_root.服务器.发布服务器消息("Load complete " + this.loadtime + "ms");
		this.play();
		return;
	}
	var time = getTimer();
	_root.loaders[_root.loaders.current]();
	_root.loaders.current++;
	_root.服务器.发布服务器消息(getTimer() - time);
}
