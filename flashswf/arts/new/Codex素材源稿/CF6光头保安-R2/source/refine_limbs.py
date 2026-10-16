"""R2 CF6 bald-guard limbs. Hand-authored organic, hard-edged cloth/leather planes.
All geometry is in the original 385 x 321 bitmap-581 pixel coordinate system.
This script never changes part matrices, main build_art.py, or frozen R1 files.
Source alpha is only used to retain existing islands/registration, never colors.
"""
from pathlib import Path
import json, subprocess, concurrent.futures, xml.etree.ElementTree as E
from PIL import Image, ImageDraw, ImageFont
R=Path(__file__).resolve().parents[1]
NS='http://www.w3.org/2000/svg'
CROPS={582:(214,84,297,155),583:(209,156,282,318),584:(318,18,385,158),585:(28,256,127,321),586:(139,43,225,149),587:(297,168,385,246),588:(148,181,198,296),594:(303,254,380,319)}
INK='#111516';BASE='#272a2b';DARK='#191c1d';MID='#303435';LIGHT='#373c3d';HIGH='#3d4142'
def p(d,f,s=None,w=.8):
 return f'<path d="{d}" fill="{f}"'+(f' stroke="{s}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if s else '')+'/>'
def line(d,c=INK,w=.7):return p(d,'none',c,w)
ART={};EDGES={};NOTES={}
# 582: rounded low dress shoe. Broad vamp, heel breast, thin uninterrupted sole.
# No decorative athletic panels, toe stripe, cap-toe seam, or disconnected glint.
h=p('M213 84H298V156H213Z','#1d2022')
h+=p('M221 110C220 101 225 92 234 89C241 86 249 89 251 94C252 99 251 103 254 108C247 103 240 104 235 108C231 112 227 114 223 112Z','#252b2d')
h+=p('M224 103C226 97 231 92 237 91C243 89 248 91 250 94C244 92 236 94 232 99C228 104 227 108 227 111L223 111Z','#2a3032')
h+=p('M222 108C224 112 229 113 232 112C235 113 237 116 240 119C237 115 236 111 237 109C240 105 245 104 250 104C257 106 258 115 263 119C269 123 277 123 283 128C289 133 292 138 292 143C289 148 279 150 269 149C257 148 252 145 247 139C243 134 239 132 235 132C230 135 224 134 220 131C217 126 218 117 222 108Z','#171c1e')
# Quarter is a curved piece of leather which wraps down to the heel.
h+=p('M222 111C222 115 225 117 229 117C233 117 237 120 240 123C238 126 238 130 235 131C228 134 224 132 221 130C220 123 220 116 222 111Z','#23282a')
# The vamp rises continuously from the throat, rounds over the toe, then turns under.
h+=p('M237 109C242 104 248 103 252 106C257 109 256 116 264 120C270 123 276 122 282 127C289 132 293 138 289 142C284 147 273 147 264 144C255 142 251 137 248 131C244 122 242 116 237 109Z','#23292b')
h+=p('M246 108C252 108 253 117 261 122C268 125 273 125 279 128C285 132 289 136 289 139C283 142 276 141 269 138C262 135 259 132 256 128C251 121 250 113 246 108Z','#303638')
h+=p('M264 125C271 124 279 128 284 133C288 137 288 139 285 140C280 140 275 137 272 134C269 130 265 128 264 125Z','#343b3d')
# Sole is darker than leather, only 2 to 3 source pixels deep at the toe.
h+=p('M220 129C225 133 232 134 236 131C242 132 245 138 250 142C258 148 278 151 288 145L292 141L292 145C287 151 275 152 262 149C251 148 248 144 244 139C240 135 238 134 235 135C230 138 223 135 220 133Z','#101416')
h+=p('M221 132C226 135 231 135 235 133L237 134C233 137 226 136 221 134Z','#292f30')
h+=p('M249 143C260 149 280 152 290 146L290 147C280 153 260 151 251 146Z','#2d3334')
h+=line('M223 111C227 114 230 113 232 113C235 114 237 116 239 118M237 109C242 104 247 103 252 105','#101416',.9)
h+=line('M220 130C225 133 231 134 236 132M248 140C257 147 279 150 289 143','#101416',.8)
EDGES[582]='M222 108C219 112 218 118 219 125L220 130C221 133 228 136 233 135C236 135 236 132 240 134C246 138 249 146 260 148C272 151 286 151 292 145L292 139C288 131 282 126 274 123C267 121 262 121 259 117C256 113 256 110 253 107'
ART[582]=h;NOTES[582]='Rounded leather last, one continuous vamp light, dark thin sole and distinct heel breast; ankle insertion left unoutlined.'
# 583: lower trouser. Original illumination is broad center/right, not a left stripe.
h=p('M208 154H284V320H208Z',BASE)
h+=p('M226 173C234 164 242 159 248 160C240 172 237 185 236 204C234 229 231 255 232 272C231 282 230 289 223 296C219 301 220 305 227 308L221 311L215 302C222 293 220 281 221 269L225 215Z',DARK)
h+=p('M245 160C254 160 264 166 267 175L269 228C270 249 270 270 271 284L279 293C266 292 254 291 247 287C243 281 239 277 236 269C235 252 239 237 239 215C239 191 241 176 245 160Z',MID)
h+=p('M250 162C257 166 263 172 265 182C267 203 264 225 266 245C268 260 272 273 274 285C265 288 255 288 248 280C254 264 253 254 251 242C248 224 248 207 249 194C250 181 249 171 247 167Z','#333738')
h+=p('M268 175C270 206 268 231 271 257L272 281C273 291 277 296 277 301L270 306C269 300 265 295 264 289C268 274 267 262 266 247L266 199Z','#202324')
# An asymmetric compression fold, broad at the side, narrows before reaching the center.
h+=p('M222 271C226 276 232 281 241 282C246 283 248 285 251 287C240 286 234 286 230 284C227 282 224 280 222 280Z','#1c2021')
h+=p('M221 285C226 289 233 293 244 295C251 296 260 294 267 291C260 296 251 299 243 299C232 297 226 293 221 292Z','#1a1e20')
h+=p('M220 295C226 297 231 301 240 303C249 305 260 304 271 301L275 305L272 311C262 312 251 312 243 310C232 309 226 307 219 306L216 302Z','#2c3031')
h+=p('M222 299C229 298 235 301 240 303C236 303 232 302 228 302C225 302 223 302 220 302Z','#333738')
h+=p('M225 310C240 313 253 312 265 311L272 309L271 314C256 315 237 314 225 313Z','#222628')
h+=line('M224 288C228 291 234 292 239 293','#15191b',.55)
EDGES[583]='M227 181C225 208 224 240 222 269L220 290C219 295 216 298 215 301L219 309C237 313 255 312 269 313L274 305C274 301 270 291 269 282L268 253C267 223 267 196 266 181'
ART[583]=h;NOTES[583]='Broad right-center cloth light; left weight shadow; two asymmetrical cuff compression folds; no shin stripe or closed knee seam.'
# 584: upper trouser. Open at hip/knee; the broad fabric plane follows the leg.
h=p('M316 17H387V160H316Z',BASE)
h+=p('M321 22L344 23C338 38 334 49 335 63C334 74 338 85 337 96C337 113 341 128 347 143C341 145 335 141 332 135C329 119 329 100 327 83C325 61 323 44 321 22Z',DARK)
h+=p('M347 23L376 23C379 42 376 61 374 80C371 101 374 120 369 140C365 151 367 158 370 164H339C343 147 342 127 343 108C344 93 339 82 341 68C344 51 342 40 347 23Z',MID)
h+=p('M353 23L369 23C375 43 369 59 368 77C366 93 369 108 366 122C364 138 365 150 366 164H348C348 145 350 123 348 105C345 92 348 82 351 72C354 58 352 43 353 23Z','#333738')
h+=p('M376 23L382 23C383 49 378 76 378 100L378 130C376 139 371 146 364 149C372 128 371 115 372 101C371 76 377 52 376 23Z','#202324')
# Soft pressure creases are short and tapered, without disconnected lit rails.
h+=p('M329 61C332 66 336 69 340 69C339 74 338 79 340 84C335 79 332 73 329 61Z','#202425')
h+=p('M334 83C338 86 341 90 344 97C340 94 337 92 334 92Z','#202425')
h+=p('M340 118C342 124 344 129 349 132C344 131 341 127 340 123Z','#242829')
EDGES[584]='M324 35C324 57 328 81 329 101C330 117 331 128 334 137M380 34C380 59 377 79 377 99C377 115 379 127 375 139'
ART[584]=h;NOTES[584]='Neutral wool, wide right-facing thigh plane and short pressure folds; smooth side contours only, open at the hip and knee.'
# 585: continuous trouser seat, with open connected planes rather than a pad.
h=p('M27 254H129V324H27Z',BASE)
# The lit cloth enters from the left/top edges and runs out of the lower crop;
# it never forms a concentric oval or a separate sewn-on pouch.
h+=p('M27 260H91C96 270 100 281 97 292C95 305 92 313 87 318C68 325 42 325 28 307Z',MID)
h+=p('M28 268C51 265 70 266 83 271C89 274 93 279 91 282C80 284 67 282 56 286C43 290 37 295 30 299Z','#333738')
h+=p('M105 265C112 267 118 269 123 272L123 297C123 309 111 316 94 316L87 318C97 308 102 300 103 291C105 281 102 273 100 266Z','#202425')
h+=p('M32 291C33 304 40 313 52 318L68 321C54 315 44 309 41 301C39 294 39 287 39 279L33 281Z','#292d2e')
h+=p('M86 316C94 310 99 305 100 299C103 301 101 306 98 309C95 314 90 317 86 318Z','#15191b')
h+=line('M87 316C94 311 99 306 100 301','#131719',.7)
EDGES[585]='M35 278C34 286 34 296 37 303M122 279C123 289 123 300 119 305'
ART[585]=h;NOTES[585]='Continuous trouser seat with edge-connected soft cloth planes and one curved crotch fold; no oval pad, belt strip, hip sockets, or vertical glint.'
# 586: upper sleeve, diagonally draped from a rounded shoulder.
h=p('M137 41H227V151H137Z',BASE)
h+=p('M189 51C201 45 211 50 215 58C223 68 222 78 218 86C202 107 187 126 171 142C164 149 156 146 152 142C167 130 178 116 186 102C195 88 205 77 205 65C204 57 198 54 189 51Z',DARK)
h+=p('M180 58C190 51 200 49 206 54C210 60 207 68 203 75C194 87 187 100 179 111C173 119 167 124 164 132C162 138 160 141 156 143C149 140 146 135 147 129C150 120 158 108 163 98C169 84 173 69 180 58Z',MID)
h+=p('M184 60C190 56 199 53 204 56C206 60 202 67 198 72C191 81 186 93 179 100C175 105 169 111 165 117C164 108 170 97 174 86C178 76 180 68 184 60Z','#333738')
h+=p('M178 70C180 65 184 61 189 59C188 65 184 70 181 76C178 84 175 91 172 94C173 87 176 77 178 70Z','#373c3d')
h+=p('M150 123C154 120 160 117 165 115C163 119 158 122 156 126C153 129 151 133 151 136C149 134 148 130 150 123Z','#202426')
h+=p('M154 136C158 130 162 127 166 127C164 130 159 134 159 139L156 143Z','#292d2e')
EDGES[586]='M173 66C168 77 165 89 159 100C155 109 149 119 146 127M217 66C220 72 221 79 218 85C208 99 195 115 181 131'
ART[586]=h;NOTES[586]='Broad curved cloth planes from shoulder to elbow, short elbow compression; no hard elbow cap and no closed shoulder/elbow line.'
# 588: forearm sleeve; central rounded light and natural cuff without a ring.
h=p('M145 179H201V299H145Z',BASE)
h+=p('M158 199C163 191 168 187 174 186C169 199 167 213 167 231C167 249 164 265 165 277L161 286L154 285C155 270 153 258 155 245C157 230 157 214 158 199Z',DARK)
h+=p('M174 187C180 188 187 196 188 202C189 220 188 235 190 252C191 263 191 275 191 285C181 291 170 290 162 286C166 274 168 267 167 256C165 240 168 225 168 211C168 200 170 192 174 187Z',MID)
h+=p('M175 190C181 194 183 200 184 209C184 223 182 234 183 245C185 258 187 274 184 287L184 296H167L169 283C172 269 171 256 171 244C170 228 171 214 172 204C173 197 173 193 175 190Z','#333738')
h+=p('M188 203C190 230 191 244 193 264L195 286L188 289C190 276 187 260 187 251C185 235 186 219 188 203Z','#1e2224')
h+=p('M154 274C159 278 162 280 169 281C165 284 159 282 155 280Z','#1c2021')
h+=p('M183 279C185 278 189 277 192 274L192 280C188 283 186 283 183 283Z','#222627')
h+=line('M157 286C168 290 181 291 191 287','#171c1e',.6)
EDGES[588]='M158 201C157 219 157 236 155 254L154 274M188 203C191 228 189 249 193 274'
ART[588]=h;NOTES[588]='Broad forearm fabric volume, slight asymmetric wrist compression and one open cuff edge; no isolated highlight rail.'
# 587: gripping hand. Fingers are bent volumes, palm/thumb overlap finger roots.
h=p('M296 166H389V249H296Z','#1d2224')
# Far index finger passes behind the thumb.
h+=p('M350 196C354 192 359 192 365 197C372 202 378 207 383 210C384 212 380 217 377 218C371 220 360 213 351 206C348 203 347 200 350 196Z','#2c3234')
h+=p('M355 195C360 195 368 201 374 205L380 209C375 209 371 207 366 204C361 201 356 200 353 199Z','#3a4042')
h+=p('M359 207C367 211 374 215 381 213C380 217 377 219 373 218C368 217 362 213 359 211Z','#242a2c')
# Middle finger; rounded bend at the root and a padded distal end.
h+=p('M340 201C343 197 347 199 353 203C358 207 365 211 369 215C373 218 370 223 366 225C363 227 359 224 354 221L338 210C335 208 336 204 340 201Z','#343a3c')
h+=p('M340 201C343 197 347 199 353 203C358 207 365 211 369 215C367 217 363 215 359 213L342 203Q338 202 337 206Q337 203 340 201Z','#3e4547')
h+=p('M340 210C348 216 356 220 363 223C367 224 369 222 371 220C370 224 368 226 364 226C359 225 348 218 339 212Z','#242a2d')
# Ring finger.
h+=p('M330 209C333 205 337 208 343 212C349 216 357 221 360 225C364 228 361 232 358 234C356 235 351 232 347 230C339 225 331 220 328 216C327 214 328 211 330 209Z','#303638')
h+=p('M330 209C333 205 337 208 343 212C349 216 357 221 360 225C356 226 350 222 345 219L333 211Q329 210 328 214Q328 211 330 209Z','#3b4244')
h+=p('M331 218C339 224 350 231 357 232C360 232 361 230 362 229C362 232 359 235 357 235C350 233 338 226 330 220Z','#242b2d')
# Little finger is shorter and tucked beneath, not a fourth equal-width bar.
h+=p('M323 218C326 215 329 218 335 222C341 226 348 230 352 234C356 237 351 241 348 243C339 241 328 233 322 226C320 223 321 221 323 218Z','#2c3335')
h+=p('M323 218C326 215 329 218 335 222C338 224 340 226 342 229C337 228 332 224 327 221Q323 219 322 223Q321 221 323 218Z','#353d3f')
h+=p('M322 225C329 231 340 238 351 239L348 243C339 241 328 233 322 227Z','#232a2c')
# Broad palm masks the roots, and the thumb hooks down over the index/middle grip.
h+=p('M310 203C315 192 326 182 336 179C343 178 350 178 356 180C362 181 363 187 363 192C363 196 361 202 360 207C358 210 355 210 353 207C351 203 351 198 348 195C342 197 339 201 335 205C328 209 322 217 320 222C315 218 312 210 310 203Z','#1c2224')
h+=p('M317 198C324 190 331 185 338 183C345 182 353 182 357 185C353 184 347 186 344 189C340 193 337 195 332 197C327 199 321 203 317 208Z','#262d2f')
h+=p('M350 184C356 182 360 185 361 189C363 194 360 202 358 207C356 209 354 207 354 204C353 200 354 197 352 194C350 191 347 190 347 188Z','#30383b')
h+=p('M356 187C358 188 360 190 360 193C360 197 358 202 357 205C355 202 357 199 356 196C357 192 353 190 356 187Z','#3a4245')
h+=p('M313 204C317 201 325 198 332 198C328 201 323 205 320 210C317 213 317 216 319 221C314 217 311 210 313 204Z','#202729')
h+=line('M323 200C332 199 341 195 348 193C352 196 352 201 354 206C355 209 358 210 360 206','#101719',.8)
# Wrist cuff seam is real, with the insertion cut left open.
h+=p('M301 195C305 185 313 177 322 172C326 174 331 176 334 179C325 184 315 193 310 205Z','#2b3235')
h+=p('M304 193C308 186 314 179 321 176L328 178C320 184 313 191 309 199Z','#383f41')
h+=line('M310 204C314 194 324 185 333 180','#101719',1)
EDGES[587]='M319 172C312 177 305 184 301 194M311 205C313 212 316 217 320 221M322 226C329 234 341 241 348 243C351 241 354 238 355 235M358 234C361 232 363 229 363 226M366 225C370 222 371 219 371 217M377 218C381 214 383 212 383 210C376 206 370 200 364 197M337 179C344 179 352 179 357 181C361 183 363 187 363 193'
ART[587]=h;NOTES[587]='Hooked thumb over four bent padded fingers; length/width hierarchy and curved joints retained; cuff insertion remains open.'
# 594: fist from the back. One swelling hand volume, curled knuckle scallops.
h=p('M301 251H382V322H301Z','#1b2123')
h+=p('M316 281C321 272 327 265 334 263L351 263C357 264 358 269 359 274C365 279 372 282 377 286C377 289 374 292 371 293L365 292C364 296 362 299 359 300C358 305 354 308 352 310L350 315C341 313 331 308 324 301C319 295 315 289 316 281Z','#202729')
h+=p('M328 275C334 269 343 267 350 268C355 269 356 274 359 279C363 282 367 283 369 286C363 287 360 291 358 295C354 299 350 301 347 307C345 309 343 309 339 307C329 302 321 293 322 286C322 281 325 278 328 275Z','#2a3235')
h+=p('M339 270C345 268 350 269 352 273C353 277 353 282 356 285C355 290 351 294 347 295C343 291 344 287 344 282C344 276 341 273 339 270Z','#323b3e')
# Knuckle row follows the diagonal curling edge; the shades connect naturally.
h+=p('M358 282C363 283 365 286 363 289C359 294 356 298 352 301C348 304 347 307 344 308C341 306 342 301 345 298C350 293 352 288 354 285Z','#384145')
h+=p('M356 285C359 284 360 286 359 288C357 291 355 293 353 294C352 292 354 288 356 285Z','#3b4447')
h+=p('M350 297C351 299 349 301 347 303L345 304C345 302 347 299 350 297Z','#3a4346')
h+=p('M363 279C367 281 373 284 377 286C376 289 374 290 371 290C368 288 365 286 362 286C362 284 363 281 363 279Z','#2d3538')
h+=p('M317 287C323 297 334 308 347 311L352 308L350 315C339 312 328 307 322 299C319 295 317 291 317 287Z','#171e20')
h+=p('M354 303C359 299 362 294 365 291L366 293C364 297 361 300 359 300C357 305 355 307 352 310L351 312C351 308 351 306 354 303Z','#1c2326')
h+=line('M365 292C361 293 359 296 358 299M358 300C355 300 352 303 351 306','#172023',.6)
# Glove cuff has only the true diagonal opening seam, no line on the arm insertion.
h+=p('M307 279C308 270 314 262 322 258C326 260 329 262 332 263C325 270 318 278 315 287Z','#2b3235')
h+=p('M310 276C313 269 317 264 322 261L327 263C320 269 316 275 313 282Z','#363d40')
h+=line('M315 287C317 279 325 269 332 264','#101719',.9)
EDGES[594]='M319 260C313 265 308 271 307 279M316 288C320 299 334 310 350 314C353 310 354 307 358 304M365 293C369 293 372 294 374 291M377 286C371 281 363 278 359 274C357 270 358 266 352 263L335 263'
ART[594]=h;NOTES[594]='Continuous fist-back mass, a diagonal row of curled knuckles and restrained finger creases; no floating angular plates.'

def main():
 out=R/'source/limbs-r2.json'; prev=R/'previews/limbs';prev.mkdir(parents=True,exist_ok=True)
 # The original topology is stored alongside this script to allow cold reconstruction.
 contour=R/'source/limb-reference-geometry.json'
 if not contour.exists():raise FileNotFoundError('Required packaged input source/limb-reference-geometry.json is missing.')
 boundaries=json.loads(contour.read_text());export={}
 for cid in CROPS:
  clip=f'limb_r2_{cid}';boundary=boundaries[str(cid)]['boundary'];source_edge=boundaries[str(cid)]['openOutline']
  body=f'<defs><clipPath id="{clip}"><path d="{boundary}" fill-rule="evenodd"/></clipPath></defs><g clip-path="url(#{clip})">'+ART[cid]+line(source_edge,'#111719',.65)+'</g>'
  export[str(cid)]={'id':cid,'body':body,'boundary':boundary,'openOutline':source_edge,'scope':NOTES[cid],'atlasSize':[385,321],'atlasCrop':CROPS[cid]}
  x,y,X,Y=CROPS[cid];w=X-x;h=Y-y
  (prev/f'r2-{cid}.svg').write_text(f'<svg xmlns="{NS}" viewBox="{x} {y} {w} {h}" width="{w*8}" height="{h*8}">{body}</svg>')
 out.write_text(json.dumps(export,ensure_ascii=False,indent=2))
 def render(cid):
  f=prev/f'r2-{cid}.svg';subprocess.run(['inkscape',str(f),'--export-filename='+str(f.with_suffix('.png'))],check=True,capture_output=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(render,CROPS))
 original=Image.open(R/'reference/581.png').convert('RGBA')
 old={cid:{'body':value['r1Body']} for cid,value in boundaries.items()}
 manifest={x['id']:x for x in json.loads((R/'reference/shape-manifest.json').read_text())}
 checks=[]
 for cid,crop in CROPS.items():
  x,y,X,Y=crop;w=X-x;h=Y-y;s=6
  # Render R1 body separately so neighboring atlas islands never contaminate comparisons.
  f=prev/f'r1-isolated-{cid}.svg';f.write_text(f'<svg xmlns="{NS}" viewBox="{x} {y} {w} {h}" width="{w*8}" height="{h*8}">{old[str(cid)]["body"]}</svg>')
  subprocess.run(['inkscape',str(f),'--export-filename='+str(f.with_suffix('.png'))],check=True,capture_output=True)
  # Original crop isolated with the exact alpha contour, so no neighboring shoe/sleeve fragments.
  # This mask has no effect on the intended original part's visible pixels.
  masksvg=prev/f'original-mask-{cid}.svg';masksvg.write_text(f'<svg xmlns="{NS}" viewBox="{x} {y} {w} {h}" width="{w*8}" height="{h*8}"><path d="{boundaries[str(cid)]['boundary']}" fill="white"/></svg>')
  subprocess.run(['inkscape',str(masksvg),'--export-filename='+str(masksvg.with_suffix('.png'))],check=True,capture_output=True)
  orig=original.crop(crop).resize((w*8,h*8),Image.Resampling.LANCZOS);mask=Image.open(masksvg.with_suffix('.png')).getchannel('A')
  from PIL import ImageChops
  orig.putalpha(ImageChops.multiply(orig.getchannel('A'),mask))
  ims=[orig,Image.open(f.with_suffix('.png')).convert('RGBA'),Image.open(prev/f'r2-{cid}.png').convert('RGBA')]
  board=Image.new('RGB',(w*s*3+80,h*s+98),'#c2c1b9');d=ImageDraw.Draw(board)
  labels=['ORIGINAL / bitmap 581','R1 / frozen','R2 / organic hard edges']
  for i,im in enumerate(ims):
   im=im.resize((w*s,h*s),Image.Resampling.LANCZOS);xx=20+i*(w*s+20);board.paste(im,(xx,55),im);d.text((xx,18),f'{cid}  {labels[i]}',fill='#202526')
  d.text((20,h*s+71),f'Identical atlas crop {crop}; source atlas 385 x 321. No transforms changed.',fill='#303638')
  board.save(prev/f'comparison-{cid}.png')
  # The replacement itself contains no raster images/gradients/filters.
  assert '<image' not in export[str(cid)]['body'] and '<linearGradient' not in export[str(cid)]['body'] and '<filter' not in export[str(cid)]['body']
  checks.append({'id':cid,'originalViewBox':manifest[cid]['viewBox'],'originalBitmapMatrix':manifest[cid]['fills'][0]['matrix'],'paths':export[str(cid)]['body'].count('<path'),'svgElements':'paths, g, defs, clipPath only','geometryPixels':[385,321],'notes':NOTES[cid]})
 (R/'qa/limbs-r2-checks.json').write_text(json.dumps(checks,indent=2))
 print('Wrote',out,'and 8 three-column comparison PNGs. Parent must preserve original part wrappers/matrices.')
if __name__=='__main__':main()
