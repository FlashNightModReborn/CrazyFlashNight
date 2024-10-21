/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *    this list of conditions and the following disclaimer.
 *  
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *    this list of conditions and the following disclaimer in the documentation 
 *    and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products 
 *    derived from this software without specific prior written permission. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE.
 */
 
import org.actionstep.NSRect;
import org.actionstep.NSPoint;
//import org.actionstep.NSException;

class org.actionstep.ASDraw {

  public static var ANGLE_LEFT_TO_RIGHT:Number =   0;
  public static var ANGLE_TOP_TO_BOTTOM:Number =  90;
  public static var ANGLE_RIGHT_TO_LEFT:Number = 180;
  public static var ANGLE_BOTTOM_TO_TOP:Number = 270;

  public static var TRACE_FLAG:Boolean = false;

  public static function setTrace(value:Boolean)
  {
    TRACE_FLAG = value;
  }

  //draws a horizontal line with thickness=1.
  public static function drawHLine(mc:MovieClip, lineColor:Number, x1:Number, x2:Number, y1:Number) {
	 drawLineSimple(mc, lineColor, x1, x2, y1, y1);
  }

  //draws a vertical line with thickness=1.
  public static function drawVLine(mc:MovieClip, lineColor:Number, y1:Number, y2:Number, x1:Number) {
    if (y1 > y2) {
      var yTmp:Number = y1;
      y1 = y2;	   	
      y1 = yTmp;	   	
	  }	 
	  y2 += 1;
    drawLineSimple(mc, lineColor, x1, x1, y1, y2);
  }

  //draws a vertical line with thickness=1 and the edges fading out.
  public static function drawVLineEdgeFade(mc:MovieClip, lineColor:Number, y1:Number, y2:Number, x1:Number, edge:Number) {
	  if (y1 > y2) {
      var yTmp:Number = y1;
      y1 = y2;	   	
      y1 = yTmp;	   	
	  }	 
	  y2 += 1;
    drawLineSimple(mc, lineColor, x1, x1, y1+edge, y2-edge);
    drawLineFade(mc, lineColor, x1, x1, y1+edge, y1);
    drawLineFade(mc, lineColor, x1, x1, y2-edge, y2);
  }

  //draws a horizontal line with thickness=1 and the edges fading out.
  public static function drawHLineEdgeFade(mc:MovieClip, lineColor:Number, x1:Number, x2:Number, y1:Number, edge:Number) {
	  if (x1 > x2) {
      var xTmp:Number = x1;
      x1 = x2;	   	
      x2 = xTmp;	   	
	  }	 
	  x2 += 1;
    drawLineSimple(mc, lineColor, x1+edge, x2-edge, y1, y1);
    drawLineFade(mc, lineColor, x1+edge, x1, y1, y1);
    drawLineFade(mc, lineColor, x2-edge, x2, y1, y1);
  }

  public static function drawVLineFade(mc:MovieClip, lineColor:Number, y1:Number, y2:Number, x1:Number) {
    drawLineShared(mc, lineColor, true, x1, x1, y1, y2, 0);
  }

  public static function drawHLineFade(mc:MovieClip, lineColor:Number, x1:Number, x2:Number, y1:Number) {
    drawLineShared(mc, lineColor, true, y1, y1, x1, x2, 0);
  }

  public static function drawLineFade(mc:MovieClip, lineColor:Number, x1:Number, x2:Number, y1:Number, y2:Number) {
    drawLineShared(mc, lineColor, true, x1, x2, y1, y2, 0);
  }

  public static function drawLineSimple(mc:MovieClip, lineColor:Number, x1:Number, x2:Number, y1:Number, y2:Number) {
    drawLineShared(mc, lineColor, false, x1, x2, y1, y2);
  }

  //draws a line with thickness=1.
  public static function drawLineShared(mc:MovieClip, lineColor:Number, isFade:Boolean, x1Param:Number, x2Param:Number, y1Param:Number, y2Param:Number) {
	  if (lineColor == undefined) {
	    return;
	  }
    var x1:Number = x1Param;
    var x2:Number = x2Param;
    var y1:Number = y1Param;
    var y2:Number = y2Param;
    var radians:Number = getRadians(x1, x2, y1, y2);
    
	  if (y1 > y2) {
      var yTmp:Number = y1;
      y1 = y2;	   	
      y2 = yTmp;	   	
	  }
	  //y2 += 1;
	  if (x1 > x2) {
      var xTmp:Number = x1;
      x1 = x2;	   	
      x2 = xTmp;	   	
	  }	 
	  //x2 += 1;
	  var w1:Number = x2 - x1 + 1;
	  var h1:Number = y2 - y1 + 1;
	  var xPlus:Number = 1;
	  var yPlus:Number = 1;
	  
	  var slope:Number = h1/w1;
	  
	  if (slope == 1)
	  {
	    yPlus = 0;
	  }
	  
	  if (w1 == 1) {
      xPlus = 1;	
    }
	  if (h1 == 1) {
      yPlus = 1;	
    }
    mc.lineStyle(undefined, 0, 100);
    if (isFade) {
      var colors:Array = [lineColor,lineColor];
      var alphas:Array = [100,0];
      var ratios:Array = [0x0,0xFF];
      var matrix:Object = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians };
      beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    } else {
      mc.beginFill(lineColor, 100);
    }

