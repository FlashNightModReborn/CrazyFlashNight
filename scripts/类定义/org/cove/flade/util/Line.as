/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * Line class
 * Copyright 2004, 2005 Alec Cove
 * 
 * This file is part of Flade - The Flash Dynamics Engine. 
 *	
 * Flade is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Flade is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Flade; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * Flash is a registered trademark of Macromedia
 */
 
import org.cove.flade.util.Vector;
 
class org.cove.flade.util.Line {
	
	public var p1:Vector;
	public var p2:Vector;
	
	public function Line(p1:Vector, p2:Vector) {
		this.p1 = p1;
		this.p2 = p2;
	}
}