function processMovieClips() {
    var doc = fl.getDocumentDOM();
    if (!doc) {
        fl.trace("No open document.");
        return;
    }

    var mainTimeline = doc.getTimeline();
    fl.trace("Starting to process all movie clips on the main timeline.");
    processClipsRecursively(doc, mainTimeline.layers);
    fl.trace("Finished processing all movie clips.");
}

function processClipsRecursively(doc, layers) {
    for (var i = 0; i < layers.length; i++) {
        var layer = layers[i];
        var frames = layer.frames;
        for (var j = 0; j < frames.length; j++) {
            var elements = frames[j].elements;
            for (var k = 0; k < elements.length; k++) {
                var element = elements[k];
                if (element.elementType === "instance" && element.instanceType === "movie clip") {
                    doc.selectNone(); // Clear previous selections
                    element.selected = true; // Select the movie clip
                    doc.enterEditMode("inPlace"); // Enter the edit mode of the movie clip
                    convertToKeyframesAndBreakApart(doc); // Convert to keyframes and break apart
                    doc.exitEditMode(); // Exit edit mode
                    element.selected = false; // Deselect the element
                }
            }
        }

        // Recursively process nested movie clips
        if (layer.layers) {
            processClipsRecursively(doc, layer.layers);
        }
    }
}

function convertToKeyframesAndBreakApart(doc) {
    var timeline = doc.getTimeline();
    var layers = timeline.layers;
    for (var i = 0; i < layers.length; i++) {
        var layer = layers[i];
        var frames = layer.frames;
        for (var j = 0; j < frames.length; j++) {
            doc.selectAll(); // Select all elements in the frame
            doc.convertToKeyframes(j, j); // Convert the current frame to keyframes
            doc.breakApart(); // Break apart the elements
            doc.selectNone(); // Clear selection
        }
    }
}

processMovieClips();