    mc.moveTo(x1Param,y1Param);
    mc.moveTo(x1Param+xPlus,y1Param+yPlus);
    mc.lineTo(x2Param+xPlus,y2Param+yPlus);
    mc.lineTo(x2Param,y2Param);
    mc.lineTo(x1Param,y1Param);
    mc.endFill();
  }

  /////////////////////////////////////////////////////////////////////////////
  // BOX METHODS
  /////////////////////////////////////////////////////////////////////////////

  //draws a rect with no border.
  public static function drawFill(mc:MovieClip, fillColor:Number, x1:Number, y1:Number, w1:Number, h1:Number) {
	  if (fillColor == undefined) 
	    return;
    mc.lineStyle(undefined, 0, 100);
    mc.beginFill(fillColor, 100);
    mc.moveTo(x1,y1);
    mc.lineTo(x1+w1, y1);
    mc.lineTo(x1+w1, y1+h1);
    mc.lineTo(x1, y1+h1);
    mc.lineTo(x1, y1);
    //mc.drawRect(x1, y1, w1, h1);
    mc.endFill();
  }

  // figure out how I wanna deal with the fact that these don't take w/h, but x1,x2,y1,y2
  public static function drawHBoxFade(mc:MovieClip, boxColor:Number, x1:Number, x2:Number, y1:Number, y2:Number) {
    drawBoxFade(mc, boxColor, x1, x2, y1, y2, 90);
  }

  public static function drawHBoxFade2(mc:MovieClip, boxColor:Number, boxColor2:Number, x1:Number, x2:Number, y1:Number, y2:Number) {
    drawBoxFade2(mc, boxColor, boxColor2, x1, x2, y1, y2, 90);
  }

  public static function drawBoxFade30(mc:MovieClip, boxColor:Number, x1:Number, x2:Number, y1:Number, y2:Number) {
//		trace('drawBoxFade30: ' + x1 + ',' + x2 + ',' + y1 + ',' + y2);
	  var w1:Number = x2 - x1;
	  var h1:Number = y2 - y1;
    var colors:Array = [boxColor,boxColor,boxColor];
    var alphas:Array = [80,0,0];
//    var ratios:Array = [0x0,0x33,0x66,0x99,0xCC,0xFF];
    var ratios:Array = [0x0,0x99,0xFF];
    var radians:Number = getRadiansByDegrees(45);
    var matrix:Object = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians };
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    mc.moveTo(x1,y1);
    mc.lineTo(x2,y1);
    mc.lineTo(x2,y2);
    mc.lineTo(x1,y2);
    mc.lineTo(x1,y1);
    mc.endFill();
  }

  public static function drawBoxFade(mc:MovieClip, boxColor:Number, x1:Number, x2:Number, y1:Number, y2:Number, degrees:Number) {
	  var w1:Number = x2 - x1;
	  var h1:Number = y2 - y1;
//    var colors = [boxColor,boxColor];
//    var alphas = [100,0];
//    var ratios = [0x0,0xFF];
    var colors:Array = [boxColor,boxColor,boxColor];
    var alphas:Array = [100,50,0];
    var ratios:Array = [0x0,0x33,0xFF];
    var radians:Number = getRadiansByDegrees(degrees);
    var matrix:Object = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians };
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    mc.moveTo(x1,y1);
    mc.lineTo(x2,y1);
    mc.lineTo(x2,y2);
    mc.lineTo(x1,y2);
    mc.lineTo(x1,y1);
    mc.endFill();
  }

  public static function drawBoxFade2(mc:MovieClip, boxColor:Number, boxColor2:Number, x1:Number, x2:Number, y1:Number, y2:Number, degrees:Number) {
	  var w1:Number = x2 - x1;
	  var h1:Number = y2 - y1;
    var colors:Array = [boxColor,boxColor2];
    var alphas:Array = [100,100];
    var ratios:Array = [0x0,0xFF];
    var radians:Number = getRadiansByDegrees(degrees);
    var matrix:Object = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians };
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    mc.moveTo(x1,y1);
    mc.lineTo(x2,y1);
    mc.lineTo(x2,y2);
    mc.lineTo(x1,y2);
    mc.lineTo(x1,y1);
    mc.endFill();
  }
  

  //draws a rect 
  public static function drawRect(mc:MovieClip, thick:Number, color:Number, x1:Number, y1:Number, w1:Number, h1:Number) {
    if (color == undefined) 
      return;
    mc.lineStyle(thick, color, 100);
    mc.moveTo(x1,y1);
    mc.lineTo(x1+w1, y1);
    mc.lineTo(x1+w1, y1+h1);
    mc.lineTo(x1, y1+h1);
    mc.lineTo(x1, y1);
  }
  
  //      ------------------      DRAW CURVE      ------------------      //

  public static function drawCurve(mc:MovieClip, thick:Number, color:Number, startX:Number, startY:Number, curveControlX:Number,
                          curveControlY:Number,endX:Number,endY:Number)
  {
    mc.lineStyle(thick,color);
    mc.moveTo(startX,startY);
    mc.curveTo(curveControlX,curveControlY,endX,endY);
  }

  // draw Oval

  public static function drawOval(mc:MovieClip, thick:Number, color:Number, x:Number,y:Number, width:Number,height:Number){
    mc.lineStyle(thick, color);
    mc.moveTo(x,y+height/2);
    mc.curveTo(x,y,x+width/2, y);
    mc.curveTo(x+width,y,x+width, y+height/2);
    mc.curveTo(x+width,y+height, x+width/2, y+height);
    mc.curveTo(x,y+height, x, y+height/2);
  }

  // ---------    FILL OVAL       ------------    //

  public static function fillOval(mc:MovieClip, thick:Number, color:Number, fill:Number, x:Number,y:Number, width:Number,height:Number){
    mc.lineStyle(thick, color);
    mc.moveTo(x,y+height/2);
    mc.beginFill(fill);
    mc.curveTo(x,y,x+width/2, y);
    mc.curveTo(x+width,y,x+width, y+height/2);
    mc.curveTo(x+width,y+height, x+width/2, y+height);
    mc.curveTo(x,y+height, x, y+height/2);
    mc.endFill();
  }

  //      ---------       DRAW CIRCLE-----------  //

  public static function drawCircle(mc:MovieClip, thick:Number, color:Number, r:Number,x:Number,y:Number){
    var styleMaker:Number = 22.5;
    mc.moveTo(x+r,y);
    mc.lineStyle(thick, color);
    var style:Number = Math.tan(styleMaker*Math.PI/180);
    for (var angle:Number=45;angle<=360;angle+=45){
      var endX:Number = r * Math.cos(angle*Math.PI/180);
      var endY:Number = r * Math.sin(angle*Math.PI/180);
      var cX:Number   = endX + r* style * Math.cos((angle-90)*Math.PI/180);
      var cY:Number   = endY + r* style * Math.sin((angle-90)*Math.PI/180);
      mc.curveTo(cX+x,cY+y,endX+x,endY+y);
    }
  }

  // ---------    DRAW FILLED circle, ----------- //

  public static function fillCircle(mc:MovieClip, thick:Number, color:Number, fill:Number, r:Number,x:Number,y:Number){
    var styleMaker:Number = 22.5;
    mc.moveTo(x+r,y);
    mc.lineStyle(thick, color);
    mc.beginFill(fill);
    var style:Number = Math.tan(styleMaker*Math.PI/180);
    for (var angle:Number=45;angle<=360;angle+=45){
      var endX:Number = r * Math.cos(angle*Math.PI/180);
      var endY:Number = r * Math.sin(angle*Math.PI/180);
      var cX:Number   = endX + r* style * Math.cos((angle-90)*Math.PI/180);
      var cY:Number   = endY + r* style * Math.sin((angle-90)*Math.PI/180);
      mc.curveTo(cX+x,cY+y,endX+x,endY+y);
    }
    mc.endFill();
  }

  //      ---------       DRAW helix shape        -----------     //

  public static function drawHelix(mc:MovieClip, thick:Number, color:Number, r:Number,x:Number,y:Number,styleMaker:Number){
    mc.moveTo(x+r,y);
    mc.lineStyle(thick, color);
    var style:Number = Math.tan(styleMaker*Math.PI/180);
    for (var angle:Number=45;angle<=360;angle+=45){
      var endX:Number = r * Math.cos(angle*Math.PI/180);
      var endY:Number = r * Math.sin(angle*Math.PI/180);
      var cX:Number   = endX + r* style * Math.cos((angle-90)*Math.PI/180);
      var cY:Number   = endY + r* style * Math.sin((angle-90)*Math.PI/180);
      mc.curveTo(cX+x,cY+y,endX+x,endY+y);
    }
  }
  
  // ---------    DRAW FILLED helix SHAPE, -----------    //

  public static function fillHelix(mc:MovieClip, thick:Number, color:Number, fill:Number, r:Number,x:Number,y:Number,styleMaker:Number){
    mc.moveTo(x+r,y);
    mc.lineStyle(thick, color);
    mc.beginFill(fill);
    var style:Number = Math.tan(styleMaker*Math.PI/180);
    for (var angle:Number=45;angle<=360;angle+=45){
      var endX:Number = r * Math.cos(angle*Math.PI/180);
      var endY:Number = r * Math.sin(angle*Math.PI/180);
      var cX:Number   = endX + r* style * Math.cos((angle-90)*Math.PI/180);
      var cY:Number   = endY + r* style * Math.sin((angle-90)*Math.PI/180);
      mc.curveTo(cX+x,cY+y,endX+x,endY+y);
    }
    mc.endFill();
  }
  
  //      --------------  DRAW GRADIENT SHAPE     --------------  //      

  public static function drawGradientShape(mc:MovieClip, thick:Number, color:Number, r:Number,x:Number,y:Number,styleMaker:Number,
      col1:Number,col2:Number,fa1:Number,fa2:Number,
      matrixX:Number,matrixY:Number,matrixW:Number,
      matrixH:Number){
    mc.lineStyle(thick, color);
    mc.moveTo(x+r,y);
    var colors:Array = [col1 ,col2];
    var alphas:Array = [ fa1, fa2 ];
    var ratios:Array = [ 7, 0xFF ];
    var matrix:Object = { matrixType:"box", x:matrixX, 
      y:matrixY, w:matrixW, h:matrixH,
      r:(45/180)*Math.PI };
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    var style:Number = Math.tan(styleMaker*Math.PI/180);
    for (var angle:Number=45;angle<=360;angle+=45){
      var endX:Number = r * Math.cos(angle*Math.PI/180);
      var endY:Number = r * Math.sin(angle*Math.PI/180);
      var cX:Number   = endX + r* style * Math.cos((angle-90)*Math.PI/180);
      var cY:Number   = endY + r* style * Math.sin((angle-90)*Math.PI/180);
      mc.curveTo(cX+x,cY+y,endX+x,endY+y);
    }
    mc.endFill();
  }

  //      -----------             DRAW HEXAGON    ----------      //

  public static function drawHexagon(mc:MovieClip, thick:Number, color:Number, hexRadius:Number, startX:Number, startY:Number){
    var sideC:Number=hexRadius;
    var sideA:Number = 0.5 * sideC;
    var sideB:Number=Math.sqrt((hexRadius*hexRadius)
                                     - (0.5*hexRadius)* (0.5*hexRadius));
    mc.lineStyle(thick,color,100);
    mc.moveTo(startX,startY);
    mc.lineTo(startX,sideC+ startY);
    mc.lineTo(sideB+startX,startY+sideA+sideC);             // bottom point
    mc.lineTo(2*sideB + startX , startY + sideC);
    mc.lineTo(2*sideB + startX , startY);
    mc.lineTo(sideB + startX, startY - sideA);
    mc.lineTo(startX, startY);
  };


  public static function fillHexagon(mc:MovieClip, thick:Number, color:Number, fill:Number, hexRadius:Number, startX:Number, startY:Number){
    var sideC:Number=hexRadius;
    var sideA:Number = 0.5 * sideC;
    var sideB:Number=Math.sqrt((hexRadius*hexRadius) 
                                    - (0.5*hexRadius)* (0.5*hexRadius));
    mc.lineStyle(thick,color,100);
    mc.beginFill(fill);
    mc.moveTo(startX,startY);
    mc.lineTo(startX,sideC+ startY);
    mc.lineTo(sideB+startX,startY+sideA+sideC);             // bottom point
    mc.lineTo(2*sideB + startX , startY + sideC);
    mc.lineTo(2*sideB + startX , startY);
    mc.lineTo(sideB + startX, startY - sideA);
    mc.lineTo(startX, startY);
    mc.endFill();
  };  
  

