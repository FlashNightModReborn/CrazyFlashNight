import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.Tag;
import com.jpexs.decompiler.flash.tags.base.PlaceObjectTypeTag;
import com.jpexs.decompiler.flash.types.MATRIX;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Selected idle-frame renderer. The SWF is read only and is never serialized.
 * Iron Guard's enterFrame mouth transform is evaluated once in memory, using
 * the same three local anchors as build.py's MOUTH_SCRIPT. FFDec does not run AS2.
 */
public final class DogPortraitExporter {
    private static final class AbortHandler implements AbortRetryIgnoreHandler {
        public int handle(Throwable t) { t.printStackTrace(System.err); return ABORT; }
        public AbortRetryIgnoreHandler getNewInstance() { return new AbortHandler(); }
    }
    private static double[] point(MATRIX m, double x, double y) {
        return new double[] {m.getScaleXFloat()*x + m.getRotateSkew1Float()*y + m.translateX/20.0,
            m.getRotateSkew0Float()*x + m.getScaleYFloat()*y + m.translateY/20.0};
    }
    private static void freezeMouth(DefineSpriteTag sprite) {
        PlaceObjectTypeTag head = null, jaw = null, mouth = null;
        for (Tag tag : sprite.getTags()) {
            if (tag.getId() == 1) break;
            if (!(tag instanceof PlaceObjectTypeTag place)) continue;
            if ("part230".equals(place.getInstanceName())) head = place;
            if ("part235".equals(place.getInstanceName())) jaw = place;
            if ("part215".equals(place.getInstanceName())) mouth = place;
        }
        if (head == null || jaw == null || mouth == null) throw new IllegalArgumentException("Missing live mouth anchors");
        double[] h=point(head.getMatrix(),60,110), u=point(head.getMatrix(),320,107), l=point(jaw.getMatrix(),205,76);
        MATRIX m = new MATRIX(); m.hasScale = true; m.hasRotate = true;
        m.scaleX=(float)(u[0]-h[0]); m.rotateSkew0=(float)(u[1]-h[1]);
        m.rotateSkew1=(float)(l[0]-h[0]); m.scaleY=(float)(l[1]-h[1]);
        // The renderer's MATRIX stores translation in twips. No geometry changes.
        m.translateX=(int)Math.round(h[0]*20); m.translateY=(int)Math.round(h[1]*20);
        mouth.setMatrix(m); mouth.setPlaceFlagHasMatrix(true); sprite.resetTimeline();
        System.out.println("mouthMatrix="+m.scaleX+","+m.rotateSkew0+","+m.rotateSkew1+","+m.scaleY+","+m.translateX/20.0+","+m.translateY/20.0);
    }
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless","true");
        if (args.length != 5) throw new IllegalArgumentException("swf output sprite-id zoom freeze-mouth");
        Path source=Path.of(args[0]), out=Path.of(args[1]);
        int id=Integer.parseInt(args[2]); double zoom=Double.parseDouble(args[3]);
        if (!Files.isRegularFile(source) || Files.exists(out) || zoom<1 || zoom>32 || !Double.isFinite(zoom))
            throw new IllegalArgumentException("Source/output/zoom");
        if (!args[4].equals("true") && !args[4].equals("false")) throw new IllegalArgumentException("freeze-mouth");
        SWF swf; try (FileInputStream input=new FileInputStream(source.toFile())) { swf=new SWF(input,false); }
        if (!(swf.getCharacter(id) instanceof DefineSpriteTag sprite) || sprite.getFrameCount()!=50)
            throw new IllegalArgumentException("Expected dog idle action (50 frames)");
        if (Boolean.parseBoolean(args[4])) freezeMouth(sprite);
        for (SpriteExportMode mode : new SpriteExportMode[] {SpriteExportMode.PNG,SpriteExportMode.SVG}) {
            var outputs=new FrameExporter().exportSpriteFrames(new AbortHandler(),out.resolve(mode.name().toLowerCase()).toString(),
                swf,id,List.of(0),new SpriteExportSettings(mode,zoom),null);
            if (outputs.size()!=1) throw new IllegalStateException("Selected-frame closure");
            System.out.println(mode+"="+outputs.get(0).getAbsolutePath());
        }
    }
}
