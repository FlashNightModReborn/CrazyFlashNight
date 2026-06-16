//所有_root字段指向主文件的_root
this._lockroot = false;
_root.stop();

function 打印加载内容(str){
	_root.加载内容文本.text = str;
}