/////////////////////////////////////////////////////////////////////////////
// GRADIENT METHODS
/////////////////////////////////////////////////////////////////////////////

  public static function drawExampleGradient(mc:MovieClip) {
	  drawTestLineGradient(mc, 50, 100, 50, 250);
  }

  public static function drawTestLineGradient(mc:MovieClip, x1:Number, x2:Number, y1:Number, y2:Number) {
	  var w1:Number = x2 - x1;
	  var h1:Number = y2 - y1;
	 //trace("x1=" + x1 + ",x2=" + x2 + "y1=" + y1 + ",y2=" + y2 + "w1=" + w1 + ",h1=" + h1)
    var colors:Array = [0xFF0000,0xFFFF00,0x00FF00,0x00FFFF,0x0000FF,0xFF00FF];
    var alphas:Array = [100,100,100,100,100,100];
    var ratios:Array = [0x0,0x33,0x66,0x99,0xCC,0xFF];
    var radians:Number = getRadians(x1, x2, y1, y2);
    var matrix:Object = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians };
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    mc.lineStyle(undefined, 0, 100);
    mc.moveTo(x1,y1);
    mc.moveTo(x1+1,y1+1);
    mc.lineTo(x2+1,y2+1);
    mc.lineTo(x2,y2);
    mc.lineTo(x1,y1);
    mc.endFill();
  }
