
Alcon (Actionscript Logging Console) v1.0.5

An external output console for Macromedia Flash
by Sascha Balkau <sascha@hiddenresource.corewatch.net>
http://hiddenresource.corewatch.net/

Alcon is a debug utility for Flash developers who write alot of Actionscript code and
use the output panel for debugging. It provides an external output console to which
debug info (or any other info) can be sent. By using Alcon, Flash applications can be
debugged easily without the need of the Flash IDE.

Main features:
- Font face and size can be configured.
- Console colors, size and position can be configured (for PC executable version).
- Five levels of logging severity which can be filtered.
- Supports recursive Object/Movieclip tracing.
- Color and Monochrome mode.
- Supported by as2lib.


This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.



1. CONTENTS
-----------
The following files are included within the Alcon archive:

Alcon/Alcon.cfg						- Configuration file for Alcon
Alcon/Alcon.exe						- Alcon executable for Windows
Alcon/Alcon.swf						- Alcon SWF version
Alcon/ReadMe.txt					- This text file
classes/net/hiddenresource/util/Debug.as		- The logging dispatcher class
icon/alcon_dockicon.png					- Alcon icon file for use with docks
sources/bin						- Empty! Used for publishing Fla's
sources/fla/Console.fla					- Fla file of Alcon Console
sources/fla/Test.fla					- Fla file for the Test.swf
sources/src/Console.as					- Class file for Alcon
Test.swf						- File for testing Alcon



2. INSTALLATION
---------------
Follow these steps to install Alcon:

