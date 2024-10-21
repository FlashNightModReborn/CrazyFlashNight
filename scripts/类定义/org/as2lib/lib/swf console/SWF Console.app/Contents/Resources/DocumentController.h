/*

       File: DocumentController.h

   Contains: Controller class for Document.nib

     Author: Ricci Adams (ricci@musictheory.net)

    License: Copyright (c) 2005, Ricci Adams.

             This file is part of SWF Console.

             SWF Console is free software; you can redistribute it and/or
             modify it under the terms of the GNU General Public License as
             published by the Free Software Foundation; either version 2 of the
             License, or (at your option) any later version.
 
             This program is distributed in the hope that it will be useful,
             but WITHOUT ANY WARRANTY; without even the implied warranty of
             MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
             GNU General Public License for more details.

             You should have received a copy of the GNU General Public License
             along with this program; if not, write to the Free Software
             Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  
             02111-1307  USA

*/ 

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#define SCLogToolbarIdentifier		@"SWF Console - Log Toolbar Identifier"
#define SCClearToolbarIdentifier	@"SWF Console - Clear Toolbar Identifier"
#define SCMarkToolbarIdentifier		@"SWF Console - Mark Toolbar Identifier"
#define SCFlareToolbarIdentifier	@"SWF Console - flare Toolbar Identifier"
#define SCFlasmToolbarIdentifier	@"SWF Console - flasm Toolbar Identifier"
#define SCSwfdumpToolbarIdentifier	@"SWF Console - swfdump Toolbar Identifier"

@class FlareController;
@class FlasmController;
@class SwfdumpController;

@interface DocumentController : NSDocument {
	IBOutlet	NSWindow			*oWindow;

	IBOutlet	NSTextView			*oTextView;
	IBOutlet	NSSplitView			*oSplitView;
	IBOutlet	WebView				*oWebView;
	IBOutlet	WebView				*oLoggerWebView;

				FlareController		*_flareController;
				FlasmController		*_flasmController;
				SwfdumpController	*_swfdumpController;

				NSToolbar			*_toolbar;
				
				int					_previousTextViewHeight;
				int					_uniqueIdentifier;
}

- (void) createHTMLFile;
- (void) deleteHTMLFile;
- (NSString *) pathToHTMLFile;

- (IBAction) saveOutput:(id)sender;

- (IBAction) toggleLog:(id)sender;
- (IBAction) clearLog:(id)sender;
- (IBAction) markLog:(id)sender;

- (IBAction) runThroughFlare:(id)sender;
- (IBAction) runThroughFlasm:(id)sender;
- (IBAction) runThroughSwfdump:(id)sender;

@end
