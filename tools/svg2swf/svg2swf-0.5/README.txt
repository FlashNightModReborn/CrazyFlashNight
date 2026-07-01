svg2swf (version 0.5)
----------------------

svg2swf is an SVG to Flash SWF converter. It is written in C and uses libsvg to
parse the SVG document and libming to generate the SWF file. It is available for
both Linux and Windows platforms. 

The homepage for the svg2swf project is http://svg2swf.sourceforge.net. The 
usage.html page describes how to use svg2swf.

svg2swf is free software and is available for distribution under the GNU Lesser 
General Public License (LGPL) version 2.1 software license - see COPYING.txt.

svg2swf uses the following software:
- libsvg* (http://webcvs.cairographics.org/libsvg/)
- libming** (http://www.libming.org/)
- expat (http://expat.sourceforge.net/)
- libpng (http://www.libpng.org/pub/png/libpng.html)
- libjpeg (http://www.ijg.org/)
- zlib (http://www.zlib.net/)
- freetype2 (http://www.freetype.org/)
- libsvg-cairo* (http://webcvs.cairographics.org/libsvg-cairo/)
- cairo (http://www.cairographics.org/)
- libcroco* (http://www.freespiders.org/projects/libcroco/)
- glib (http://library.gnome.org/devel/glib/stable/)
- uriparser (http://uriparser.sourceforge.net/)
- libcurl (http://curl.haxx.se/libcurl/)
The project web pages contain details of the licenses.
* modified versions are available in the svg2swf CVS
** a patch file is available in the svg2swf CVS

The font file, test_sans.fdb, is a copy of the ming/perl_ext/common/_sans.fdb 
file in the Ming source tree. E.g. use the "--default-font" command-line option
to set it to be the default font.

The pan_zoom.as actionscript file provides simple pan and zoom functionality:
- pan: press the left mouse button and move the mouse
- zoom: use the mouse wheel or the +/- keys to zoom in or out
- press 'r' to return to the original scale and position
Add it to the Flash movie using the "--asf" command-line option.

The following binary files were copied from the GTK+ windows page 
(http://www.gtk.org/download-windows.html):
- freetype6.dll
- libcairo-2.dll
- libpng12-0.dll
- zlib1.dll
- libglib-2.0-0.dll

The following Microsoft Visual C++ 7.1 redistributable runtime library is 
provided (see also http://support.microsoft.com/kb/326922)
- msvcr71.dll


11 April 2009
Philip de Nier