a) Copy 'net/hiddenresource/util/Debug.as' to your Actionscript Class Path
   (by default 'C:\Documents and Settings\username\Local Settings\Application Data\Macromedia\
    Flash MX 2004\en\Configuration\Classes\') or to where you store your additional classes.
b) Copy the 'Alcon' folder to where you like (for example 'C:\Program Files\').

Alcon doesn't make any changes to the Windows registry or any other places.
For uninstalling, it is only necessary to delete the copied files/folders.



3. USAGE
--------
Start Alcon by executing 'Alcon.exe' on Windows. You might want to create a link of it in
the Startmenu or on the Desktop for easier access.

Import the Alcon class into your project with:
  import net.hiddenresource.util.Debug;

Use Alcon's trace method to send messages to the Alcon output console:

   Debug.trace("A test message!");


The trace method supports three arguments which are all optional. If no argument was given,
Alcon will trace 'undefined'. The following arguments can be set:

   Debug.trace(outputVar, recursiveObjTracing, severityLevel);
   
[outputVar]		is the variable that should be debugged.

[recursiveObjTracing]	a Boolean. If set to true and outputVar is of type Object or
			Movieclip, Alcon will evaluate the object/clip and trace
			all it's contents recursively. Defaults to false if omitted.
			
[severityLevel]		a Number which determines the severity level of the output.
			Defaults to 1 if omitted.


Here are some examples of using the trace method:

   Debug.trace("Test Message!", 0);
      traces the text with a severity level of DEBUG.
   
   Debug.trace(test_obj, true);
      recursively traces the Object test_obj with severity level of INFO.

   Debug.trace(_root, true, 2);
      traces all variables, objects and movieclips in _root recursively with a
      severity level of WARN.



Setting the Filter Level
------------------------
The filter level can be changed with Alcon.setFilterLevel(0-4). By default all severity
levels will be traced. For example by using ...

   Debug.setFilterLevel(2);

... only outputs with a level of 2 and higher will be traced.



Using Level Descriptive Keywords
--------------------------------
Alcon can show a level descriptive prefix for each trace. By default these are omitted.
If they are activated by using ...

   Debug.showKeywords();

... Each output will be traced with a level keyword before it. For example:
--WARN: A warning message!
-DEBUG: Some debugging info.

The keywords can be turned of again by using ...

   Debug.hideKeywords();



Setting recursion depth for object tracing
------------------------------------------
By default this depth is set to 20. This means that by using 'recursive object tracing'
an object's or movieclip's contents will be traced down to a hierarchy of 20 levels.
This is enough for most cases but if you are using objects/clips with a deeper hierarchy,
you can raise the maximum limit with this method:

   Debug.setRecursionDepth(60);
      sets the maximum recursion depth to 60.



Using Clear Buffer and Delimiter signals
----------------------------------------
Since version 1.0.5 you can clear the console buffer or send a delimiter line to it from
within your code. The console will parse the tags [%CLR%] and [%DLT%] to clear the buffer
or place a delimiter line. For these tags to be recognized by the console they must be
written uppercase and at the beginning of a text. Optionally you can use the methods
Debug.clr() and Debug.dlt() to send the signals.

   Debug.trace("[%CLR%]Here's some output!");
      clears the console buffer and outputs the text.
      
   Debug.clr();
   Debug.trace("Here's some output!");
      Same as above.
      
   Debug.trace("[%DLT%]More text to come ...");
   or ...
   Debug.dlt();
   Debug.trace("More text to come ...");
      ... both yield in placing a delimiter line and outputting the text under it.




4. MAC/LINUX SUPPORT
--------------------
Alcon can be used the same way on Mac or Linux. At the moment no executable version for
Macintosh is included but the SWF version can be used platform independently and only
lacks the window sizing and positioning features as well as the status bar.



4. CONFIGURATION
----------------
Alcon's output console can be configured by changing the 'Alcon.cfg' file!
The following settings can be made:

FONT_FACE		Determines which font face will be used.
FONT_SIZE		Determines the used font size.
BUFFER_LENGTH		Sets the buffer size of the output console. If this value is
			reached, the buffer will be emptied.
BUFFER_INFO		Determines if buffer information will be shown in the status bar.
WIN_XPOS		The x position of Alcon's window. Negative values are possible.
WIN_XPOS		The y position of Alcon's window. Negative values are possible.
WIN_WIDTH		The width of Alcon's window.
WIN_HEIGHT		The height of Alcon's window.
USE_COLORS		Determines of color mode is used or not. If disabled, all text will
			use the LEVEL_1_COLOR. If enabled, the output area will be in HTML mode
			which can become slow if alot of text is in the backbuffer.
BG_COLOR		Defines the background color of the output area.
LEVEL_[0-4]_COLOR	These values define the colors for the various severity levels.
DELIMITER		A string which is used for the delimiter signal.




6. CONTACT
----------
Please send comments, suggestions or bug reports to sascha@hiddenresource.corewatch.net or post
them at http://hiddenresource.corewatch.net/index.php?itemid=17



7. HISTORY
----------
v1.0.5
- Added control tags [%CLR%] and [%DLT%] for sending buffer clear and delimiter signals.
- Added clr() method to Debug.as for sending clear buffer signals.
- Added dlt() method to Debug.as for sending delimiter signals.
- Added delimiter string to Alcon.cfg file so it can be changed by the user.
- Changed config file so it uses '#' instead of '//' for comment lines.
- Replaced supressLevelDesc() method with showKeywords() and hideKeywords().
- Added getFilterLevel() method to Debug.as for compability with as2lib.
- Fixed a bug in the console that crippled output text in color mode when sending '<' and '>'
  characters.
- Changed package of Debug class to net.hiddenresource.util because an extra namespace is not
  necessary for only one class.
- Made exe version a standalone barebone projector so it fits better into an open source
  development environment.
- Several internal changes in Debug.as and Console.as.

v1.0.4
- Changed class name to Debug.
- Added compability for Debug.as to compile with MTASC.

v1.0.3
- Application name changed from 'Output Logger' to 'Alcon'.
- Statusbar added for the executable version which displays some info like
  buffer status and pause mode.
- Added option to display buffer info in the status bar.
- Added support for recursive object tracing.
- Added keyboard control for using pause, clear buffer and reset.
- Right click menu has been changed.
- Added 'about' info.
- Removed a bug which caused a memory access violation when using clear buffer
  while logging (hopefully!).
- Uses 'Courier New' as default font now which most people should have.

v1.0.2
- Added support for setting the console window size.
- Included ReadMe file.
- Rewrote console code to AS2 class code.

v1.0.1
- Added support for positioning the console window.
- Added option to turn off color mode.

v1.0.0
Initial public release.


** Big thanks to the folks on [Flashcoders] and [OSFlash] for all the support! **
