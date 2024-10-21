/*
 * Copyright (c) 2005 Pablo Costantini (www.luminicbox.com). All rights reserved.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Class: LuminicBox.Log.PropertyInspector
 * 
 * This is a helper class for the publishers.
 * 
 * It contains arrays with the reserved properties for these classes.
 * 	- MovieClip
 * 	- Button
 */
class LuminicBox.Log.PropertyInspector {
	
// Group: Static Fields	
	public static var movieClipProperties = new Array("_alpha","_currentframe","_droptarget","enabled","focusEnabled","_focusrect","_framesloaded","_height","hitArea","_lockroot","menu","_name","_parent","_quality","_rotation","_soundbuftime","tabChildren","tabEnabled","tabIndex","_target","_totalframes","trackAsMenu","_url","useHandCursor","_visible","_width","_x","_xmouse","_xscale","_y","_ymouse","_yscale");
	public static var buttonProperties = new Array("_alpha","enabled","_focusrect","_height","_quality","menu","_name","_parent","_quality","_rotation","_soundbuftime","tabEnabled","tabIndex","_target","trackAsMenu","_url","useHandCursor","_visible","_width","_x","_xmouse","_xscale","_y","_ymouse","_yscale");
	public static var soundProperties = new Array("duration","id3","position");
	public static var textFieldProperties = new Array("_alpha","autoSize","background","backgroundColor","border","borderColor","bottomScroll","condenseWhite","embedFonts","_height","hscroll","html","htmlText","length","maxChars","maxhscroll","maxscroll","menu","mouseWheelEnabled","multiline","_name","_parent","password","_quality","restrict","_rotation","scroll","selectable","styleSheet","tabEnabled","tabIndex","_target","text","textColor","textHeight","textWidth","type","_url","variable","_visible","_width","wordWrap","_x","_xmouse","_xscale","_y","_ymouse","_yscale");
	
	
// Group: Private Methods
	/*
	 * Constructor: PropertyInspector
	 * 
	 * Private constructor. DO NOT USE.
	 */
	private function PropertyInspector() { }
	
}



/*
 * Group: Changelog
 * 
 * Mon May 02 01:43:52 2005:
 * 	- added Sound and TextField properties
 * 
 * Wed Apr 27 00:18:47 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Sun Mar 20 17:23:19 2005:
 * 	- first release.
 */