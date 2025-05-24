class org.flashNight.aven.test.TestConfig {
    private var debug:Boolean;
    private var repeat:Number;
    private var mute:Boolean;
    private var enabledTags:Array;
    private var disabledTags:Array;

    public function TestConfig(debug:Boolean, repeat:Number, mute:Boolean, enabledTags:Array, disabledTags:Array) {
        this.debug = debug;
        this.repeat = repeat != null ? repeat : 1;
        this.mute = mute;
        this.enabledTags = enabledTags != null ? enabledTags : [];
        this.disabledTags = disabledTags != null ? disabledTags : [];
    }

    public function isDebug():Boolean {
        return this.debug;
    }

    public function getRepeat():Number {
        return this.repeat;
    }

    public function isMute():Boolean {
        return this.mute;
    }

    public function shouldSkipTest(testCase:org.flashNight.aven.test.TestCase):Boolean {
        var tags:Array = testCase.getTags();
        if (this.enabledTags.length > 0) {
            var hasEnabledTag:Boolean = false;
            for (var i:Number = 0; i < this.enabledTags.length; i++) {
                if (tags.indexOf(this.enabledTags[i]) != -1) {
                    hasEnabledTag = true;
                    break;
                }
            }
            if (!hasEnabledTag) {
                return true;
            }
        }
        for (var j:Number = 0; j < this.disabledTags.length; j++) {
            if (tags.indexOf(this.disabledTags[j]) != -1) {
                return true;
            }
        }
        return false;
    }
}
