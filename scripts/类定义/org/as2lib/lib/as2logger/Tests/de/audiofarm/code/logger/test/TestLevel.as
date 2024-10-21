import as2unit.framework.TestCase;

import logging.Level;

class de.audiofarm.code.logger.test.TestLevel extends TestCase
{
   public function TestLevel( methodName:String )
   {
      super( methodName );
   }
      
   public function testCompareLevels()
   {
   		assertTrue("Level.ALL == Level.ALL", Level.ALL == Level.ALL);
   		assertTrue("Level.ALL < Level.FINEST", Level.ALL < Level.FINEST);
   		assertTrue("Level.FINEST < Level.FINER", Level.FINEST < Level.FINER);
   		assertTrue("Level.FINER < Level.CONFIG", Level.FINER < Level.CONFIG);
   		assertTrue("Level.CONFIG < Level.INFO", Level.CONFIG < Level.INFO);
   		assertTrue("Level.INFO < Level.WARNING", Level.INFO < Level.WARNING);
   		assertTrue("Level.WARNING < Level.SEVERE", Level.WARNING < Level.SEVERE);
   		assertTrue("Level.SEVERE < Level.OFF", Level.SEVERE < Level.OFF);   		
   }
} 