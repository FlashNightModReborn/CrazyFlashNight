import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.FrameExportMode;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.FrameExportSettings;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.base.CharacterTag;
import com.jpexs.decompiler.flash.tags.base.DrawableTag;
import com.jpexs.decompiler.flash.timeline.DepthState;
import com.jpexs.decompiler.flash.timeline.Frame;
import com.jpexs.decompiler.flash.types.MATRIX;
import com.jpexs.decompiler.flash.types.RECT;

import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public final class BatchBgExporter {
    private static final class IgnoreHandler implements AbortRetryIgnoreHandler {
        @Override
        public int handle(Throwable throwable) {
            throw new IllegalStateException("Background export failed", throwable);
        }
        @Override
        public AbortRetryIgnoreHandler getNewInstance() {
            return new IgnoreHandler();
        }
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        Path jobFile = Path.of(args[0]).toAbsolutePath().normalize();
        List<String> lines = Files.readAllLines(jobFile, StandardCharsets.UTF_8);

        for (String line : lines) {
            if (line == null || line.isBlank()) continue;
            String[] parts = line.split("\\|");
            Path swfPath = Path.of(parts[0]).toAbsolutePath().normalize();
            Path outDir = Path.of(parts[1]).toAbsolutePath().normalize();
            int spriteId = (parts.length >= 3 && !parts[2].isBlank()) ? Integer.parseInt(parts[2].trim()) : -1;

            if (!Files.isRegularFile(swfPath)) {
                throw new IllegalArgumentException("Missing SWF: " + swfPath);
            }
            Files.createDirectories(outDir);

            try (FileInputStream fis = new FileInputStream(swfPath.toFile())) {
                SWF swf = new SWF(fis, false);
                RECT origRect = new RECT(swf.displayRect);
                List<Integer> frame0 = Collections.singletonList(0);

                if (spriteId > 0) {
                    CharacterTag ch = swf.getCharacter(spriteId);
                    RECT r = (ch instanceof DrawableTag dt) ? dt.getRect() : origRect;
                    SpriteExportSettings sSettings = new SpriteExportSettings(SpriteExportMode.PNG, 1.0);
                    new FrameExporter().exportSpriteFrames(
                        new IgnoreHandler(),
                        outDir.toString(),
                        swf,
                        spriteId,
                        frame0,
                        sSettings,
                        null
                    );
                    System.out.println("OK|" + parts[0] + "|" + (r.Xmin/20) + "," + (r.Ymin/20) + "," + (r.Xmax/20) + "," + (r.Ymax/20)
                        + "|" + (origRect.Xmin/20) + "," + (origRect.Ymin/20) + "," + (origRect.Xmax/20) + "," + (origRect.Ymax/20));
                    continue;
                }

                Map<Integer, CharacterTag> chars = swf.getCharacters(false);
                int xmin = Integer.MAX_VALUE, xmax = Integer.MIN_VALUE;
                int ymin = Integer.MAX_VALUE, ymax = Integer.MIN_VALUE;

                if (swf.getTimeline().getFrameCount() > 0) {
                    Frame f0 = swf.getTimeline().getFrame(0);
                    for (DepthState ds : f0.layers.values()) {
                        CharacterTag ch = chars.get(ds.characterId);
                        if (!(ch instanceof DrawableTag dt)) continue;
                        RECT r;
                        try {
                            r = dt.getRect();
                        } catch (Throwable t) {
                            continue;
                        }
                        if (r == null || r.getWidth() <= 0 || r.getHeight() <= 0 || r.getWidth() > 200000 || r.getHeight() > 100000) {
                            continue;
                        }
                        MATRIX m = ds.matrix;
                        double sx = (m != null && m.hasScale) ? m.scaleX : 1.0;
                        double sy = (m != null && m.hasScale) ? m.scaleY : 1.0;
                        double rk0 = (m != null && m.hasRotate) ? m.rotateSkew0 : 0.0;
                        double rk1 = (m != null && m.hasRotate) ? m.rotateSkew1 : 0.0;
                        double tx = (m != null) ? m.translateX : 0.0;
                        double ty = (m != null) ? m.translateY : 0.0;

                        int[] xs = {r.Xmin, r.Xmax};
                        int[] ys = {r.Ymin, r.Ymax};
                        for (int x : xs) {
                            for (int y : ys) {
                                int wx = (int) Math.round(x * sx + y * rk1 + tx);
                                int wy = (int) Math.round(x * rk0 + y * sy + ty);
                                xmin = Math.min(xmin, wx);
                                xmax = Math.max(xmax, wx);
                                ymin = Math.min(ymin, wy);
                                ymax = Math.max(ymax, wy);
                            }
                        }
                    }
                }

                if (xmin == Integer.MAX_VALUE) {
                    xmin = origRect.Xmin;
                    xmax = origRect.Xmax;
                    ymin = origRect.Ymin;
                    ymax = origRect.Ymax;
                }

                xmin = Math.max(xmin, -80000);
                xmax = Math.min(xmax, 120000);
                ymin = Math.max(ymin, -40000);
                ymax = Math.min(ymax, 60000);

                swf.displayRect.Xmin = xmin;
                swf.displayRect.Ymin = ymin;
                swf.displayRect.Xmax = xmax;
                swf.displayRect.Ymax = ymax;
                swf.getTimeline().displayRect = new RECT(swf.displayRect);

                FrameExportSettings fSettings = new FrameExportSettings(FrameExportMode.PNG, 1.0, true);
                new FrameExporter().exportFrames(
                    new IgnoreHandler(),
                    outDir.toString(),
                    swf,
                    0,
                    frame0,
                    fSettings,
                    null
                );
                System.out.println("OK|" + parts[0] + "|" + (xmin/20) + "," + (ymin/20) + "," + (xmax/20) + "," + (ymax/20)
                    + "|" + (origRect.Xmin/20) + "," + (origRect.Ymin/20) + "," + (origRect.Xmax/20) + "," + (origRect.Ymax/20));
            }
        }
    }
}
