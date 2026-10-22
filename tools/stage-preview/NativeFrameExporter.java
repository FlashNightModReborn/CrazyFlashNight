import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.Arrays;

/** Read-only native raster export. Jobs: swf|output-directory|sprite-id|frame-1based|zoom. */
public final class NativeFrameExporter {
    private static final class FailClosed implements AbortRetryIgnoreHandler {
        public int handle(Throwable error) { throw new IllegalStateException("Native frame export failed", error); }
        public AbortRetryIgnoreHandler getNewInstance() { return new FailClosed(); }
    }
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        for (String line : Files.readAllLines(Path.of(args[0]), StandardCharsets.UTF_8)) {
            if (line.isBlank()) continue;
            String[] p=line.split("\\|",-1);
            if(p.length<5 || p.length>6) throw new IllegalArgumentException("Expected five or six job columns");
            Path source=Path.of(p[0]), output=Path.of(p[1]);
            int id=Integer.parseInt(p[2]), frame=Integer.parseInt(p[3]);
            double zoom=Double.parseDouble(p[4]);
            try(FileInputStream stream=new FileInputStream(source.toFile())) {
                SWF swf=new SWF(stream,false);
                if(!(swf.getCharacter(id) instanceof DefineSpriteTag sprite))
                    throw new IllegalArgumentException("Missing sprite " + id + " in " + source);
                if(frame<1 || frame>sprite.getTimeline().getFrameCount() || zoom<=0 || zoom>32)
                    throw new IllegalArgumentException("Invalid frame or zoom");
                if(p.length==6 && !p[5].isBlank()) {
                    Set<Integer> retained=Arrays.stream(p[5].split(",")).map(Integer::parseInt).collect(Collectors.toSet());
                    // Filter the in-memory render timeline only; never serialize a modified SWF.
                    sprite.getTimeline().getFrame(frame-1).layers.keySet().removeIf(depth -> !retained.contains(depth));
                }
                Files.createDirectories(output);
                new FrameExporter().exportSpriteFrames(new FailClosed(),output.toString(),swf,id,
                    List.of(frame-1),new SpriteExportSettings(SpriteExportMode.PNG,zoom),null);
                try(var files=Files.walk(output)) {
                    long count=files.filter(f -> f.getFileName().toString().equals(frame+".png")
                        && f.getParent().getFileName().toString().startsWith("DefineSprite_"+id)).count();
                    if(count!=1) throw new IllegalStateException("Expected one exported frame, found " + count);
                }
                System.out.println("Exported sprite="+id+" frame="+frame+" zoom="+zoom);
            }
        }
    }
}
