/* 过场「像素传输」叠层：旧封面人物呼吸动画（sprite/标题画面/Symbol 988）在 U12 过场上的呈现。
 * 资产与来源见 assets/breathing/manifest.json；8 分件 + 121 帧逐帧矩阵，30fps 约 4 秒循环。
 * 人物是数据、加载即投送：传输进度 txP 渐近爬到 0.9 停住，真实就绪由主模块撤幕（不等动画播完）。
 * 纯视觉层：不读写协议消息，不产生回执；reduced-motion 下呼吸定格第 0 帧、无传输运动。 */
(function () {
    'use strict';
    var W=1024,H=576,ASSET='assets/breathing/';
    var ready=false,failed=false,loading=false,manifest=null,frames=null;
    var parts=[],backdropImg=null;
    var canvas=null,ctx=null,fig=null,sample=null;
    var active=false,stateKey='',txP=0,raf=0,last=0,breathBase=0;
    var rmQuery=window.matchMedia?window.matchMedia('(prefers-reduced-motion: reduce)'):{matches:false};

    function mulM(o,i){return [o[0]*i[0]+o[2]*i[1],o[1]*i[0]+o[3]*i[1],
        o[0]*i[2]+o[2]*i[3],o[1]*i[2]+o[3]*i[3],
        o[0]*i[4]+o[2]*i[5]+o[4],o[1]*i[4]+o[3]*i[5]+o[5]];}
    function clamp(v,a,b){return v<a?a:v>b?b:v;}
    function hash3(x,y,b){var h=(x*73856093)^(y*19349663)^(b*83492791);h^=h>>>13;h=Math.imul(h,0x5bd1e995);h^=h>>>15;return h>>>0;}

    function load(){
        if(ready||failed||loading)return;
        if(!canvas)return;
        loading=true;
        fetch(ASSET+'manifest.json').then(function(r){return r.json();}).then(function(mf){
            manifest=mf;
            return fetch(ASSET+'timeline.json').then(function(r){return r.json();});
        }).then(function(tl){
            // 关键帧区间展开为逐帧矩阵
            frames=tl.layers.map(function(L){
                var fr=new Array(tl.frameCount);
                L.keyframes.forEach(function(kf){
                    var m=kf.matrix,row=[m.a,m.b,m.c,m.d,m.tx,m.ty];
                    for(var f=kf.index;f<Math.min(kf.index+kf.duration,tl.frameCount);f++)fr[f]=row;
                });
                return fr;
            });
            var loaders=manifest.layers.map(function(L,i){
                return new Promise(function(resolve,reject){
                    var im=new Image();
                    im.onload=function(){parts[i]={img:im,s:L.s,tx:L.tx,ty:L.ty};resolve();};
                    im.onerror=reject;
                    im.src=ASSET+L.file;
                });
            });
            if(manifest.backdrop)loaders.push(new Promise(function(resolve,reject){
                var im=new Image();
                im.onload=function(){backdropImg=im;resolve();};
                im.onerror=reject;
                im.src=ASSET+manifest.backdrop.file;
            }));
            return Promise.all(loaders);
        }).then(function(){
            fig=document.createElement('canvas');fig.width=W;fig.height=H;
            sample=document.createElement('canvas');
            ready=true;loading=false;
            if(canvas)canvas.hidden=!active;
            if(active)start();
        }).catch(function(){failed=true;loading=false;});
    }

    function drawFigure(c,fi,M){
        for(var li=7;li>=0;li--){
            var p=parts[li],m=mulM(M,mulM(frames[li][fi],[p.s,0,0,p.s,p.tx,p.ty]));
            c.setTransform(m[0],m[1],m[2],m[3],m[4],m[5]);
            c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';
            c.drawImage(p.img,0,0);
            if(li===manifest.badge.layer){
                var bm=mulM(M,mulM(frames[li][fi],manifest.badge.m));
                c.setTransform(bm[0],bm[1],bm[2],bm[3],bm[4],bm[5]);
                c.fillStyle=manifest.badge.color;
                c.beginPath();
                manifest.badge.polys.forEach(function(poly){
                    poly.forEach(function(pt,i){if(i)c.lineTo(pt[0],pt[1]);else c.moveTo(pt[0],pt[1]);});
                    c.closePath();
                });
                c.fill();
            }
        }
        c.setTransform(1,0,0,1,0,0);
    }

    function render(fi){
        // 旧封面背景（bitmap961）+ 压暗层，维持旧标题画面观感
        if(backdropImg){
            var bm=manifest.backdrop.m;
            ctx.setTransform(bm[0],bm[1],bm[2],bm[3],bm[4],bm[5]);
            ctx.drawImage(backdropImg,0,0);
            ctx.setTransform(1,0,0,1,0,0);
            ctx.fillStyle='rgba(5,7,10,'+manifest.backdrop.dim+')';
        }else{
            ctx.fillStyle='#05070a';
        }
        ctx.fillRect(0,0,W,H);
        var fc=fig.getContext('2d');
        fc.clearRect(0,0,W,H);
        drawFigure(fc,fi,manifest.framing.m);
        var cell=8,gw=Math.ceil(W/cell),gh=Math.ceil(H/cell);
        sample.width=gw;sample.height=gh;
        var sc=sample.getContext('2d');
        sc.drawImage(fig,0,0,gw,gh);
        var d=sc.getImageData(0,0,gw,gh).data;
        for(var gy=0;gy<gh;gy++)for(var gx=0;gx<gw;gx++){
            var o=(gy*gw+gx)*4,a=d[o+3];
            if(a<24)continue;
            var hd=hash3(gx,gy,7919),h01=(hd%1000)/1000;
            var cx=gx*cell,cy=gy*cell;
            var th=clamp((1-gy/gh)*0.72+h01*0.28,0,1);
            if(txP<=th){
                ctx.globalAlpha=1;
                ctx.drawImage(fig,cx,cy,cell,cell,cx,cy,cell,cell);
                var flash=clamp((txP-(th-0.06))/0.06,0,1)*0.85;
                if(flash>0.02){
                    ctx.globalAlpha=flash*0.38*(a/255);
                    ctx.fillStyle='#8be0f1';
                    ctx.fillRect(cx,cy,cell,cell);
                }
                continue;
            }
            var rel=txP-th;
            if(rel<0.22&&((hd>>4)%1000)/1000<0.5){
                var k=rel/0.22,r=d[o],gg=d[o+1],bb=d[o+2],mix=0.45+0.35*k;
                ctx.globalAlpha=(1-k)*0.9*(a/255);
                ctx.fillStyle='rgb('+Math.round(r+(139-r)*mix)+','+Math.round(gg+(213-gg)*mix)+','+Math.round(bb+(241-bb)*mix)+')';
                ctx.fillRect(cx+((hd>>9)%5-2)*k*4,cy-k*46,cell,cell);
            }
        }
        ctx.globalAlpha=1;
    }

    function tick(now){
        var dt=last?Math.min(200,now-last):16;last=now;
        var rm=rmQuery.matches;
        if(!rm){
            breathBase+=dt;
            // 就绪即收尾：撤幕的 210ms 内把传输补完——他不是被剪断，是传完入场
            if(finishing){
                txP=Math.min(1,txP+dt/200);
            }else if(currentPhase!=='error'&&currentConnected!==false){
                txP=Math.min(0.9,txP+((0.9-txP)*0.28+0.012)*dt/1000);
            }
        }
        render(rm?0:Math.floor(breathBase*30/1000)%121);
        raf=requestAnimationFrame(tick);
    }

    var currentPhase='cover',currentConnected=true,finishing=false;
    function start(){
        if(raf)return;
        last=0;
        raf=requestAnimationFrame(tick);
    }
    function stop(){
        if(raf)cancelAnimationFrame(raf);raf=0;
    }

    /* st: {active, key, phase, connected}；key 变化=新一轮过场，传输进度归零。 */
    function sync(st){
        if(!canvas)return;
        if(st&&st.active){
            if(st.key!==stateKey){stateKey=st.key;txP=0;breathBase=0;}
            currentPhase=st.phase||'cover';
            currentConnected=st.connected!==false;
            finishing=st.phase==='reveal'&&st.revealAllowed===true;
            active=true;
            load();
            if(ready){canvas.hidden=false;start();}
        }else{
            active=false;
            canvas.hidden=true;
            stop();
        }
    }

    window.TransitionBreathing={
        /* 由 scene-transition.js 在场景加载完成后挂接画布。 */
        attach:function(el){
            canvas=el;ctx=canvas.getContext('2d');
            canvas.hidden=true;
            if(ready)canvas.hidden=!active;
        },
        sync:sync,
        /* 仅供诊断：当前是否已就绪/失败。 */
        status:function(){return {ready:ready,failed:failed,active:active,txP:txP};}
    };
})();
