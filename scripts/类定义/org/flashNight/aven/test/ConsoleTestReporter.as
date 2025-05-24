class org.flashNight.aven.test.ConsoleTestReporter implements org.flashNight.aven.test.TestReporter {
    private var passed:Number;
    private var failed:Number;
    private var skipped:Number;
    private var config:org.flashNight.aven.test.TestConfig;

    public function ConsoleTestReporter(config:org.flashNight.aven.test.TestConfig) {
        this.passed = 0;
        this.failed = 0;
        this.skipped = 0;
        this.config = config;
    }

    public function startSuite(name:String):Void {
        if (!this.config.isMute()) {
            trace("=== Suite: " + name + " ===");
        }
    }

    public function endSuite(name:String):Void {
        if (!this.config.isMute()) {
            trace("=== End of Suite: " + name + " ===");
        }
    }

    public function startTest(description:String):Void {
        if (!this.config.isMute()) {
            trace("Running Test: " + description);
        }
    }

    public function passTest(description:String, time:Number):Void {
        this.passed++;
        if (!this.config.isMute()) {
            trace("[PASS] " + description + " (" + time + "ms)");
        }
    }

    public function failTest(description:String, time:Number, error:Error):Void {
        this.failed++;
        if (!this.config.isMute()) {
            trace("[FAIL] " + description + " (" + time + "ms)");
            trace("  Error: " + error.message);
        }
    }

    public function skipTest(description:String):Void {
        this.skipped++;
        if (!this.config.isMute()) {
            trace("[SKIP] " + description);
        }
    }

    public function generateReport():Void {
        if (!this.config.isMute()) {
            trace("\n=== Test Report ===");
            trace("Passed: " + this.passed);
            trace("Failed: " + this.failed);
            trace("Skipped: " + this.skipped);
            trace("====================");
        }
    }
}
