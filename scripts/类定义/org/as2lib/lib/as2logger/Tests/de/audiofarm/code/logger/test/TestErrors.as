import as2unit.framework.TestCase;

import logging.*;
import logging.errors.*;

class de.audiofarm.code.logger.test.TestErrors extends TestCase
{
   public function TestErrors( methodName:String )
   {
      super( methodName );
   }
      
   public function testThrowInvalidLevelError()
   {
     	var errorThrown:Boolean = false;
     	
   		try {		
			var level:Level = Level.forName("ALL");
		} catch (e:logging.errors.InvalidLevelError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( errorThrown ) {
			fail("No " + errorName + " should have been thrown");
		}
		
		assertTrue("level == Level.ALL", level == Level.ALL);
     	
   		try {		
			var level:Level = Level.forName("GARBAGE");
		} catch (e:logging.errors.InvalidLevelError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( !errorThrown ) {
			fail("An Error should have been thrown");
		}
   }
   
   public function testThrowInvalidFormatterError()
   {
     	var errorThrown:Boolean = false;
     	
		try {
			var formatter:IFormatter = LogManager.createFormatterByName("logging.IFormatter");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFormatterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( errorThrown ) {
			fail("No " + errorName + " should have been thrown");
		}
		
		assertTrue("formatter instanceof logging.IFormatter", formatter instanceof logging.IFormatter);
     	
		try {
			var formatter:IFormatter = LogManager.createFormatterByName("GARFIELD");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFormatterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( !errorThrown ) {
			fail("An Error should have been thrown");
		}
   }
   
   public function testThrowInvalidFilterError()
   {
     	var errorThrown:Boolean = false;
     	
		try {
			var filter:IFilter = LogManager.createFilterByName("logging.IFilter");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFilterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( errorThrown ) {
			fail("No " + errorName + " should have been thrown");
		}
		
		assertTrue("filter instanceof logging.IFilter", filter instanceof logging.IFilter);
     	
		try {
			var filter:IFilter = LogManager.createFilterByName("COFFEE");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFilterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( !errorThrown ) {
			fail("An Error should have been thrown");
		}
   }
   
   public function testThrowInvalidPublisherError()
   {
     	var errorThrown:Boolean = false;
     	
		try {
			var publisher:IPublisher = LogManager.createPublisherByName("logging.IPublisher");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFilterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( errorThrown ) {
			fail("No " + errorName + " should have been thrown");
		}
		
		assertTrue("publisher instanceof logging.IPublisher", publisher instanceof logging.IPublisher);
     	
		try {
			var publisher:IPublisher = LogManager.createPublisherByName("MAGAZINE");
		} catch (e:logging.errors.ClassNotFoundError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.InvalidFilterError) {
			errorThrown = true;
			var errorName = e.name;
		} catch (e:logging.errors.IllegalArgumentError) {
			errorThrown = true;
			var errorName = e.name;
		}
		
		if ( !errorThrown ) {
			fail("An Error should have been thrown");
		}
   }
} 