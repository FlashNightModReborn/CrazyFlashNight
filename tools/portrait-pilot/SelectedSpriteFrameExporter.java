import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.base.CharacterTag;

import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Minimal FFDec library adapter for exporting only selected frames of one
 * DefineSprite. FFDec's CLI accepts -select for top-level frames but currently
 * expands every frame for sprite:png; the library API has the required exact
 * frame list and preserves frame-specific Flash color transforms.
 */
public final class SelectedSpriteFrameExporter {
    private SelectedSpriteFrameExporter() {}

    private static final class AbortHandler implements AbortRetryIgnoreHandler {
        @Override
        public int handle(Throwable throwable) {
            throwable.printStackTrace(System.err);
            return ABORT;
        }

        @Override
        public AbortRetryIgnoreHandler getNewInstance() {
            return new AbortHandler();
        }
    }

    private static List<Integer> parseFrames(String csv, int frameCount) {
        Set<Integer> ordered = new LinkedHashSet<>();
        for (String raw : csv.split(",")) {
            int oneBased;
            try {
                oneBased = Integer.parseInt(raw.trim());
            } catch (NumberFormatException error) {
                throw new IllegalArgumentException("Invalid frame number: " + raw, error);
            }
            if (oneBased < 1 || oneBased > frameCount) {
                throw new IllegalArgumentException("Frame outside 1.." + frameCount + ": " + oneBased);
            }
            ordered.add(oneBased - 1);
        }
        if (ordered.isEmpty()) throw new IllegalArgumentException("At least one frame is required");
        return new ArrayList<>(ordered);
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length != 5) {
            System.err.println("Usage: SelectedSpriteFrameExporter <swf> <output-dir> <character-id> <zoom> <frames-1-based-csv>");
            System.exit(2);
        }

        Path swfPath = Path.of(args[0]).toAbsolutePath().normalize();
        Path outputPath = Path.of(args[1]).toAbsolutePath().normalize();
        int characterId = Integer.parseInt(args[2]);
        double zoom = Double.parseDouble(args[3]);
        if (!Files.isRegularFile(swfPath)) throw new IllegalArgumentException("SWF does not exist: " + swfPath);
        if (Files.exists(outputPath)) throw new IllegalArgumentException("Output path already exists: " + outputPath);
        if (!Double.isFinite(zoom) || zoom < 1 || zoom > 64) throw new IllegalArgumentException("Zoom must be within 1..64");

        SWF swf;
        try (FileInputStream input = new FileInputStream(swfPath.toFile())) {
            swf = new SWF(input, false);
        }
        CharacterTag character = swf.getCharacter(characterId);
        if (!(character instanceof DefineSpriteTag sprite)) {
            throw new IllegalArgumentException("Character is not a DefineSprite: " + characterId);
        }
        List<Integer> frames = parseFrames(args[4], sprite.getFrameCount());
        SpriteExportSettings settings = new SpriteExportSettings(SpriteExportMode.PNG, zoom);
        List<File> outputs = new FrameExporter().exportSpriteFrames(
            new AbortHandler(),
            outputPath.toString(),
            swf,
            characterId,
            frames,
            settings,
            null
        );
        if (outputs.size() != frames.size()) {
            throw new IllegalStateException("FFDec output count mismatch: expected=" + frames.size() + " actual=" + outputs.size());
        }
        System.out.println("status=selected_sprite_frames_exported");
        System.out.println("characterId=" + characterId);
        System.out.println("zoom=" + zoom);
        System.out.println("frames=" + args[4]);
        for (File output : outputs) System.out.println("output=" + output.getAbsolutePath());
    }
}
