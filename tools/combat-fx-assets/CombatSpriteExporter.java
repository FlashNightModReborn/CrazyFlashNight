import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.commonshape.Matrix;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.Tag;
import com.jpexs.decompiler.flash.tags.base.PlaceObjectTypeTag;
import com.jpexs.decompiler.flash.types.MATRIX;
import com.jpexs.decompiler.flash.types.RECT;
import com.jpexs.helpers.SerializableImage;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import javax.imageio.ImageIO;

/** Read-only, selected-frame FFDec rasterization. Never executes frame scripts. */
public final class CombatSpriteExporter {
    private static final class AbortHandler implements AbortRetryIgnoreHandler {
        public int handle(Throwable error) { error.printStackTrace(System.err); return ABORT; }
        public AbortRetryIgnoreHandler getNewInstance() { return new AbortHandler(); }
    }
    private static PlaceObjectTypeTag visualChild(DefineSpriteTag sprite, String name) {
        PlaceObjectTypeTag result = null;
        for (Tag tag : sprite.getTags()) {
            if (tag instanceof PlaceObjectTypeTag place && name.equals(place.getInstanceName())) {
                if (result != null) throw new IllegalArgumentException("Duplicate named child: " + name);
                result = place;
            }
        }
        if (result == null) throw new IllegalArgumentException("Missing named child: " + name);
        return result;
    }
    private static void reset(SWF swf, DefineSpriteTag sprite) {
        sprite.resetTimeline(); swf.getRectCache().clear(); swf.clearImageCache();
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
            String[] cols = line.split("\t", -1);
            int style = Integer.parseInt(cols[0]), id = Integer.parseInt(cols[1]);
            if (!(swf.getCharacter(id) instanceof DefineSpriteTag sprite))
                throw new IllegalArgumentException("Not a sprite: " + id);
            String childName = cols.length > 3 ? cols[3] : "-";
            String mode = cols.length > 4 ? cols[4] : "legacy";
            if (!List.of("legacy", "child", "nested-scaled", "padded").contains(mode))
                throw new IllegalArgumentException("Unknown render adapter");
            PlaceObjectTypeTag child = null; MATRIX original = null;
            if (!childName.equals("-")) {
                child = visualChild(sprite, childName);
                if (mode.equals("child")) {
                    id = child.getCharacterId();
                    if (!(swf.getCharacter(id) instanceof DefineSpriteTag nested))
                        throw new IllegalArgumentException("Visual child is not a sprite");
                    sprite = nested;
                } else if (mode.equals("nested-scaled")) {
                    original = child.getMatrix();
                    if (original == null || original.hasRotate ||
                        Math.abs(original.getScaleXFloat() - .284439086914063) > 1e-7 ||
                        original.getScaleXFloat() != original.getScaleYFloat() ||
                        child.getFilters() == null || child.getFilters().size() != 1 || child.getFilters().get(0).id != 2)
                        throw new IllegalArgumentException("Unreviewed nested scale or GlowFilter");
                    // This is a disposable in-memory render view. No SWF is saved.
                    // Keep authored scale/filter; runtime applies only the child's
                    // translation and random rotation, avoiding double scaling.
                    MATRIX centered = new MATRIX(original); centered.translateX = centered.translateY = 0;
                    child.setMatrix(centered); reset(swf, sprite);
                } else throw new IllegalArgumentException("Child needs a reviewed render adapter");
            }
            try {
            List<Integer> frames = new ArrayList<>();
            for (String value : cols[2].split(",")) {
                int frame = Integer.parseInt(value);
                if (frame < 0 || frame >= sprite.getFrameCount()) throw new IllegalArgumentException("Invalid frame");
                frames.add(frame);
            }
            RECT bounds = new RECT(sprite.getRectWithStrokes());
            List<File> files;
            if (mode.equals("padded") || mode.equals("nested-scaled")) {
                // The same filter-safe viewport used by the bullet exporter.
                // Python rejects any nontransparent outer edge.
                bounds.Xmin -= 640; bounds.Xmax += 640; bounds.Ymin -= 640; bounds.Ymax += 640;
                Path images = out.resolve("style-" + style); Files.createDirectories(images);
                files = new ArrayList<>();
                for (int frame : frames) {
                    SerializableImage image = SWF.frameToImageGet(sprite.getTimeline(), frame, 0, null, 0,
                        bounds, new Matrix(), null, null, zoom, true);
                    Path path = images.resolve("frame-" + frame + ".png");
                    if (!ImageIO.write(image.getBufferedImage(), "png", path.toFile()))
                        throw new IllegalStateException("PNG writer unavailable");
                    files.add(path.toFile());
                }
            } else {
                // Existing 35 styles stay on their original rasterization path.
                files = new FrameExporter().exportSpriteFrames(new AbortHandler(),
                    out.resolve("style-" + style).toString(), swf, id, frames,
                    new SpriteExportSettings(SpriteExportMode.PNG, zoom), null);
            }
            if (files.size() != frames.size()) throw new IllegalStateException("Frame export count mismatch");
            for (int i = 0; i < files.size(); i++) results.add(style + "\t" + frames.get(i)
                + "\t" + bounds.Xmin + "\t" + bounds.Ymin + "\t" + bounds.Xmax + "\t" + bounds.Ymax
                + "\t" + files.get(i).getAbsolutePath());
            } finally {
                if (original != null) { child.setMatrix(original); reset(swf, sprite); }
            }
        }
        Files.write(out.resolve("frames.tsv"), results, StandardCharsets.UTF_8);
        System.out.println("Exported " + results.size() + " selected frames.");
    }
}
