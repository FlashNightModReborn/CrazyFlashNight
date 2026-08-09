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
 * Loads one SWF once and exports a bounded sample of frames from several
 * DefineSprites. This avoids FFDec CLI's all-frame expansion for long internal
 * timelines while preserving exact character/frame provenance.
 */
public final class SelectedSpriteSampleExporter {
    private SelectedSpriteSampleExporter() {}

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

    private record Sample(int characterId, List<Integer> zeroBasedFrames, String originalFrames) {}

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

    private static Sample parseSample(SWF swf, String raw) {
        String[] parts = raw.split(":", 2);
        if (parts.length != 2) throw new IllegalArgumentException("Invalid sample spec: " + raw);
        int characterId = Integer.parseInt(parts[0]);
        CharacterTag character = swf.getCharacter(characterId);
        if (!(character instanceof DefineSpriteTag sprite)) {
            throw new IllegalArgumentException("Character is not a DefineSprite: " + characterId);
        }
        return new Sample(characterId, parseFrames(parts[1], sprite.getFrameCount()), parts[1]);
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length != 4) {
            System.err.println("Usage: SelectedSpriteSampleExporter <swf> <output-dir> <zoom> <id:frames;id:frames>");
            System.exit(2);
        }

        Path swfPath = Path.of(args[0]).toAbsolutePath().normalize();
        Path outputPath = Path.of(args[1]).toAbsolutePath().normalize();
        double zoom = Double.parseDouble(args[2]);
        if (!Files.isRegularFile(swfPath)) throw new IllegalArgumentException("SWF does not exist: " + swfPath);
        if (Files.exists(outputPath)) throw new IllegalArgumentException("Output path already exists: " + outputPath);
        if (!Double.isFinite(zoom) || zoom < 0.25 || zoom > 16) {
            throw new IllegalArgumentException("Zoom must be within 0.25..16");
        }

        SWF swf;
        try (FileInputStream input = new FileInputStream(swfPath.toFile())) {
            swf = new SWF(input, false);
        }
        List<Sample> samples = new ArrayList<>();
        Set<Integer> seen = new LinkedHashSet<>();
        for (String raw : args[3].split(";")) {
            Sample sample = parseSample(swf, raw);
            if (!seen.add(sample.characterId())) {
                throw new IllegalArgumentException("Duplicate character id: " + sample.characterId());
            }
            samples.add(sample);
        }
        if (samples.isEmpty()) throw new IllegalArgumentException("At least one sprite sample is required");

        SpriteExportSettings settings = new SpriteExportSettings(SpriteExportMode.PNG, zoom);
        for (Sample sample : samples) {
            List<File> outputs = new FrameExporter().exportSpriteFrames(
                new AbortHandler(),
                outputPath.toString(),
                swf,
                sample.characterId(),
                sample.zeroBasedFrames(),
                settings,
                null
            );
            if (outputs.size() != sample.zeroBasedFrames().size()) {
                throw new IllegalStateException(
                    "FFDec output count mismatch: character=" + sample.characterId()
                    + " expected=" + sample.zeroBasedFrames().size() + " actual=" + outputs.size()
                );
            }
            System.out.println("characterId=" + sample.characterId() + " frames=" + sample.originalFrames());
            for (File output : outputs) System.out.println("output=" + output.getAbsolutePath());
        }
        System.out.println("status=selected_sprite_samples_exported");
        System.out.println("zoom=" + zoom);
        System.out.println("spriteCount=" + samples.size());
    }
}
