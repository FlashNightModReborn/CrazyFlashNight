

/*
If the frame classFrame does not already shows a page,
the url passed as parameter is used to load content.
*/
window.onload = function() {
    if (classFrame.document.title != "") {
        // already content in there
        return;
    }
    var q = window.location.search;
    var url = q.substring(1, q.length);
    if (url != "") {
        classFrame.document.location = url;
    } else {
    	// no (valid) url passed for classFrame
    	// use the first link in the TOC to fill the classFrame
		url = tocFrame.document.links[0];
		if (url != undefined) {
			classFrame.document.location = url;
		}
    }
}

/*
Tells the toc frame to update and highlight the link that corresponds to the shown page.
*/
function setCurrentPage(inPageClassName) {
	tocFrame.update(inPageClassName);
}


