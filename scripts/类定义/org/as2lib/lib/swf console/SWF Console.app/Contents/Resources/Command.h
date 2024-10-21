/*

       File: Command.h

   Contains: Wrapper class for NSTask.  Launches a command in the background and
             activates a target/action pair upon completion.

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


@interface Command : NSObject {
	NSTask		*_task;

	NSString	*_launchPath;
	NSArray		*_arguments;
	NSString	*_output;

	id			_target;
	SEL			_action;	
}

- (void) launch;

- (void) setLaunchPath:(NSString *)path;
- (NSString *) launchPath;
- (void) setArguments:(NSArray *)arguments;
- (NSArray *) arguments;
- (NSString *) output;
- (void) setTarget:(id)newTarget;
- (id) target;
- (void) setAction:(SEL)newAction;
- (SEL) action;

@end
