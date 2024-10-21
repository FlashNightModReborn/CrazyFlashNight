Log4F 0.8 (c), 14 December 2004
===============================

Thank you for downloading Log4F, a Log4J-style logging framework for Flex
applications. It is based on Ralf Siegel's public domain logging framework found
at http://code.audiofarm.de/Logger/ and adds useful Flex-specific enhancements
including a debug console, instance inspector, etc.

A remote logger integrated with Log4J is coming soon.

Log4F has been released under the Apache 2.0 license.

If you wish to use Log4F unchanged, the files you are interested in are:

LoggingConfig.as - A helper class to assist the integration of Log4F in other
                   applications while keeping the amount of Log4F-related code
                   in those applications to a minimum.

defaultConfig.xml - The configuration file used by LoggingConfig.as.

TestApp.mxml - Example Flex application showing how to use Log4F with the
               LoggingConfig helper class.

The Log4F documentation gives full instructions on how to install Log4F in your
environment and integrate it with your application.  The documentation can be
lauched via index.html in the docs folder and gives further details on the
above.

The content/ directory in the distribution is the full ActionScript and MXML
source for Log4F; the src/ directory in the distribution is the full Java source
for the remote logger.

(c) 2004 Peter Armstrong and Ralf Siegel