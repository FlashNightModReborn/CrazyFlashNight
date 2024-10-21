


var selectedLink;

if (parent.location.href != self.location.href) {
    // page not in frameset
    // let all links point to frame "classFrame"
    /*
    // 'setAttribute' does not work properly in Mozilla, so I need to fall back to document.write
    var z = document.getElementsByTagName("head")[0].appendChild(document.createElement("base"));
    z.setAttribute('target','classFrame');
    */
    document.write("<base target=\"classFrame\" />");
}

/*
Adds a id 'toc' to the body node if the page is framed.
This is equivalent to: <body id="toc">
This way the css style 'toc' can give a different appearance to the page.
To set the class <body class="toc"> instead of the id does not seem to work on IE.
Update: now the id is default, and removed when the toc is not framed. This does not give a unstyled flash on loading.
*/
window.onload = function () {
    if (parent.location.href == self.location.href) {
        // page is framed
        var bodyNode = document.getElementsByTagName('body')[0];
        bodyNode.setAttribute("id", "");
    }
}

/*
Loads the frameset.
*/
function showTOC() {
	self.location = "index.html";
}

/*
Replaces the frameset by the current page.
*/
function hideTOC() {
	parent.location = self.location;
}

/*
Sets the highlight of the link that corresponds to the shown page. 
*/
function update (inPageClassName) {
	var linkId = inPageClassName.split("Page")[1];
	var selLink = getElementsByClassName(linkId)[0];
	if (selectedLink != undefined) {
		selectedLink.className = selectedLink.className.split(" selected")[0];
	}
	selectedLink = selLink;
	selectedLink.className = linkId + " selected";
}

/*
Utility function
*/
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



