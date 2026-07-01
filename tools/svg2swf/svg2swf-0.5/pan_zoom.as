/*
 * $Id: pan_zoom.as,v 1.2 2009/01/21 11:45:02 philipn Exp $
 *
 * Copyright (C) 2009  Philip de Nier <philipn@users.sourceforge.net>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */
 
/*

Pan: press the left mouse button and move the mouse
Zoom: use the mouse wheel or the +/- keys to zoom in or out
Press 'r' to return to the original scale and position

*/

var scaleMove = 0;
var mouseIsDown = false;
var mouseX = 0;
var mouseY = 0;


function do_scale(scaleInc)
{
    scaleMove += scaleInc;

    var scale = 100 * Math.pow(0.99, scaleMove);
    
    var xScaleFactor = scale / this._xscale;
    var yScaleFactor = scale / this._yscale;
    
    var xOffset = this._x - this._width / 2.0 * (100.0 / this._xscale - 1);
    var yOffset = this._y - this._height / 2.0 * (100.0 / this._yscale - 1);
    
    this._xscale = scale;
    this._yscale = scale;
    
    this._x = xOffset * xScaleFactor + this._width / 2.0 * (100.0 / this._xscale - 1);
    this._y = yOffset * yScaleFactor + this._height / 2.0 * (100.0 / this._yscale - 1);
};

function do_pan()
{
    var mouseXDiff = mouseX - _root._xmouse;
    var mouseYDiff = mouseY - _root._ymouse;
        
    this._x -= mouseXDiff / 3.0 * this._xscale / 100.0;
    this._y -= mouseYDiff / 3.0 * this._yscale / 100.0;
    
    mouseX = _root._xmouse + mouseXDiff;
    mouseY = _root._ymouse + mouseYDiff;
};


mouseEventHandlers = 
{
    onMouseDown:function() 
    {
        mouseIsDown = true;
        mouseX = _root._xmouse;
        mouseY = _root._ymouse;
    },

    onMouseUp:function() 
    {
        mouseIsDown = false;
    },
    
    onMouseWheel:function(delta)
    {
        if (delta >= 0)
        {
            do_scale(5);
        }
        else
        {
            do_scale(-5);
        }
    }

};

keyEventHandlers = 
{
    onKeyDown:function() 
    {
        switch (Key.getAscii())
        {
            case 114: // 'r'
                scaleMove = 0;
                _root._x = 0;
                _root._y = 0;
                _root._xscale = 100;
                _root._yscale = 100;
                break;
            case 43: // '+'
                do_scale(-5);
                break;
            case 61: // '='
                do_scale(-5);
                break;
            case 45: // '-'
                do_scale(5);
                break;
            case 95: // '_'
                do_scale(5);
                break;
        };
    }
};

Key.addListener(keyEventHandlers);
Mouse.addListener(mouseEventHandlers);

onEnterFrame = function()
{
    if (mouseIsDown)
    {
        do_pan();
    }
};

