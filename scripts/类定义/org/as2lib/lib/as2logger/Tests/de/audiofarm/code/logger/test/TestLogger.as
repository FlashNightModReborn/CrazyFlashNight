import as2unit.framework.TestCase;

import logging.Logger;
import logging.Level;

class de.audiofarm.code.logger.test.TestLogger extends TestCase
{
   public function TestLogger ( methodName:String )
   {
      super( methodName );
   }
   
   public function testCreateLogger()
   {
   		var loggerA1:Logger = Logger.getLogger("a");
   		var loggerA2:Logger = Logger.getLogger("a");
   		
   		assertNotUndefined("First reference to Logger 'a'", loggerA1);
   		assertNotUndefined("Second reference to Logger 'a'", loggerA2);
   		
   		assertNotNull("First reference to Logger 'a'", loggerA1);
   		assertNotNull("Second reference to Logger 'a'", loggerA2);
   		
   		assertEquals("Both should reference the same Logger object", loggerA1, loggerA2);   		
   }   
   
   public function testLookupEmptyHierarchy()
   {
   		var loggerA:Logger = Logger.getLogger("a");
   		loggerA.setLevel(undefined);
   		
   		assertEquals("Default Level", undefined, loggerA.getLevel());
   		assertTrue("Since hierarchy is empty -> log all.", loggerA.isLoggable(Level.ALL));

		// ------------------------------------------------
   		
   		var loggerB:Logger = Logger.getLogger("a.b");
   		loggerB.setLevel(undefined);
   		
   		assertEquals("Default Level", undefined, loggerB.getLevel());
   		assertTrue("Since hierarchy is empty -> log all.", loggerB.isLoggable(Level.ALL));

		// ------------------------------------------------
  
     	var loggerC:Logger = Logger.getLogger("a.b.c");
     	loggerC.setLevel(undefined);
   		
   		assertEquals("Default Level", undefined, loggerC.getLevel());
   		assertTrue("Since hierarchy is empty -> log all.", loggerC.isLoggable(Level.ALL));
   		
		// ------------------------------------------------
   				
       	var loggerD:Logger = Logger.getLogger("a.b.c.d");
       	loggerD.setLevel(undefined);
   		
   		assertEquals("Default Level", undefined, loggerD.getLevel());
   		assertTrue("Since hierarchy is empty -> log all.", loggerD.isLoggable(Level.ALL));
   		
   }
   
   public function testLookupPopulatedHierarchy()
   {
   		var loggerA:Logger = Logger.getLogger("a");
   		
   		loggerA.setLevel(Level.WARNING);
   		assertEquals("Return assigned level.", Level.WARNING, loggerA.getLevel());   		
   		assertTrue("Log assigned level.", loggerA.isLoggable(Level.WARNING));
   		assertFalse("Do not log below assigned level.", loggerA.isLoggable(Level.INFO));
   		
   		// ------------------------------------------------
   		
   		var loggerB:Logger = Logger.getLogger("a.b");
   		assertTrue("Log parent's (a) level.", loggerB.isLoggable(Level.WARNING));
   		assertFalse("Do not log below parent's (a) level.", loggerB.isLoggable(Level.INFO));
   		   		
   		loggerB.setLevel(Level.FINER);   		
   		assertEquals("Return assigned level.", Level.FINER, loggerB.getLevel());   		
   		assertTrue("Log assigned level.", loggerB.isLoggable(Level.FINER));
   		assertFalse("Do not log below assigned level.", loggerB.isLoggable(Level.FINEST));
 
 		// ------------------------------------------------
 
    	var loggerC:Logger = Logger.getLogger("a.b.c");
   		assertTrue("Log parent's (a.b) level.", loggerC.isLoggable(Level.FINER));
   		assertFalse("Do not log below parent's (a.b) level.", loggerC.isLoggable(Level.FINEST));
   		   		
   		loggerC.setLevel(Level.FINEST);   		
   		
   		assertEquals("Return assigned level.", Level.FINEST, loggerC.getLevel());   		
   		assertTrue("Log assigned level.", loggerC.isLoggable(Level.FINEST));
   		assertFalse("Do not log below assigned level.", loggerC.isLoggable(Level.ALL));
   		
   		Logger.getLogger("a.b").setLevel(undefined);
   		Logger.getLogger("a.b.c").setLevel(undefined);
   		
   		assertFalse("Do not log previously assigned level anymore.", loggerC.isLoggable(Level.FINEST));
   		assertFalse("Do not log former parent's level anymore.", loggerC.isLoggable(Level.FINER));
   		assertTrue("Log parent's (a) level.", loggerC.isLoggable(Level.WARNING));
   		assertFalse("Do not log below parent's (a) level.", loggerC.isLoggable(Level.INFO));
  
		// ------------------------------------------------
  
      	var loggerD:Logger = Logger.getLogger("a.b.c.d");
   		assertTrue("Log parent's (a) level.", loggerC.isLoggable(Level.WARNING));
   		assertFalse("Do not log below parent's (a) level.", loggerC.isLoggable(Level.INFO));
   		
   		loggerA.setLevel(Level.SEVERE);
   		
   		assertTrue("Log new parent's (a) level.", loggerC.isLoggable(Level.SEVERE));
   		assertFalse("Do not log below new parent's (a) level.", loggerC.isLoggable(Level.WARNING));
   		
   
  
   }
} 