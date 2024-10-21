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
 
/**
 * An NSColor object represents a color, which is defined in a color space,
 * each point of which has a set of components (such as red, green, and blue)
 * that uniquely define a color.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSColor extends org.actionstep.NSObject
{
	private static var MODE_RGB:Number	= 0;
	private static var MODE_HSB:Number	= 1;
	private static var MODE_CMYK:Number	= 2;
	
	private var m_mode:Number;
	
	/** The opacity of the color. (0.0 to 1.0) */
	private var m_alpha:Number;
	
	//
	// Red Green Blue RGB Color Space (all values between 0.0 and 1.0)
	//
	private var m_red:Number;
	private var m_green:Number;
	private var m_blue:Number;
	
	//
	// Hue Saturation Brightness (HSB) color space (all values between 0.0 and 1.0)
	//
	private var m_hue:Number;
	private var m_saturation:Number;
	private var m_brightness:Number;
		
	public var value:Number; // set to hex
	
	/**These constants are the standard gray values for the 2-bit deep grayscale color space.*/
	public static var NSWhite:NSColor = new NSColor(0xFFFFFF);
	public static var NSLightGray:NSColor = new NSColor(0xAAAAAA);
	public static var NSDarkGray:NSColor = new NSColor(0x666666);
	public static var NSBlack:NSColor = new NSColor(0x000000);
	
	private static var g_systemFontColor:NSColor;
	
	public static function systemFontColor():NSColor {
	  if (g_systemFontColor == undefined) {
	    return NSBlack;
	  }
	  return g_systemFontColor;
	}
	
	public static function setSystemFontColor(color:NSColor) {
	  g_systemFontColor = color;
	}
	
	/**
	 * Creates a new instance of NSColor.
	 */
	public function NSColor(value:Number)
	{
		this.value = value;
		
		init();
	}
	
	/**
	 * Initializes the color.
	 */
	private function init():Void
	{
		m_alpha = 1;
		calculateRGBAFromValue();
		calculateHSBFromRGB();
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * Returns the receiver's alpha (opacity) component. Returns 1.0 (opaque)
	 * if the receiver has no alpha component.
	 */
	public function alphaComponent():Number
	{
		return m_alpha;
	}
	

	/**
	 * @see org.actionstep.NSObject#description()
	 */
	public function description():String
	{
		return "NSColor(" +
			"value=" + value + ", " +
			"red=" + m_red + ", " +
			"blue=" + m_blue + ", " +
			"green=" + m_green + ", " +
			"alpha=" + m_alpha + ", " +
			"hue=" + m_hue + ", " +
			"brightness=" + m_brightness + ", " +
			"saturation=" + m_saturation  +
			")";
	}

	//******************************************************															 
	//*                 RGB Properties
	//******************************************************
	
	/**
	 * Returns the receiver�s blue component. Raises an exception if the
	 * receiver isn�t an RGB color.
	 */
	public function blueComponent():Number
	{
		return m_blue;
	}


	/**
	 * Returns the receiver�s green component. Raises an exception if the
	 * receiver isn�t an RGB color.
	 */
	public function greenComponent():Number
	{
		return m_green;
	}
	
	
	/**
	 * Returns the receiver�s red component. Raises an exception if the
	 * receiver isn�t an RGB color.
	 */
	public function redComponent():Number
	{
		return m_red;
	}
	
	//******************************************************															 
	//*                   HSB Properties
	//******************************************************
		
	/**
	 * Returns the receiver�s brightness component. Raises an exception if the
	 * receiver isn�t an HSB color.
	 */
	public function brightnessComponent():Number
	{
		return m_brightness;
	}


	/**
	 * Returns the receiver�s hue component. Raises an exception if the
	 * receiver isn�t an HSB color.
	 */
	public function hueComponent():Number
	{
		return m_hue;
	}
	
	
	/**
	 * Returns the receiver�s red component. Raises an exception if the
	 * receiver isn�t an HSB color.
	 */
	public function saturationComponent():Number
	{
		return m_saturation;
	}
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Returns a hexidecimal representation of the color.
	 */
	public function toHex():Number
	{
		return ((m_red * 255) << 16 | (m_green * 255) << 8 | (m_blue * 255));
	}
	
	
	//******************************************************															 
	//*                 Private Methods
	//******************************************************
	
	private function calculateRGBAFromValue():Void
	{
		m_red 	= ((value & 0xFF0000) >> 16) / 255;
		m_green = ((value & 0x00FF00) >> 8) / 255;
		m_blue 	= (value & 0x0000FF) / 255;
	}
	
	private function calculateHSBFromRGB():Void
	{
		var h:Number = 0, s:Number, b:Number, min:Number;
		var r:Number = m_red * 255, g:Number = m_green * 255, 
			bl:Number = m_blue * 255;
	
		//
		// Calculate brightness and saturation
		//
		min = Math.min(Math.min(r, g), bl);
		b = Math.max(Math.max(r, g), bl);		
		s = (b <= 0) ? 0 : Math.round(100 * (b - min) / b);
		b = Math.round((b / 255) * 100);
		
		//
		// Calculate hue
		//				
		if ((r == g) && (g == bl))  
			h = 0;
		else if (r >= g && g >= bl) 
			h = 60 * (g - bl) / (r - bl);
		else if (g >= r && r >= bl) 
			h = 60 + 60 * (g - r) / (g - bl);
		else if (g >= bl && bl >= r) 
			h = 120 + 60 * (bl - r) / (g - r);
		else if (bl >= g && g >= r) 
			h = 180 + 60 * (bl - g) / (bl - r);
		else if (bl >= r && r >= g) 
			h = 240 + 60 * (r - g) / (bl - g);
		else if (r >= bl && bl >= g) 
			h = 300 + 60 * (r - bl) / (r - g);
		else 
			h = 0;
			
		h = Math.round(h);
		
		//
		// Set values
		//
		m_hue = h / 360;
		m_saturation = s / 100;
		m_brightness = b / 100;
	}
	
	//******************************************************															 
	//*                 Class Constructors
	//******************************************************	
	
	public static function colorWithHexValueAlpha(hexValue:Number, alpha:Number):NSColor {
	  var c:NSColor = new NSColor(hexValue);
	  c.m_alpha = alpha;
	  return c;
	}
	
	/**
	 * Creates and returns an NSColor whose opacity value is alpha and whose
	 * RGB components are red, green, and blue. (Values below 0.0 are
	 * interpreted as 0.0, and values above 1.0 are interpreted as 1.0.)
	 */
	public static function colorWithCalibratedRedGreenBlueAlpha(red:Number, 
		green:Number, blue:Number, alpha:Number):NSColor
	{
		//
		// Deal with out of range values
		//
		if (red > 1)
			red = 1;
		else if (red < 0)
			red = 0;
			
		if (green > 1)
			green = 1;
		else if (green < 0)
			green = 0;
			
		if (blue > 1)
			blue = 1;
		else if (blue < 0)
			blue = 0;
			
		if (alpha > 1)
			alpha = 1;
		else if (alpha < 0)
			alpha = 0;
			
		//
		// Create an return color.
		//
		var c:NSColor = new NSColor();
		c.m_red = red;
		c.m_green = green;
		c.m_blue = blue;
		c.m_alpha = alpha;
		c.value = c.toHex();
		c.calculateHSBFromRGB();
		
		return c;
	}
  
  
	/**
	 * Creates and returns an NSColor whose opacity value is alpha and whose
	 * grayscale value is white. (Values below 0.0 are interpreted as 0.0, and
	 * values above 1.0 are interpreted as 1.0.)
	 */
	public static function colorWithCalibratedWhiteAlpha(white:Number, alpha:Number):NSColor
	{
		//
		// Deal with out of range values.
		//
		if (white > 1)
			white = 1;
		else if (white < 0)
			white = 0;
			
		if (alpha > 1)
			alpha = 1;
		else if (alpha < 0)
			alpha = 0;
			
		//
		// Create an return color.
		//
		var c:NSColor = new NSColor();
		c.m_red = white;
		c.m_green = white;
		c.m_blue = white;
		c.m_alpha = alpha;
		c.value = c.toHex();
		c.calculateHSBFromRGB();
		
		return c;		
	}
}