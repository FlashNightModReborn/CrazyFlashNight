/** 无损数值池、线性矩阵池和姿态差分；只在首次读取时解码一次。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.NamedPoseCodec {
    /** Base64变长整数直接转为非NUL字符；避免AVM1吞掉零字符。 */
    private static function integers(input:String):String {
        if (typeof input != "string" || input.length == 0 || input.length % 4 != 0) return null;
        var alphabet:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var buffer:Number = 0; var bits:Number = 0; var value:Number = 0; var shift:Number = 0;
        var padding:Number = 0; var output:Array = [];
        for (var i:Number = 0; i < input.length; i++) {
            var ch:String = input.charAt(i);
            if (ch == "=") { if (++padding > 2 || i < input.length - 2) return null; continue; }
            var sextet:Number = alphabet.indexOf(ch);
            if (sextet < 0 || padding > 0) return null;
            buffer = (buffer << 6) | sextet; bits += 6;
            if (bits >= 8) {
                bits -= 8;
                var octet:Number = (buffer >> bits) & 255;
                buffer &= (1 << bits) - 1;
                value |= (octet & 127) << shift;
                if (octet & 128) { shift += 7; if (shift > 14) return null; }
                else {
                    if (value >= 65534) return null;
                    output.push(String.fromCharCode(value + 1));
                    value = 0; shift = 0;
                }
            }
        }
        if (shift != 0 || buffer != 0 || (padding == 0 && bits != 0)
                || (padding == 1 && bits != 2) || (padding == 2 && bits != 4)) return null;
        return output.join("");
    }

    public static function unpack(source:Object):Object {
        if (source.schema != "named-pose.packed.v1" || !(source.numbers instanceof Array)
                || !(source.targets instanceof Array) || !(source.parts instanceof Array)) return null;
        var width:Number = source.targets.length;
        if (!(width > 0 && width < 256) || source.numbers.length == 0 || source.numbers.length >= 65534) return null;
        var count:Object = source.counts;
        var names:Array = ["linear","matrices","states","poses"];
        for (var i:Number = 0; i < names.length; i++) {
            var n:Number = count[names[i]];
            if (!(n > 0 && n < 65534 && n == (n | 0))) return null;
        }
        for (i = 0; i < source.numbers.length; i++) {
            if (typeof source.numbers[i] != "number" || !isFinite(source.numbers[i])) return null;
        }
        var linear:String = integers(source.tables.linear);
        if (linear == null || linear.length != count.linear * 4) return null;
        for (i = 0; i < linear.length; i++) if (linear.charCodeAt(i) > source.numbers.length) return null;
        var result:Object = {schema:"named-pose.compact.v1",version:source.version,fps:source.fps,
            parts:source.parts,targets:source.targets,fixedAnchors:source.fixedAnchors,clips:source.clips,
            config:source.config,numbers:source.numbers,matrices:[],states:[],poses:[]};
        var stream:String = integers(source.tables.matrices);
        if (stream == null || stream.length != count.matrices * 3) return null;
        for (i = 0; i < stream.length; i += 3) {
            var lid:Number = stream.charCodeAt(i) - 1;
            if (lid >= count.linear || stream.charCodeAt(i+1) > source.numbers.length
                    || stream.charCodeAt(i+2) > source.numbers.length) return null;
            result.matrices.push(linear.substr(lid*4,4) + stream.substr(i+1,2));
        }
        stream = integers(source.tables.states);
        if (stream == null || stream.length != count.states * 3) return null;
        for (i = 0; i < stream.length; i += 3) {
            var alpha:Number = source.numbers[stream.charCodeAt(i+2)-1];
            if (stream.charCodeAt(i) > source.parts.length + 1 || stream.charCodeAt(i+1) > count.matrices
                    || !(alpha >= 0 && alpha <= 1)) return null;
            result.states.push(stream.substr(i,3));
        }
        stream = integers(source.tables.poses);
        if (stream == null || stream.length < width) return null;
        var pose:Array = [];
        for (i = 0; i < width; i++) {
            if (stream.charCodeAt(i) > count.states) return null;
            pose[i] = stream.charAt(i);
        }
        result.poses.push(pose.join(""));
        var offset:Number = width;
        while (offset < stream.length && result.poses.length < count.poses) {
            var changes:Number = stream.charCodeAt(offset++) - 1;
            if (changes > width || offset + changes*2 > stream.length) return null;
            var previous:Number = -1;
            for (i = 0; i < changes; i++) {
                var index:Number = stream.charCodeAt(offset++) - 1;
                var state:String = stream.charAt(offset++);
                if (index <= previous || index >= width || state.charCodeAt(0) > count.states) return null;
                previous = index; pose[index] = state;
            }
            result.poses.push(pose.join(""));
        }
        if (offset != stream.length || result.poses.length != count.poses) return null;
        return result;
    }
}
