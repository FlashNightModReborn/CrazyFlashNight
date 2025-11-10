// Test script for NPC Dialogue Loader
import org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader;
import org.flashNight.gesh.object.ObjectUtil;

trace("=== Testing NPC Dialogue Loader ===");

// Get the loader instance
var npcLoader:NpcDialogueLoader = NpcDialogueLoader.getInstance();

// Test loading the NPC dialogues
npcLoader.loadNpcDialogues(
    function(data:Object):Void {
        trace("✓ NPC dialogues loaded successfully!");

        // Count and list NPCs
        var npcCount:Number = 0;
        var npcNames:Array = [];

        for (var npcName:String in data) {
            if (data.hasOwnProperty(npcName)) {
                npcCount++;
                npcNames.push(npcName);
            }
        }

        trace("Total NPCs loaded: " + npcCount);
        trace("NPC Names: " + npcNames.join(", "));

        // Test specific NPCs
        if (data["Andy Law"]) {
            trace("✓ Andy Law dialogues found: " + data["Andy Law"].length + " dialogue sets");
        } else {
            trace("✗ Andy Law dialogues not found!");
        }

        if (data["The Girl"]) {
            trace("✓ The Girl dialogues found: " + data["The Girl"].length + " dialogue sets");
        } else {
            trace("✗ The Girl dialogues not found!");
        }

        if (data["Shop Girl"]) {
            trace("✓ Shop Girl dialogues found: " + data["Shop Girl"].length + " dialogue sets");
        } else {
            trace("✗ Shop Girl dialogues not found!");
        }

        // Verify data structure matches original format
        trace("\n=== Data Structure Test ===");
        for (var testNpc:String in data) {
            if (data.hasOwnProperty(testNpc)) {
                var dialogueArray:Array = data[testNpc];
                if (dialogueArray && dialogueArray.length > 0) {
                    var firstDialogue:Object = dialogueArray[0];
                    trace("NPC: " + testNpc);
                    trace("  - Has " + dialogueArray.length + " dialogue entries");
                    if (firstDialogue.TaskRequirement != undefined) {
                        trace("  - Has TaskRequirement field");
                    }
                    if (firstDialogue.Dialogue != undefined) {
                        trace("  - Has Dialogue field");
                    }
                    break; // Just test one NPC
                }
            }
        }

        trace("\n✓ All tests completed successfully!");
    },
    function():Void {
        trace("✗ Failed to load NPC dialogues!");
    }
);