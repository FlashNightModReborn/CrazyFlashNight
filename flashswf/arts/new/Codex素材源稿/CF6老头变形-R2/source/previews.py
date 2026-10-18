"""30 fps side-by-side static visual simulation with original sound cues.
This is not an executed Flash recording. Scene audio tail policy is documented.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import subprocess,json
R=Path(__file__).resolve().parents[1];P=R/'previews';P.mkdir(parents=True,exist_ok=True);VF=R/'qa/video-frames';VF.mkdir(parents=True,exist_ok=True)
frames=[]
for fr in range(1,284):
 board=Image.new('RGB',(1280,400),'#151515');d=ImageDraw.Draw(board)
 for j,var in enumerate(['original','candidate']):
  im=Image.open(R/f'qa/frames/{var}/{fr:03}.png').convert('RGB').resize((640,374),Image.Resampling.LANCZOS);board.paste(im,(640*j,26));d.text((640*j+10,7),f'{"ORIGINAL" if j==0 else "R2"} | 2008 frame {fr:03}/283 | static 30fps',fill='#dddddd')
 board.save(VF/f'{fr:03}.png')
 small=board.resize((640,200),Image.Resampling.LANCZOS);frames.append(small)
durations=[40 if (i+1)%3==0 else 30 for i in range(283)]
frames[0].save(P/'transform-original-r2.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=False,disposal=2)
# Exact 30 fps video. Original three audio assets are kept independently and in
# a full-tail mix. MP4 stops with original frame283, so any surviving tail is
# provided separately rather than inventing a freeze-frame extension.
audio=P/'sound-effects-full-tail.wav'
filt='[0:a]atrim=start_sample=1661:end_sample=50940,asetpts=PTS-STARTPTS,aresample=44100,adelay=1470S:all=1[a0];[1:a]atrim=start_sample=1661:end_sample=65529,asetpts=PTS-STARTPTS,aresample=44100,adelay=117600S:all=1[a1];[2:a]atrim=start_sample=1661:end_sample=17970,asetpts=PTS-STARTPTS,aresample=44100,adelay=373380S:all=1[a2];[a0][a1][a2]amix=inputs=3:duration=longest:normalize=0[out]'
subprocess.run(['ffmpeg','-y','-v','error','-i',str(R/'audio/sound-1993.mp3'),'-i',str(R/'audio/sound-2004.mp3'),'-i',str(R/'audio/sound-2007.mp3'),'-filter_complex',filt,'-map','[out]','-c:a','pcm_s16le',str(audio)],check=True)
subprocess.run(['ffmpeg','-y','-v','error','-framerate','30','-start_number','1','-i',str(VF/'%03d.png'),'-i',str(audio),'-frames:v','283','-t',str(283/30),'-c:v','libx264','-preset','medium','-crf','21','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-movflags','+faststart',str(P/'transform-original-r2.mp4')],check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(P/'transform-original-r2.mp4')]))
(P/'preview-timing.json').write_text(json.dumps({'sprite':2008,'frames':283,'sourceFps':30,'nominalSeconds':283/30,'gifDurationMs':sum(durations),'gifQuantization':'30/30/40ms repeating, approximately 30fps. MP4 is exact30fps.','videoProbe':probe,'backgroundMusic':'music01 cue and original1110 MP3 retained; preview does not simulate original music-player state/volume/loop.','audioTail':'Source MP3s and full-tail WAV retained. MP4 ends at frame283 and may truncate a surviving final effect tail; runtime tail behavior unexecuted.'},indent=2))
print('Created 283-frame side-by-side GIF/30fps MP4, three original cues and full-tail effects mix.')
# Encoding cannot silently drop frames or include MP3 encoder padding.
import wave
with wave.open(str(audio),'rb') as w:
 assert w.getframerate()==44100
 assert w.getnframes()==438616,(w.getnframes(),438616)
gif=Image.open(P/'transform-original-r2.gif');assert gif.n_frames==283
v=next(s for s in probe['streams'] if s['codec_type']=='video');assert v['nb_frames']=='283' and v['avg_frame_rate']=='30/1'
(R/'qa/audio-video-check.json').write_text(json.dumps({'allPassed':True,'mp4Frames':283,'mp4FrameRate':'30/1','mp4Seconds':float(v['duration']),'gifFrames':283,'gifDurationMs':9430,'fullTailAudioRate':44100,'fullTailAudioSamples':438616,'fullTailAudioSeconds':438616/44100,'cueStartsInSamples':[1470,117600,373380],'swfEncoderSeekSamplesApplied':1661,'rawSoundsPreserved':True,'music01ResourcePreservedNotMixed':True},indent=2))
