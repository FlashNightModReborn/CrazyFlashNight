import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.Tag;
import com.jpexs.decompiler.flash.tags.base.PlaceObjectTypeTag;

import java.io.FileInputStream;
import java.nio.file.Path;
import java.util.List;

public final class CleanPortraitExporter {
    private static final class AbortHandler implements AbortRetryIgnoreHandler {
        @Override
        public int handle(Throwable t) {
            t.printStackTrace(System.err);
            return ABORT;
        }
        @Override
        public AbortRetryIgnoreHandler getNewInstance() {
            return new AbortHandler();
        }
    }

    private static void removeCharacterFromSprite(DefineSpriteTag sprite, int targetCid) {
        var tags = sprite.getTags();
        for (int i = tags.size() - 1; i >= 0; i--) {
            Tag t = tags.get(i);
            if (t instanceof PlaceObjectTypeTag po && po.getCharacterId() == targetCid) {
                sprite.removeTag(i);
            }
        }
        sprite.resetTimeline();
    }

    private static void freezeJkHair(SWF swf, int targetPlaceIdxIn137) {
        DefineSpriteTag s137 = (DefineSpriteTag) swf.getCharacter(137);
        Tag targetPlace = s137.getTags().get(targetPlaceIdxIn137);
        // Remove all tags after the first ShowFrame (idx=4) so s137 becomes a 1-frame sprite
        for (int i = s137.getTags().size() - 1; i > 4; i--) {
            s137.removeTag(i);
        }
        // In s137, idx=2 is d=16 cid=116, idx=3 is d=17 cid=118, idx=4 is ShowFrame
        s137.removeTag(3);
        s137.removeTag(2);
        s137.addTag(2, targetPlace);
        s137.setFrameCount(1);
        s137.resetTimeline();
        ((DefineSpriteTag) swf.getCharacter(142)).resetTimeline();
    }

    private static void exportBoth(SWF swf, int cid, int frame1Based, double zoom, Path outDir) throws Exception {
        for (SpriteExportMode mode : new SpriteExportMode[]{SpriteExportMode.PNG, SpriteExportMode.SVG}) {
            new FrameExporter().exportSpriteFrames(
                new AbortHandler(),
                outDir.resolve(mode.name().toLowerCase()).toString(),
                swf, cid, List.of(frame1Based - 1),
                new SpriteExportSettings(mode, zoom), null
            );
        }
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        Path root = Path.of(args[0]);
        Path outRoot = Path.of(args[1]);

        // 1. 武装JK: orange (idx=17 in cid=137 -> cid=119) and white (idx=29 in cid=137 -> cid=121), also remove foot shadow cid=57
        Path jkPath = root.resolve("flashswf/arts/new/武装JK.swf");
        try (FileInputStream fis = new FileInputStream(jkPath.toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(142), 57);
            freezeJkHair(swf, 17); // frame 10 '橙发' (cid=119)
            exportBoth(swf, 142, 10, 16.0, outRoot.resolve("jk_clean_orange"));
        }
        try (FileInputStream fis = new FileInputStream(jkPath.toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(142), 57);
            freezeJkHair(swf, 29); // frame 19 '白发' (cid=121)
            exportBoth(swf, 142, 10, 16.0, outRoot.resolve("jk_clean_white"));
        }

        // 2. Clean exports for shadow-bearing units + commando knife f10
        try (FileInputStream fis = new FileInputStream(root.resolve("flashswf/arts/new/Codex蛮蛮素材.swf").toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(52), 2);
            exportBoth(swf, 52, 1, 16.0, outRoot.resolve("u463_cf6_manman_clean"));
        }
        try (FileInputStream fis = new FileInputStream(root.resolve("flashswf/arts/new/Codex特种兵素材.swf").toFile())) {
            SWF swf = new SWF(fis, false);
            exportBoth(swf, 68, 10, 16.0, outRoot.resolve("u466_cf6_commando_knife10"));
        }
        try (FileInputStream fis = new FileInputStream(root.resolve("flashswf/arts/new/Codex光头保安素材.swf").toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(157), 76);
            exportBoth(swf, 157, 45, 16.0, outRoot.resolve("u469_cf6_transform_guard_clean"));
        }
        try (FileInputStream fis = new FileInputStream(root.resolve("flashswf/arts/new/Codex大头机器人素材.swf").toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(9), 2);
            exportBoth(swf, 9, 1, 16.0, outRoot.resolve("u472_cf6_headbot_clean"));
        }
        try (FileInputStream fis = new FileInputStream(root.resolve("flashswf/arts/new/Codex老头素材.swf").toFile())) {
            SWF swf = new SWF(fis, false);
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(89), 2);
            exportBoth(swf, 89, 1, 16.0, outRoot.resolve("u473_cf6_elder_human_clean"));
            removeCharacterFromSprite((DefineSpriteTag) swf.getCharacter(17), 2);
            exportBoth(swf, 17, 1, 16.0, outRoot.resolve("u474_cf6_elder_robot_clean"));
        }
        System.out.println("All clean exports finished.");
    }
}
