import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.commonshape.Matrix;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.types.ColorTransform;
import com.jpexs.decompiler.flash.types.RECT;
import com.jpexs.helpers.SerializableImage;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import javax.imageio.ImageIO;

/** Read-only first-frame rasterization with an explicit filter-safe viewport.
 * FrameExporter uses shape bounds, which clip GlowFilter on thin chain units.
 * The larger rendering viewport changes neither source tags nor SWF bytes.
 */
public final class BulletSpriteExporter {
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length != 4) throw new IllegalArgumentException("swf plan.tsv output zoom");
        SWF swf;
        try (FileInputStream input = new FileInputStream(args[0])) { swf = new SWF(input, false); }
        Path out = Path.of(args[2]);
        double zoom = Double.parseDouble(args[3]);
        if (Files.exists(out) || zoom < 1 || zoom > 8) throw new IllegalArgumentException("Invalid output/zoom");
        Files.createDirectories(out);
        List<String> rows = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8)) {
            String[] cols = line.split("\t");
            int style = Integer.parseInt(cols[0]), id = Integer.parseInt(cols[1]);
            if (!(swf.getCharacter(id) instanceof DefineSpriteTag sprite) || !cols[2].equals("0"))
                throw new IllegalArgumentException("Only first-frame sprites are supported");
            RECT bounds = new RECT(sprite.getRectWithStrokes());
            // 32 source pixels comfortably contain the reviewed 8px glows.
            // Python rejects a nontransparent viewport edge, so future larger
            // filters fail closed rather than silently trimming the artwork.
            bounds.Xmin -= 640; bounds.Ymin -= 640;
            bounds.Xmax += 640; bounds.Ymax += 640;
            SerializableImage image = SWF.frameToImageGet(sprite.getTimeline(), 0, 0, null, 0,
                bounds, new Matrix(), new ColorTransform(), null, zoom, false);
            Path path = out.resolve("style-" + style + ".png");
            if (!ImageIO.write(image.getBufferedImage(), "png", path.toFile()))
                throw new IllegalStateException("PNG writer unavailable");
            rows.add(style + "\t0\t" + bounds.Xmin + "\t" + bounds.Ymin + "\t" + bounds.Xmax + "\t"
                + bounds.Ymax + "\t" + path.toAbsolutePath());
        }
        Files.write(out.resolve("frames.tsv"), rows, StandardCharsets.UTF_8);
        System.out.println("Exported " + rows.size() + " filter-safe source bullet frames.");
    }
}
