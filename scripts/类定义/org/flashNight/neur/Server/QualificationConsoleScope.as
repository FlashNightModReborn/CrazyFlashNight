/** Exact test role binding for the candidate's closed console allowlist. */
class org.flashNight.neur.Server.QualificationConsoleScope {
    public static function allows(slot:String,command:String,active:String,origin:String):Boolean {
        if(slot!=="cf7_agent_review1110" && slot!=="cf7_agent_i2051110")return false;
        if(active===slot)return true;
        return origin===slot && String(active).indexOf("bookrun_")===0
            && (command.indexOf("#get:")===0 || command.indexOf("#eval:")===0);
    }
}
