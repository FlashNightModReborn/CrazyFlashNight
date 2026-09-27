import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.types.RECT;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Read-only, selected-frame FFDec rasterization. Never executes frame scripts. */
public final class CombatSpriteExporter {
    private static final class AbortHandler implements AbortRetryIgnoreHandler {
        public int handle(Throwable error) { error.printStackTrace(System.err); return ABORT; }
        public AbortRetryIgnoreHandler getNewInstance() { return new AbortHandler(); }
    }
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length != 4) throw new IllegalArgumentException("swf plan.tsv output zoom");
        SWF swf;
        try (FileInputStream input = new FileInputStream(args[0])) { swf = new SWF(input, false); }
        Path out = Path.of(args[2]);
        double zoom = Double.parseDouble(args[3]);
        if (Files.exists(out) || zoom < 1 || zoom > 8) throw new IllegalArgumentException("Invalid output/zoom");
        Files.createDirectories(out);
        List<String> results = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8)) {
            String[] cols = line.split("\t");
            int style = Integer.parseInt(cols[0]), id = Integer.parseInt(cols[1]);
            if (!(swf.getCharacter(id) instanceof DefineSpriteTag sprite))
                throw new IllegalArgumentException("Not a sprite: " + id);
            List<Integer> frames = new ArrayList<>();
            for (String value : cols[2].split(",")) {
                int frame = Integer.parseInt(value);
                if (frame < 0 || frame >= sprite.getFrameCount()) throw new IllegalArgumentException("Invalid frame");
                frames.add(frame);
            }
            RECT bounds = sprite.getRectWithStrokes();
            List<File> files = new FrameExporter().exportSpriteFrames(new AbortHandler(),
                out.resolve("style-" + style).toString(), swf, id, frames,
                new SpriteExportSettings(SpriteExportMode.PNG, zoom), null);
            if (files.size() != frames.size()) throw new IllegalStateException("Frame export count mismatch");
            for (int i = 0; i < files.size(); i++) results.add(style + "\t" + frames.get(i)
                + "\t" + bounds.Xmin + "\t" + bounds.Ymin + "\t" + bounds.Xmax + "\t" + bounds.Ymax
                + "\t" + files.get(i).getAbsolutePath());
        }
        Files.write(out.resolve("frames.tsv"), results, StandardCharsets.UTF_8);
        System.out.println("Exported " + results.size() + " selected frames.");
    }
}
