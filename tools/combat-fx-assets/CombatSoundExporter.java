import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.exporters.SoundExporter;
import com.jpexs.decompiler.flash.exporters.modes.SoundExportMode;
import com.jpexs.decompiler.flash.tags.DefineSoundTag;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Decode selected published event sounds only. Never plays or saves the SWF. */
public final class CombatSoundExporter {
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length != 3) throw new IllegalArgumentException("swf sound-ids output");
        SWF swf;
        try (FileInputStream input = new FileInputStream(args[0])) { swf = new SWF(input, false); }
        Path out = Path.of(args[2]);
        if (Files.exists(out)) throw new IllegalArgumentException("Output already exists");
        Files.createDirectories(out);
        SoundExporter exporter = new SoundExporter();
        List<String> rows = new ArrayList<>();
        for (String value : args[1].split(",")) {
            int id = Integer.parseInt(value);
            if (!(swf.getCharacter(id) instanceof DefineSoundTag sound) || sound.soundFormat != 2)
                throw new IllegalArgumentException("Expected reviewed MP3 DefineSound: " + id);
            // FFDec's WAV path calls getInitialLatency() and removes MP3 SeekSamples
            // from decoded PCM. Raw MP3 export would retain that encoder delay.
            byte[] wav = exporter.exportSound(sound, SoundExportMode.WAV, false);
            Files.write(out.resolve("sound-" + id + ".wav"), wav);
            rows.add(id + "\t" + sound.getInitialLatency() + "\t" + sound.soundSampleCount
                + "\t" + sound.getSoundFormat().samplingRate + "\t" + (sound.soundType ? 2 : 1));
        }
        Files.write(out.resolve("sounds.tsv"), rows, StandardCharsets.UTF_8);
        System.out.println("Decoded " + rows.size() + " selected event sounds with authored SeekSamples.");
    }
}
