-----------
Debug Panel
-----------

Homepage: http://www.bit-101.com/DebugPanel
Article: http://www.bit-101.com/blog/archives/000119.html

Instructions:

1. Put the Debug.as file in the root level of your class path. 
   If you don't know what a class path is, you're going to have to find out on your own. sorry.

2. Run the "Flash Debug Panel.exe" file.

3. In your code, you can use the following methods and syntax:

Debug.trace("hello world");             // any type
Debug.trace(value1, "hello", _root);    // any types separated by commas
Debug.traceObject(myComponent, n);      // n is how many levels deep the trace will iterate
Debug.clear();                          // clears the panel

4. In the panel, you can:

- press "Clear" to clear the panel.
- press "Save" to save contents of panel to a text file (save dialog will open).
- press "Print" to send contents of panel directly to printer (NO print dialog).
- change the font size (minimum 8).
- select "On top" to keep the panel the topmost window.
- select "Get focus" to move the panel to the top when it gets new content.
  (only applicable if "On top" is not selected)