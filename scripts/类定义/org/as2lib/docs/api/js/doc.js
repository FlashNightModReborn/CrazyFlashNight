

var isShowingPrivateMembers = 1;
var isShowingSourceCode = 0;
var isHidingAccessKeyInfo = 0;
var privateElements = null;
var sourceCodeDiv = null;
var view_btn = null;
var hide_btn = null;
var sourceCodeDiv = null;
var view_source_btns = null;
var hide_source_btns = null;
var sourceCodeViewDiv = null;
var accessKeyLinksSpan = null;

/*
Adds a id 'framed' to the body node if the page is framed.
This is equivalent to: <body id="framed">
This way the css style 'framed' can give a different appearance to the page.
*/
window.onload = function(e) {
	if (parent.location.href != self.location.href) {
		// page is framed
		// set body id to 'framed': <body id="framed">
		// to address css style 'framed'
		// so that the margins can be defined differently
		var bodyNode = document.getElementsByTagName('body')[0];
		bodyNode.setAttribute("id", "framed");
		top.setCurrentPage(bodyNode.getAttribute("pageId"));
	}
 
	var cookie = readCookie("hidePrivateMembers");
	isShowingPrivateMembers = cookie;
	
	cookie = readCookie("sourceCode");
	isShowingSourceCode = cookie;
	
	readPageElements();

	if (isShowingPrivateMembers == "1" || isShowingPrivateMembers == null) {
		showPrivate();
	} else {
		hidePrivate();
	}
	
	if (isShowingSourceCode == "1") {
		viewSource();
	} else {
		hideSource();
	}
	
	cookie = readCookie("hideAccessKeyInfo");
	if (cookie != null) {
		isHidingAccessKeyInfo = cookie;
	}
	displayAccessKeyInfo();
}

window.onunload = function(e) {
	setCookie("privateMembers", 1-isShowingPrivateMembers, 365);
	setCookie("sourceCode", isShowingSourceCode, 365);
	setCookie("hideAccessKeyInfo", isHidingAccessKeyInfo, 365);
}

function readPageElements () {
	if (sourceCodeDiv == null) {
		var f = getElementsByClassName('sourceCode')[0];
		if (f != null) sourceCodeDiv = f;
	}
	if (sourceCodeViewDiv == null) {
		var f = getElementsByClassName('sourceCodeView')[0];
		if (f != null) sourceCodeViewDiv = f;
	}
	if (view_source_btns == null) {
		var f = getElementsByClassName('viewSource');
		if (f != null) view_source_btns = f;
	}
	if (hide_source_btns == null) {
		var f = getElementsByClassName('hideSource');
		if (f != null) hide_source_btns = f;
	}
	if (view_btn == null) {
		var f = getElementsByClassName('viewPrivate')[0];
		if (f != null) view_btn = f;
	}
	if (hide_btn == null) {
		var f = getElementsByClassName('hidePrivate')[0];
		if (f != null) hide_btn = f;
	}
	if (accessKeyLinksSpan == null) {
		var f = getElementsByClassName('accessKeyLinks')[0];
		if (f != null) accessKeyLinksSpan = f;
	}
}

/*
Loads the frameset, passing the current page url as parameter so this
page can be loaded into the frame classFrame.
*/
function showTOC() {
	parent.location = "index.html?" + self.location.href;
}

/*
Replaces the frameset by the current page.
*/
function hideTOC() {
	parent.location = self.location;
}

function getElementsByClassName(className) {
	var elements = [];
	var allObjects = (document.all) ? document.all : document.getElementsByTagName("*");
	var i = allObjects.length-1;
	do 
	{
		if (allObjects.item(i).className.indexOf(className) != -1)
			elements.push(allObjects.item(i));
		i--;
	} while (i>=0);
	return elements;
}

function setPrivateElements () {
	privateElements = getElementsByClassName('private');
}

function setButtonsToShowPrivateState() {
	if (view_btn != null) {
		view_btn.style.display = "none";
	}
	if (hide_btn != null) {
		hide_btn.style.display = "inline";
	}
}

function setButtonsToHidePrivateState() {
	if (view_btn == null) {
		var f = getElementsByClassName('viewPrivate')[0];
		if (f != null) view_btn = f;
	}
	if (hide_btn == null) {
		hide_btn = getElementsByClassName('hidePrivate')[0];
	}	
	if (view_btn != null) {
		view_btn.style.display = "inline";
	}
	if (hide_btn != null) {
		hide_btn.style.display = "none";
	}
}

function showPrivate() {
	isShowingPrivateMembers = "1";
	setButtonsToShowPrivateState();
	hide_btn.style.display = "inline";
	if (privateElements == null) {
		setPrivateElements();
	}
	var len = privateElements.length;
	for (i=0; i<len; ++i) {
		privateElements[i].style.display = "block";
	}
	setCookie("privateMembers", 1-isShowingPrivateMembers, 365);
}

function hidePrivate() {
	isShowingPrivateMembers = "0";
	setButtonsToHidePrivateState();
	if (privateElements == null) {
		setPrivateElements();
	}
	var len = privateElements.length;
	for (i=0; i<len; ++i) {
		privateElements[i].style.display = "none";
	}
	setCookie("privateMembers", isShowingPrivateMembers, 365);
}

function setCookie(name,value,days) {
	if (days) {
		var date = new Date();
		date.setTime(date.getTime()+(days*24*60*60*1000));
		var expires = "; expires="+date.toGMTString();
	} else expires = "";
	document.cookie = name+"="+value+expires+"; path=/";
}

function readCookie(name) { 
	var nameEQ = name + "=";
	var ca = document.cookie.split(';');
	if (ca.length == 0) {
		ca = document.cookie.split(';');
	}
	for (var i=0;i < ca.length;i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1,c.length);
		if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
	}
	return null;
}

function viewSource() {
	readPageElements();
	isShowingSourceCode = "1";
	setCookie("sourceCode", isShowingSourceCode, 365);
	if (sourceCodeDiv != null) {
		sourceCodeDiv.style.display = "block";
	}
	if (sourceCodeViewDiv != null) {
		sourceCodeViewDiv.style.borderBottomWidth = "0px";
	}
	setButtonsToHideSourceState();
}

function hideSource() {
	isShowingSourceCode = "0";
	setCookie("sourceCode", isShowingSourceCode, 365);
	readPageElements();
	if (sourceCodeDiv != null) {
		sourceCodeDiv.style.display = "none";
	}
	if (sourceCodeViewDiv != null) {
		sourceCodeViewDiv.style.borderBottomWidth = "1px";
	}
	setButtonsToViewSourceState();
}

function setButtonsToHideSourceState() {
	for (var i=0;i<view_source_btns.length;i++) {
		view_source_btns[i].style.display = "none";
	}
	for (var i=0;i<hide_source_btns.length;i++) {
		hide_source_btns[i].style.display = "inline";
	}
}

function setButtonsToViewSourceState() {
	for (var i=0;i<view_source_btns.length;i++) {
		view_source_btns[i].style.display = "inline";
	}
	for (var i=0;i<hide_source_btns.length;i++) {
		hide_source_btns[i].style.display = "none";
	}
}

function toggleAccessKeyInfo() {
	isHidingAccessKeyInfo = 1-isHidingAccessKeyInfo;
	setCookie("hideAccessKeyInfo", isHidingAccessKeyInfo, 365);
	displayAccessKeyInfo();
}

function displayAccessKeyInfo() {
	if (isHidingAccessKeyInfo == 0) {
		accessKeyLinksSpan.style.display = "none";
	} else {
		accessKeyLinksSpan.style.display = "inline";
	}
}


