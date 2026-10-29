import com.jpexs.decompiler.flash.AbortRetryIgnoreHandler;
import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.FrameExporter;
import com.jpexs.decompiler.flash.exporters.modes.SpriteExportMode;
import com.jpexs.decompiler.flash.exporters.settings.SpriteExportSettings;
import com.jpexs.decompiler.flash.tags.DefineSpriteTag;
import com.jpexs.decompiler.flash.tags.base.CharacterTag;

import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class BatchPreviewExporter {
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

    private record Job(String key, String swfRel, int cid, double zoom, int[] frames1Based, boolean exportSvg) {}

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        Path root = Path.of(args[0]);
        Path outRoot = Path.of(args[1]);

        List<Job> jobs = List.of(
            new Job("u459_clone_longevity", "flashswf/arts/new/Codex专用素材.swf", 366, 16.0, new int[]{1}, true),
            new Job("u460_clone_perfect", "flashswf/arts/new/Codex专用素材.swf", 484, 16.0, new int[]{1}, true),
            new Job("u461_cf6_male_zombie", "flashswf/arts/new/Antigravity专用素材.swf", 167, 16.0, new int[]{1}, true),
            new Job("u462_cf6_female_zombie", "flashswf/arts/new/Antigravity专用素材.swf", 32, 16.0, new int[]{1}, true),
            new Job("u463_cf6_manman", "flashswf/arts/new/Codex蛮蛮素材.swf", 52, 16.0, new int[]{1}, true),
            new Job("u464_cf6_wings", "flashswf/arts/new/CodexWings素材.swf", 41, 16.0, new int[]{1}, true),
            new Job("u465_cf6_bladebot", "flashswf/arts/new/Codex大刀机器人素材.swf", 26, 16.0, new int[]{1}, true),
            new Job("u466_cf6_commando", "flashswf/arts/new/Codex特种兵素材.swf", 44, 16.0, new int[]{1}, true),
            new Job("u466_cf6_commando_fire", "flashswf/arts/new/Codex特种兵素材.swf", 69, 16.0, new int[]{1, 10, 15}, false),
            new Job("u467_cf6_shield_commando", "flashswf/arts/new/Codex特种兵素材.swf", 141, 16.0, new int[]{1}, true),
            new Job("u468_cf6_guard", "flashswf/arts/new/Codex光头保安素材.swf", 37, 16.0, new int[]{1}, true),
            new Job("u469_cf6_transform_guard", "flashswf/arts/new/Codex光头保安素材.swf", 157, 16.0, new int[]{1, 10, 20, 30, 38, 45, 55, 65}, true),
            new Job("u472_cf6_headbot", "flashswf/arts/new/Codex大头机器人素材.swf", 9, 16.0, new int[]{1}, true),
            new Job("u473_cf6_elder_human", "flashswf/arts/new/Codex老头素材.swf", 89, 16.0, new int[]{1}, true),
            new Job("u474_cf6_elder_robot", "flashswf/arts/new/Codex老头素材.swf", 17, 16.0, new int[]{1}, true),
            new Job("jk_stand", "flashswf/arts/new/武装JK.swf", 142, 16.0, new int[]{10, 19}, true)
        );

        String lastSwf = "";
        SWF swf = null;
        for (Job job : jobs) {
            if (!job.swfRel.equals(lastSwf)) {
                Path swfPath = root.resolve(job.swfRel);
                try (FileInputStream fis = new FileInputStream(swfPath.toFile())) {
                    swf = new SWF(fis, false);
                }
                lastSwf = job.swfRel;
            }
            CharacterTag ct = swf.getCharacter(job.cid);
            if (!(ct instanceof DefineSpriteTag)) {
                throw new IllegalStateException("Not a sprite: " + job.key + " cid=" + job.cid);
            }
            List<Integer> zeroBased = new ArrayList<>();
            for (int f : job.frames1Based) zeroBased.add(f - 1);

            Path pngOut = outRoot.resolve(job.key).resolve("png");
            List<File> pngs = new FrameExporter().exportSpriteFrames(
                new AbortHandler(), pngOut.toString(), swf, job.cid, zeroBased,
                new SpriteExportSettings(SpriteExportMode.PNG, job.zoom), null
            );
            System.out.println(job.key + " PNG count=" + pngs.size() + " first=" + pngs.get(0).getAbsolutePath());

            if (job.exportSvg) {
                Path svgOut = outRoot.resolve(job.key).resolve("svg");
                List<File> svgs = new FrameExporter().exportSpriteFrames(
                    new AbortHandler(), svgOut.toString(), swf, job.cid, zeroBased,
                    new SpriteExportSettings(SpriteExportMode.SVG, job.zoom), null
                );
                System.out.println(job.key + " SVG count=" + svgs.size() + " first=" + svgs.get(0).getAbsolutePath());
            }
        }
    }
}