/*
  public static function drawTestGradient(mc:MovieClip, x1:Number, x2:Number, y1:Number, y2:Number) {
	  var w1:Number = x2 - x1;
	  var h1:Number = y2 - y1;
    // EXAMPLE GRADIENT
    var colors:Array = [0xFF0000,0xFFFF00,0x00FF00,0x00FFFF,0x0000FF,0xFF00FF];
    // all of the colors should be opaque
    var alphas:Array = [100,100,100,100,100,100];
    // these ratios are in hexadeciaml, in even steps from 0 to 255
    var ratios:Array = [0x0,0x33,0x66,0x99,0xCC,0xFF];
    // 0 radians is the equivalent of no rotation for the gradient
//    var radians = getRadiansByDegrees(0);
    var radians:Number = getRadians(x1, x2, y1, y2);
    // build our matrix using the "box" method
    var matrix = { matrixType:"box", x:x1, y:y1, w:w1, h:h1, r: radians }
    // put all that together in the beginGradientFill
    beginLinearGradientFill(mc,colors,alphas,ratios,matrix);
    // draw the bounding box
    mc.moveTo(x1,y1);
    mc.lineTo(x2,y1);
    mc.lineTo(x2,y2);
    mc.lineTo(x1,y2);
    mc.lineTo(x1,y1);
    // close up the fill
    mc.endFill();
    drawLine(mc, lineColor, x1, x2, y1, y2);
  }*/
  
  
  public static function drawRoundedRect(mc:MovieClip, x:Number, y:Number, w:Number, h:Number, cornerRadius:Number) {
  	// ==============
  	// mc.drawRect() - by Ric Ewing (ric@formequalsfunction.com) - version 1.1 - 4.7.2002
  	// 
  	// x, y = top left corner of rect
  	// w = width of rect
  	// h = height of rect
  	// cornerRadius = [optional] radius of rounding for corners (defaults to 0)
  	// ==============
  	if (arguments.length<4) {
  		return;
  	}
  	// if the user has defined cornerRadius our task is a bit more complex. :)
  	if (cornerRadius>0) {
  		// init vars
  		var theta:Number, angle:Number, cx:Number, cy:Number, px:Number, py:Number;
  		// make sure that w + h are larger than 2*cornerRadius
  		if (cornerRadius>Math.min(w, h)/2) {
  			cornerRadius = Math.min(w, h)/2;
  		}
  		// theta = 45 degrees in radians
  		theta = Math.PI/4;
  		// draw top line
  		mc.moveTo(x+cornerRadius, y);
  		mc.lineTo(x+w-cornerRadius, y);
  		//angle is currently 90 degrees
  		angle = -Math.PI/2;
  		// draw tr corner in two parts
  		cx = x+w-cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+w-cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		angle += theta;
  		cx = x+w-cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+w-cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		// draw right line
  		mc.lineTo(x+w, y+h-cornerRadius);
  		// draw br corner
  		angle += theta;
  		cx = x+w-cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+h-cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+w-cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+h-cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		angle += theta;
  		cx = x+w-cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+h-cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+w-cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+h-cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		// draw bottom line
  		mc.lineTo(x+cornerRadius, y+h);
  		// draw bl corner
  		angle += theta;
  		cx = x+cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+h-cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+h-cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		angle += theta;
  		cx = x+cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+h-cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+h-cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		// draw left line
  		mc.lineTo(x, y+cornerRadius);
  		// draw tl corner
  		angle += theta;
  		cx = x+cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  		angle += theta;
  		cx = x+cornerRadius+(Math.cos(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		cy = y+cornerRadius+(Math.sin(angle+(theta/2))*cornerRadius/Math.cos(theta/2));
  		px = x+cornerRadius+(Math.cos(angle+theta)*cornerRadius);
  		py = y+cornerRadius+(Math.sin(angle+theta)*cornerRadius);
  		mc.curveTo(cx, cy, px, py);
  	} else {
  		// cornerRadius was not defined or = 0. This makes it easy.
  		mc.moveTo(x, y);
  		mc.lineTo(x+w, y);
  		mc.lineTo(x+w, y+h);
  		mc.lineTo(x, y+h);
  		mc.lineTo(x, y);
  	}
  }


  /////////////////////////////////////////////////////////////////////////////
  // RADIAN METHODS
  /////////////////////////////////////////////////////////////////////////////

  public static function getRadiansByDegrees(degrees:Number):Number {
    // To calculate a radian value, use this formula:
    // radian = Math.PI/180 * degree
    return Math.PI/180 * degrees;
  }

  public static function getRadians(x1:Number, x2:Number, y1:Number, y2:Number):Number {
	  var x_base:Number   = x2-x1;
	  var y_height:Number = y2-y1;
	  if (x_base == 0) {
  		if (y_height > 0) {
   	    return getRadiansByDegrees(90);
   	  }
      return getRadiansByDegrees(270);
	  }
	  if (y_height == 0) {
		  if (x_base > 0) {
        return getRadiansByDegrees(180);
      }
 	    return getRadiansByDegrees(0);
	  }
    // The return value represents the opposite angle of a right triangle in radians
    // where x is the adjacent side length and y is the opposite side length.
    return Math.atan2(  x_base, y_height  ); 
  }

  public static function getAngleAdjacentRadians(base:Number, height:Number):Number {
    // The return value represents the opposite angle of a right triangle in radians
    // where x is the adjacent side length and y is the opposite side length.
    return Math.atan2(  height, base  ); 
  }

  public static function getAngleOppositeRadians(base:Number, height:Number):Number {
    // The return value represents the opposite angle of a right triangle in radians
    // where x is the adjacent side length and y is the opposite side length.
    return Math.atan2(  base, height  ); 
  }

 /**
  * The following methods are the new draw methods.  
  * The methods above this are being phased out.
  */

  ///////////////////////////////////////////
  // BASIC DRAWING METHODS

  //POINTS

    //TODO find out if there is a way to draw a pixel other than doing a 1 pixel solid fill
    //TODO also find out if there is a way to get the effing rectangle to draw its own bottom-right corner.
    public static function drawPoint(mc:MovieClip, x:Number, y:Number, color:Number){
      solidRect(mc, x, y, 1, 1, color);
    }

    public static function drawPointWithAlpha(mc:MovieClip, x:Number, y:Number, color:Number, alpha:Number){
      solidRectWithAlpha(mc, x, y, 1, 1, color, alpha);
    }

    static var DEFAULT_LINE_THICKNESS:Number = 1;
    static var DEFAULT_ALPHA:Number = 100;

  //LINES


    public static function drawLine(mc:MovieClip, startX:Number, startY:Number, endX:Number, endY:Number, color:Number){
      drawLineWithAlpha(mc, startX, startY, endX, endY, color, DEFAULT_ALPHA);
    }

    public static function drawLineWithThickness(mc:MovieClip, startX:Number, startY:Number, endX:Number, endY:Number, color:Number, thickness:Number){
      drawLineWithAlphaThickness(mc, startX, startY, endX, endY, color, DEFAULT_ALPHA, thickness);
    }

    public static function drawLineWithAlpha(mc:MovieClip, startX:Number, startY:Number, endX:Number, endY:Number, color:Number, alpha:Number){
      drawLineWithAlphaThickness(mc, startX, startY, endX, endY, color, alpha, DEFAULT_LINE_THICKNESS);
    }

    public static function drawLineWithAlphaThickness(mc:MovieClip, startX:Number, startY:Number, endX:Number, endY:Number, color:Number, alpha:Number, thickness:Number){
      mc.lineStyle(DEFAULT_LINE_THICKNESS, color, alpha);
      mc.moveTo( startX,  startY);
      mc.lineTo(   endX,    endY);
    }

    public static function drawLineWithPoint(mc:MovieClip, start:NSPoint, end:NSPoint, color:Number){
      drawLineWithAlpha(mc, start.x, start.y, end.x, end.y, color, DEFAULT_ALPHA);
    }

    public static function drawLineWithAlphaPoint(mc:MovieClip, start:NSPoint, end:NSPoint, color:Number, alpha:Number){
      drawLineWithAlpha(mc, start.x, start.y, end.x, end.y, color, alpha);
    }

    //used to fix bad diagonal line drawing. draws a line using a fill, for precise pixels and colors.
    public static function drawFillLine(mc:MovieClip, startX:Number, startY:Number, endX:Number, endY:Number, color:Number){
      drawLineSimple(mc, color, startX, endX, startY, endY);
    }

  //SHAPES

    public static function drawShape(mc:MovieClip, xyArrays:Array, color:Number)
    {
       //NSPoint.ZeroPoint doesn't seem to work. why'
      drawShapeWithOrigin(mc, xyArrays, color, new NSPoint(0,0));
    }

    public static function drawShapeWithOrigin(mc:MovieClip, xyArrays:Array, color:Number, origin:NSPoint)
    {
      mc.lineStyle(DEFAULT_LINE_THICKNESS, color, 100);
      drawShapeShared(mc, xyArrays,origin);
    }

    public static function fillShape(mc:MovieClip, xyArrays:Array, color:Number)
    {
      fillShapeWithOrigin(mc, xyArrays, color, new NSPoint(0,0));
    }

    public static function fillShapeWithOrigin(mc:MovieClip, xyArrays:Array, color:Number, origin:NSPoint)
    {
      mc.lineStyle(1, color, 100);
      mc.beginFill(color,100);
      drawShapeShared(mc, xyArrays, origin);
      mc.endFill();
    }

    public static function fillShapeWithoutBorder(mc:MovieClip, xyArrays:Array, color:Number)
    {
      fillShapeWithoutBorderWithOrigin(mc, xyArrays, color, new NSPoint(0,0));
    }

    public static function fillShapeWithoutBorderWithOrigin(mc:MovieClip, xyArrays:Array, color:Number, origin:NSPoint)
    {
      mc.lineStyle(undefined, 0, 100);
      mc.beginFill(color,100);
      drawShapeShared(mc, xyArrays, origin);
      mc.endFill();
    }

    private static function drawShapeShared(mc:MovieClip, xyArrays:Array, origin:NSPoint)
    {
      var startX:Number = xyArrays[0][0];
      var startY:Number = xyArrays[0][1];
      mc.moveTo(startX+origin.x,startY+origin.y);
      for (var i:Number = 1; i < xyArrays.length; i++) 
      {
        var x:Number = xyArrays[i][0] + origin.x;
        var y:Number = xyArrays[i][1] + origin.y;
        mc.lineTo(x,y);
      }
      mc.lineTo(startX+origin.x,startY+origin.y);
    }

  // END BASIC DRAWING METHODS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // OUTLINE RECT METHODS
  
    public static function outlineRectWithRectExcludingRect(mc:MovieClip, rect:NSRect, exclude:NSRect, colors:Array) {
      var x:Number = rect.origin.x;
      var y:Number = rect.origin.y;
      var width:Number = rect.size.width;
      var height:Number = rect.size.height;
      colors = getArrayOfFour(colors);
      var alphas:Array = buildArray(colors.length, 100);
      
      var iRect:NSRect = rect.intersectionRect(exclude);
      var excludeTop:Boolean = true;
      if (iRect.maxY() == rect.maxY()) {
        excludeTop = false;
      }

      //change width and height so that the total width/height, including line thickness is the given width/height.
      var x2:Number = x + width  -1;
      var y2:Number = y + height -1;
      var lineThickness:Number = 1;

      mc.lineStyle(lineThickness, colors[0], alphas[0]);
      mc.moveTo( x,  y);
      if (excludeTop) {
        mc.lineTo(iRect.minX(), y);
        mc.moveTo(iRect.maxX(), y);
      }
      mc.lineTo(x2,  y);

      //TODO Why the eff won't the bottom right pixel draw?
      mc.lineStyle(lineThickness, colors[1], alphas[1]);
      mc.lineTo(x2, y2);


      mc.lineStyle(lineThickness, colors[2], alphas[2]);
      if (!excludeTop) {
        mc.lineTo(iRect.maxX(), y2);
        mc.moveTo(iRect.minX(), y2);
      }
      mc.lineTo( x, y2);

      mc.lineStyle(lineThickness, colors[3], alphas[3]);
      mc.lineTo( x,  y);

      // need to draw the bottom right pixel separately for some reason.
      // I can't get any line to draw there, so I'm using the 'pixel' method, which is actually a fill.

      drawPointWithAlpha(mc, x2, y2, colors[1], alphas[1]);


    }
  
    public static function outlineRectWithRect(mc:MovieClip, rect:NSRect, colors:Array, ratios:Array){
      outlineRect(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, colors);
    }
   
    public static function outlineRectWithAlphaRect(mc:MovieClip, rect:NSRect, colors:Array, alphas:Array){
      outlineRectWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, colors, alphas);
    }

    public static function outlineRect(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, colors:Array){
      var alphas:Array = buildArray(colors.length, 100);
      outlineRectWithAlpha(mc, x, y, width, height, colors, alphas);
    }
   
    public static function outlineRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, colors:Array, alphas:Array){
  //    beginLinearGradientFill(mc,colors,alphas,actualRatios,matrix);
      
      colors = getArrayOfFour(colors);
      alphas = getArrayOfFour(alphas);
      
      //change width and height so that the total width/height, including line thickness is the given width/height.
      var x2:Number = x + width  -1;
      var y2:Number = y + height -1;
      var lineThickness:Number = 1;
    
      mc.lineStyle(lineThickness, colors[0], alphas[0]);
      mc.moveTo( x,  y);
      mc.lineTo(x2,  y);

  //TODO Why the eff won't the bottom right pixel draw?
      mc.lineStyle(lineThickness, colors[1], alphas[1]);
      mc.lineTo(x2, y2);


      mc.lineStyle(lineThickness, colors[2], alphas[2]);
      mc.lineTo( x, y2);

      mc.lineStyle(lineThickness, colors[3], alphas[3]);
      mc.lineTo( x,  y);

  // need to draw the bottom right pixel separately for some reason.
  // I can't get any line to draw there, so I'm using the 'pixel' method, which is actually a fill.

  //trace("DRAW POINT: x2=" + x2 + ", y2=" + y2 + ", color=" + colors[1] + ", alpha=" + alphas[1]);
      
      drawPointWithAlpha(mc, x2, y2, colors[1], alphas[1]);

  //    mc.endFill();
    }
  // END OUTLINE RECT METHODS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // OUTLINE RECT METHODS
    public static function solidRectWithRect(mc:MovieClip, rect:NSRect, color:Number){
      solidRect(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, color);
    }
   
    public static function solidRectWithAlphaRect(mc:MovieClip, rect:NSRect, color:Number, alpha:Number){
      solidRectWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, color, alpha);
    }

    public static function solidRect(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, color:Number){
      var alpha:Number = 100;
      solidRectWithAlpha(mc, x, y, width, height, color, alpha);
    }
   
    public static function solidRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, color:Number, alpha:Number){
    
  //trace("SOLID RECT WITH ALPHA: x=" + x + ", y=" + y + ", width=" + width + ", height=" + height + ", color=" + color + ", alpha=" + alpha);

      mc.lineStyle(undefined, 0, 100);
      mc.beginFill(color,alpha);
      mc.moveTo(x,y);
      mc.lineTo(x+width, y);
      mc.lineTo(x+width, y+height);
      mc.lineTo(x, y+height);
      mc.lineTo(x, y);
      mc.endFill();
    }
  // END SOLID RECT METHODS
  ///////////////////////////////////////////

  ///////////////////////////////////////////
  // CORNER RECT METHODS
  
  //SOLIDS
    public static function solidCornerRectWithRect(mc:MovieClip, rect:NSRect, corner:Number, color:Number){
      solidCornerRect(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, corner, color);
    }
   
    public static function solidCornerRectWithAlphaRect(mc:MovieClip, rect:NSRect, corner:Number, color:Number, alpha:Number){
      solidCornerRectWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, corner, color, alpha);
    }

    public static function solidCornerRect(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, corner:Number, color:Number){
      var alpha:Number = 100;
      solidCornerRectWithAlpha(mc, x, y, width, height, corner, color, alpha);
    }
   
    public static function solidCornerRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, corner:Number, color:Number, alpha:Number){
//      var cornerSize = 1;
      mc.lineStyle(undefined, 0, 100);
      mc.beginFill(color,alpha);
      cornerRectWithAlpha(mc, x, y, width, height, corner);
      mc.endFill();
    }
 
  //OUTLINES
    public static function outlineCornerRectWithRect(mc:MovieClip, rect:NSRect, corner:Number, color:Number){
      outlineCornerRect(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, corner, color);
    }

    public static function outlineCornerRectWithAlphaRect(mc:MovieClip, rect:NSRect, corner:Number, color:Number, alpha:Number){
      outlineCornerRectWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, corner, color, alpha);
    }

    public static function outlineCornerRect(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, corner:Number, color:Number){
      var alpha:Number = 100;
      outlineCornerRectWithAlpha(mc, x, y, width, height, corner, color, alpha);
    }

    public static function outlineCornerRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, corner:Number, color:Number, alpha:Number){
      mc.lineStyle(1, color, alpha);
      cornerRectWithAlpha(mc, x, y, width, height, corner);
    }

    private static function cornerRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, cornerSize:Number){
      mc.moveTo(x+cornerSize      ,y);
      mc.lineTo(x+width-cornerSize,y);
      mc.lineTo(x+width           ,y+cornerSize);
      mc.lineTo(x+width           ,y+height-cornerSize);
      mc.lineTo(x+width-cornerSize,y+height);
      mc.lineTo(x+cornerSize      ,y+height);
      mc.lineTo(x                 ,y+height-cornerSize);
      mc.lineTo(x                 ,y+cornerSize);
      mc.lineTo(x+cornerSize      ,y);
    }

  // END SOLID CORNER RECT METHODS
  ///////////////////////////////////////////
  
  ///////////////////////////////////////////
  // GRADIENT RECT METHODS
  //
  //I think I should make versions of these methods with NSrects instead of x,y,w,h as well.
  //for now naming it 'WithRect' to imply that the gradient should also be a rect
  //TODO decide on a documentation format for these methods.
  //currently using WITH to specify additional params, and then listing params alphabetically. 
  //Maybe that should be the order as well?
  //-gradientRectWithAlpha 
  //this one uses no outline since they are rarely a single color in our skins.
  //this one will also uses no alpha just to keep things simple. for now it's in.
  //this one makes the matrix the same size as the rect, again to be simple.
  //this one takes an angel, a color array and a ratio array to keep things flexible.
  //
    public static function gradientRectWithRect(mc:MovieClip, rect:NSRect, angle:Number, colors:Array, ratios:Array){
      gradientRect(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, angle, colors, ratios);
    }
   
    public static function gradientRectWithAlphaRect(mc:MovieClip, rect:NSRect, angle:Number, colors:Array, ratios:Array, alphas:Array){
      gradientRectWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, angle, colors, ratios, alphas);
    }

    public static function gradientRect(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, 
                                        angle:Number, colors:Array, ratios:Array){
      var alphas:Array = buildArray(colors.length, 100);
      gradientRectWithAlpha(mc, x, y, width, height, angle, colors, ratios, alphas);
    }
   
    public static function gradientRectWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, 
                                        angle:Number, colors:Array, ratios:Array, alphas:Array){
      var radians:Number = getRadiansFromAngle(angle);
      var matrix:Object = getMatrix(new NSRect(x, y, width, height), angle);
      var actualRatios:Array = getActualRatios(ratios);

      mc.lineStyle(undefined, 0, 100);
      beginLinearGradientFill(mc,colors,alphas,actualRatios,matrix);
      mc.moveTo(x,y);
      mc.lineTo(x+width, y);
      mc.lineTo(x+width, y+height);
      mc.lineTo(x, y+height);
      mc.lineTo(x, y);
      mc.endFill();
    }
  // END GRADIENT RECT METHODS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // DRAW ELLIPSE METHODS
  //
    public static function gradientEllipseWithRect(mc:MovieClip, rect:NSRect, colors:Array, ratios:Array){
      gradientEllipse(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, colors, ratios);
    }
   
    public static function gradientEllipseWithAlphaRect(mc:MovieClip, rect:NSRect, colors:Array, ratios:Array, alphas:Array){
      gradientEllipseWithAlpha(mc, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, colors, ratios, alphas);
    }

    public static function gradientEllipse(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, 
                                           colors:Array, ratios:Array){
      var alphas:Array = buildArray(colors.length, 100);
      gradientEllipseWithAlpha(mc, x, y, width, height, colors, ratios, alphas);
    }
   
    //top-left with diameters. not center with radii.
    public static function gradientEllipseWithAlpha(mc:MovieClip, x:Number, y:Number, width:Number, height:Number, 
                                                    colors:Array, ratios:Array, alphas:Array){
      var rect:NSRect = new NSRect(x, y, width, height);
      var matrix:Object = getMatrix(rect);
      var actualRatios:Array = getActualRatios(ratios);

      mc.lineStyle(undefined, 0, 100);
      beginRadialGradientFill(mc,colors,alphas,actualRatios,matrix);
      drawEllipse(mc, x, y, width, height);
      mc.endFill();
    }

    //taken from AcionScript cookbook's DrawingMethods.as (modified the param order)
    //the original used center origin and radius. this one uses top-left origin and width/height.
    public static function drawEllipse(mc:MovieClip, xTopLeft:Number, yTopLeft:Number, width:Number, height:Number) {
      var radiusRect:NSRect = getRadiusRect(new NSRect(xTopLeft, yTopLeft, width, height));
      var x:Number = radiusRect.origin.x;
      var y:Number = radiusRect.origin.y;
      var xRadius:Number = radiusRect.size.width;
      var yRadius:Number = radiusRect.size.height;
      var angleDelta:Number = Math.PI / 4;

  //    trace("xTopLeft[" + xTopLeft + "] yTopLeft[" + yTopLeft + "] width[" +   width + "] height[" +  height + "]");
  //    trace("       x[" +        x + "]        y[" +        y + "] width[" + xRadius + "] height[" + yRadius + "]");

      // Whereas the circle has only one distance to the control point 
      // for each segment, the ellipse has two distances: one that 
      // corresponds to xRadius and another that corresponds to yRadius.
      var xCtrlDist:Number = xRadius/Math.cos(angleDelta/2);
      var yCtrlDist:Number = yRadius/Math.cos(angleDelta/2);
      var rx:Number, ry:Number, ax:Number, ay:Number;
      mc.moveTo(x + xRadius, y);
      var angle:Number = 0;
      for (var i:Number = 0; i < 8; i++) {
        angle += angleDelta;
        rx = x + Math.cos(angle-(angleDelta/2))*(xCtrlDist);
        ry = y + Math.sin(angle-(angleDelta/2))*(yCtrlDist);
        ax = x + Math.cos(angle)*xRadius;
        ay = y + Math.sin(angle)*yRadius;
        mc.curveTo(rx, ry, ax, ay);
    }
  }
  // END DRAW ELLIPSE METHODS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // MISC HELPER FUNCTIONS

  // this helper function builds an array of length four from an array of 1 or 2
  // this is helpful for the various rect methods that use different params for the 4 sides.
    public static function getArrayOfFour(originalArray:Array):Array {

      var array:Array = originalArray;
      var size:Number = originalArray.length;
      if (size == 4){
        //do nothing. this is just to avoid unnecessary checks.
      }
      else if (size == 1){
        array = [originalArray[0], originalArray[0], originalArray[0], originalArray[0]];
      }
      else if (size == 2){
        array = [originalArray[0], originalArray[1], originalArray[1], originalArray[0]];
      }
      return array;
    }

  // END MISC HELPER FUNCTIONS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // GRADIENT HELPER FUNCTIONS

    //This method translate an array of numerical values into the ratio format Flash uses for gradients.
    //Flash requires a ratio be an array of numbers starting with 0 and ending with 255.
    //If those values are already set, then the arry is returned as is, otherwise the numbers are translated to that scale.
    //TODO explain this more.
    public static function getActualRatios(ratios:Array):Array {
      return getActualNumbers(ratios, 0, 255);
    }

    //this actually doesn't make any sense, since alphas don't have to start at 0 and end at 100.
  /*
    public static function getActualAlphas(alphas:Array){
      return getActualNumbers(alphas, 0, 100);
    }
  */

    //This method translate an array of numerical values into the specified format.
    //This method is used by other methods that have specific value requirements for Muber Arrays.
    public static function getActualNumbers(values:Array, minNumber:Number, maxNumber:Number):Array {
      var size:Number = values.length;
      var minValue:Number = values[0];
      var maxValue:Number = values[size-1];
      if (minValue == minNumber && maxValue == maxNumber){
        return values;
      }
      var actualValues:Array = new Array();
  		var value:Number;
  		var actualValue:Number;
  		var offset:Number = minNumber - minValue;
      minValue += offset;
      maxValue += offset;
  		//the idea here is to change the original values to proporionally equivalent values from minValue to maxValue.
  		//all numbers are adjusted so that the first number starts at minValue and the last in maxValue.
  		for (var i:Number = 0; i < size-1; i++){
  		  value = values[i] + offset;
  		  actualValue = (value/maxValue)*(maxNumber);
  			actualValues.push(actualValue);
  			if (TRACE_FLAG)
  			{
  trace("actual numbers: minNumber=" + minNumber + " | maxNumber=" + maxNumber + " | maxNumber=" + maxNumber + 
                     " | original=" + values[i] + " | offset=" + offset + " | new=" + actualValue);
        }
  		}
  		actualValues.push(maxNumber);
      return actualValues;
    }

    public static function buildArray(size:Number, initValue:Number):Array {
      var array:Array = new Array();
  		for (var i:Number = 0; i < size; i++){
  			array.push(initValue);
  		}
      return array;
    }

    public static function getMatrix(rect:NSRect, angle:Number):Object {
      var radians:Number = getRadiansFromAngle(angle);
      var matrix:Object = { matrixType:"box", x:rect.origin.x, y:rect.origin.y, w:rect.size.width, h:rect.size.height, r: radians };
      return matrix;
    }  

    //the rect param is a normal top/left rect, not a radiusRect
    public static function getRadialMatrix(rect:NSRect):Object {
      var width:Number  = rect.size.width;
      var height:Number = rect.size.height;
      var matrix:Object = { matrixType:"box", x:-width/2, y:-height/2, w:width, h:height, r: 0 };
      return matrix;
    }  

    public static function getRadiansFromAngle(angle:Number):Number {
      var radians:Number = angle == 0 ? 0 : (angle/180)*Math.PI;
      return radians;
    }  

  // END GRADIENT HELPER FUNCTIONS
  ///////////////////////////////////////////

  ///////////////////////////////////////////
  // NSPOINT CONVENIENCE FUNCTIONS

    public static function getOffsetPoint(point:NSPoint, dx:Number, dy:Number):NSPoint {
      return new NSPoint(point.x + dx, point.y + dy);
    }
    
  // END NSPOINT CONVENIENCE FUNCTIONS
  ///////////////////////////////////////////


  ///////////////////////////////////////////
  // NSRECT CONVENIENCE FUNCTIONS

    public static function getRadiusRect(rect:NSRect):NSRect {
      var xRadius:Number = rect.size.width/2;
      var yRadius:Number = rect.size.height/2;
      var x:Number = rect.origin.x + xRadius;
      var y:Number = rect.origin.y + yRadius;
      return new NSRect(x, y, xRadius, yRadius);
    }

    //adds a percent of the width to x
    //adds a percent of the height to y
    //sets width to a percent of width
    //sets height to a percent of height
    public static function getScaledPercentRect(rect:NSRect, xPercent:Number, yPercent:Number, widthPercent:Number, heightPercent:Number):NSRect 
    {
      var x:Number = rect.origin.x;
      var y:Number = rect.origin.y;
      var width:Number  = rect.size.width;
      var height:Number = rect.size.height;

      x = x + width*xPercent*.01;
      y = y + height*yPercent*.01;
      height = height*widthPercent*.01;
      width = width*heightPercent*.01;

      var scaledRect:NSRect = new NSRect(x, y, width, height);
      return scaledRect;
    }

    //adds given pixel to x, y, width and height
    public static function getScaledPixelRect(rect:NSRect, xPixel:Number, yPixel:Number, widthPixel:Number, heightPixel:Number):NSRect 
    {
      var x:Number = rect.origin.x;
      var y:Number = rect.origin.y;
      var width:Number  = rect.size.width;
      var height:Number = rect.size.height;

      x = x + xPixel;
      y = y + yPixel;
      width  = width  + widthPixel;
      height = height + heightPixel;

      var scaledRect:NSRect = new NSRect(x, y, width, height);
      return scaledRect;
    }

  // END NSRECT CONVENIENCE FUNCTIONS
  ///////////////////////////////////////////

    public static function beginLinearGradientFill(mc:MovieClip,colors:Array,alphas:Array,ratios:Array,matrix:Object) 
    {  
      beginGradientFill(mc, "linear",colors,alphas,ratios,matrix);
    }

    public static function beginRadialGradientFill(mc:MovieClip,colors:Array,alphas:Array,ratios:Array,matrix:Object) 
    {  
      beginGradientFill(mc, "radial",colors,alphas,ratios,matrix);
    }
    
    //TODO consolidate actualRatios, matrix, etc to here.
    //Initially this is here for the color size check.
    public static function beginGradientFill(mc:MovieClip,gradientType:String, colors:Array,alphas:Array,ratios:Array,matrix:Object) 
    {  
      if (colors.length > 8)
		  {
/*
			  var e:NSException = NSException.exceptionWithNameReasonUserInfo("InvalidArgumentException", 
				  "ASDraw::gradientRectWithAlpha - The color array must have 8 or fewer colors " + 
				  "since Flash seems to incorrectly draw gradients with more than 8 colors. colors=" + colors, 
				  null);
		  	trace(e);
	  		throw e;
*/
        trace("WARNING!!! Flash seems to incorrectly draw gradients with more than 8 colors.");
        trace(" - colors=" + colors);
  		}
      mc.beginGradientFill(gradientType,colors,alphas,ratios,matrix);
    }


  //     EASING FUNCTIONS USEFUL FOR ANIMATIONS
  // Robert Penner - Sept. 2001 - robertpenner.com

  public static function linearTween(t:Number, b:Number, c:Number, d:Number):Number {
          return c*t/d + b;
  };


  // quadratic easing in - accelerating from zero velocity
  public static function easeInQuad(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return c*t*t + b;
  };


  // quadratic easing out - decelerating to zero velocity
  public static function easeOutQuad(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return -c * t*(t-2) + b;
  };



  // quadratic easing in/out - acceleration until halfway, then deceleration
  public static function easeInOutQuad(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return c/2*t*t + b;
          t--;
          return -c/2 * (t*(t-2) - 1) + b;
  };


  // cubic easing in - accelerating from zero velocity
  public static function easeInCubic(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return c*t*t*t + b;
  };



  // cubic easing out - decelerating to zero velocity
  public static function easeOutCubic(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          t--;
          return c*(t*t*t + 1) + b;
  };



  // cubic easing in/out - acceleration until halfway, then deceleration
  public static function easeInOutCubic(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return c/2*t*t*t + b;
          t -= 2;
          return c/2*(t*t*t + 2) + b;
  };


  // quartic easing in - accelerating from zero velocity
  public static function easeInQuart(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return c*t*t*t*t + b;
  };



  // quartic easing out - decelerating to zero velocity
  public static function easeOutQuart(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          t--;
          return -c * (t*t*t*t - 1) + b;
  };



  // quartic easing in/out - acceleration until halfway, then deceleration
  public static function easeInOutQuart(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return c/2*t*t*t*t + b;
          t -= 2;
          return -c/2 * (t*t*t*t - 2) + b;
  };


  // quintic easing in - accelerating from zero velocity
  public static function easeInQuint(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return c*t*t*t*t*t + b;
  };



  // quintic easing out - decelerating to zero velocity
  public static function easeOutQuint(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          t--;
          return c*(t*t*t*t*t + 1) + b;
  };



  // quintic easing in/out - acceleration until halfway, then deceleration
  public static function easeInOutQuint(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return c/2*t*t*t*t*t + b;
          t -= 2;
          return c/2*(t*t*t*t*t + 2) + b;
  };


  // sinusoidal easing in - accelerating from zero velocity
  public static function easeInSine(t:Number, b:Number, c:Number, d:Number):Number {
          return -c * Math.cos(t/d * (Math.PI/2)) + c + b;
  };



  // sinusoidal easing out - decelerating to zero velocity
  public static function easeOutSine(t:Number, b:Number, c:Number, d:Number):Number {
          return c * Math.sin(t/d * (Math.PI/2)) + b;
  };



  // sinusoidal easing in/out - accelerating until halfway, then decelerating
  public static function easeInOutSine(t:Number, b:Number, c:Number, d:Number):Number {
          return -c/2 * (Math.cos(Math.PI*t/d) - 1) + b;
  };



  // exponential easing in - accelerating from zero velocity
  public static function easeInExpo(t:Number, b:Number, c:Number, d:Number):Number {
          return c * Math.pow( 2, 10 * (t/d - 1) ) + b;
  };



  // exponential easing out - decelerating to zero velocity
  public static function easeOutExpo(t:Number, b:Number, c:Number, d:Number):Number {
          return c * ( -Math.pow( 2, -10 * t/d ) + 1 ) + b;
  };



  // exponential easing in/out - accelerating until halfway, then decelerating
  public static function easeInOutExpo(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return c/2 * Math.pow( 2, 10 * (t - 1) ) + b;
          t--;
          return c/2 * ( -Math.pow( 2, -10 * t) + 2 ) + b;
  };


  // circular easing in - accelerating from zero velocity
  public static function easeInCirc(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          return -c * (Math.sqrt(1 - t*t) - 1) + b;
  };



  // circular easing out - decelerating to zero velocity
  public static function easeOutCirc(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d;
          t--;
          return c * Math.sqrt(1 - t*t) + b;
  };



  // circular easing in/out - acceleration until halfway, then deceleration
  public static function easeInOutCirc(t:Number, b:Number, c:Number, d:Number):Number {
          t /= d/2;
          if (t < 1) return -c/2 * (Math.sqrt(1 - t*t) - 1) + b;
          t -= 2;
          return c/2 * (Math.sqrt(1 - t*t) + 1) + b;
  };
}