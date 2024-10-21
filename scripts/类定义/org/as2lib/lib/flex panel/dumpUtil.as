// Dump Utility
// by Dirk Eismann, feel free to use this code :)
//
// uses the Standalone Central Trace Panel by Mike Chambers
// see http://www.markme.com/mesh/archives/003850.cfm for details
//
// Usage: simple include this script into your MXML-document
//        calling dump() sends its parameter via a LocalConnection
//        to the Trace Panel and outputs it

// the LocalConnection used as a sender
var sender:LocalConnection = null;

function initSender() {
	// create a new instance
	sender = new LocalConnection();
}

function dump(val:Object) {
	if (sender == null) initSender();
	// simply send the passed object over the wire - that's it :)
	sender.send("_tracer", "onMessage", val);
}
