// Ground routes are requested only for a genuinely blocked firing lane.
// The real Mover remains responsible for every step, including route steps.
cf6NavSegment=function(x:Number,z:Number,ex:Number,ez:Number):Boolean {
    var dx:Number=ex-x,dz:Number=ez-z;
    var n:Number=Math.max(1,Math.ceil(Math.sqrt(dx*dx+dz*dz)/8));
    var sx:Number=dx/n,sz:Number=dz/n;
    for(var k:Number=1;k<n;k++){
        x+=sx;z+=sz;
        if(!this.cf6Ground.isPointValid(x,z))return false;
    }
    return this.cf6Ground.isPointValid(ex,ez);
};
// How much of the preferred stand-off actually has a clear shot back to the
// player? A point beyond a pillar on the same lane is not a firing position.
cf6NavSpace=function(tx:Number,tz:Number,side:Number,desired:Number):Number {
    var edge:Number=side>0?_root.Xmax-8-tx:tx-_root.Xmin-8;
    var end:Number=Math.max(0,Math.min(desired,edge)),last:Number=0;
    for(var d:Number=8;d<end;d+=8){
        if(!this.cf6Ground.isPointValid(tx+side*d,tz))return Math.max(0,last-4);
        last=d;
    }
    return this.cf6Ground.isPointValid(tx+side*end,tz)?end:Math.max(0,last-4);
};
// Most rooms need only a horizontal-then-vertical or vertical-then-horizontal
// detour. More complex layouts share one lazily sampled grid per map/revision.
cf6NavGridRoute=function(room:Object,revision:Number,ex:Number,ez:Number):Array {
    var g:Object=room.groundNavigation;
    if(g==null || g.revision!==revision || g.layer!==_root.collisionLayer){
        var width:Number=_root.Xmax-_root.Xmin,height:Number=_root.Ymax-_root.Ymin;
        if(!(width>0) || !(height>0))return null;
        var cs:Number=Math.max(24,Math.ceil(Math.sqrt(width*height/3000)));
        var cols:Number=Math.ceil(width/cs),rows:Number=Math.ceil(height/cs);
        if(cols*rows>4096)return null;
        var gridClass:Function=_global.org.flashNight.neur.Navigation.AStarGrid;
        g={map:new gridClass(cols,rows,true,false),cols:cols,rows:rows,cell:cs,at:0,
            revision:revision,layer:_root.collisionLayer};room.groundNavigation=g;
    }
    var total:Number=g.cols*g.rows,limit:Number=Math.min(total,g.at+96);
    while(g.at<limit){
        var col:Number=g.at%g.cols,row:Number=Math.floor(g.at/g.cols);g.at++;
        var wx:Number=_root.Xmin+(col+.5)*g.cell,wz:Number=_root.Ymin+(row+.5)*g.cell;
        if(wx>_root.Xmax || wz>_root.Ymax || !this.cf6Ground.isPointValid(wx,wz))g.map.setWalkable(col,row,false);
    }
    if(g.at<total)return null;
    var sc:Number=Math.min(g.cols-1,Math.max(0,Math.floor((this._x-_root.Xmin)/g.cell)));
    var sr:Number=Math.min(g.rows-1,Math.max(0,Math.floor((this.Z轴坐标-_root.Ymin)/g.cell)));
    var ec:Number=Math.min(g.cols-1,Math.max(0,Math.floor((ex-_root.Xmin)/g.cell)));
    var er:Number=Math.min(g.rows-1,Math.max(0,Math.floor((ez-_root.Ymin)/g.cell)));
    var cells:Array=g.map.find(sc,sr,ec,er,Math.min(384,total));
    if(cells==null)return null;
    var path:Array=[];
    for(var i:Number=1;i<cells.length;i++){
        var cell:Object=cells[i],next:Object=cells[i+1],prev:Object=cells[i-1];
        if(next!=null && next.x-cell.x==cell.x-prev.x && next.y-cell.y==cell.y-prev.y)continue;
        path.push({x:_root.Xmin+(cell.x+.5)*g.cell,z:_root.Ymin+(cell.y+.5)*g.cell});
    }
    path.push({x:ex,z:ez});return path;
};
cf6NavWaypoint=function(target:MovieClip,o:Object,preferred:Number):Object {
    var plan:Object=this.cf6GroundRoute,frame:Number=o.frame;
    if(plan==null && this.cf6NavStalls<3 && !o.obstructed)return null;
    var revision:Number=this.cf6Collision.revision;
    if(plan!=null){
        if(plan.target!==target || plan.version!==target.version || plan.revision!==revision
            || plan.layer!==_root.collisionLayer || frame>plan.expires
            || Math.abs(plan.tx-target._x)>64 || Math.abs(plan.tz-target.Z轴坐标)>24){
            this.cf6GroundRoute=null;plan=null;
        }else{
            var wp:Object=plan.points[plan.index];
            while(wp!=null && Math.abs(wp.x-this._x)<=1 && Math.abs(wp.z-this.Z轴坐标)<=1){
                plan.index++;wp=plan.points[plan.index];plan.best=100000;plan.progress=frame;
            }
            if(wp==null){
                this.cf6GroundRoute=null;this.cf6NavStalls=0;this.cf6NavRetry=frame+12;return null;
            }
            var remaining:Number=Math.abs(wp.x-this._x)+Math.abs(wp.z-this.Z轴坐标);
            if(remaining<plan.best-1){plan.best=remaining;plan.progress=frame;}
            if(frame-plan.progress<=18)return wp;
            this.cf6GroundRoute=null;this.cf6NavRetry=frame+8;return null;
        }
    }
    var room:Object=this.cf6ActionApi.context();
    if(room==null || frame<this.cf6NavRetry || frame<room.groundNextPlan)return null;
    room.groundNextPlan=frame+4;this.cf6NavRetry=frame+12;
    var tx:Number=target._x,tz:Number=target.Z轴坐标;
    if(!this.cf6Ground.isPointValid(tx,tz))return null;
    var side:Number=o.flank!=null?o.flank.side:(this._x<tx?-1:1);
    var span:Number=this.cf6NavSpace(tx,tz,side,preferred);
    if(span<Math.min(120,preferred*.6)){
        var opposite:Number=this.cf6NavSpace(tx,tz,-side,preferred);
        if(opposite>span){side=-side;span=opposite;}
    }
    var ex:Number=tx+side*span,x:Number=this._x,z:Number=this.Z轴坐标;
    var points:Array=null;
    if(this.cf6NavSegment(x,z,ex,z) && this.cf6NavSegment(ex,z,ex,tz))points=[{x:ex,z:z},{x:ex,z:tz}];
    else if(this.cf6NavSegment(x,z,x,tz) && this.cf6NavSegment(x,tz,ex,tz))points=[{x:x,z:tz},{x:ex,z:tz}];
    else points=this.cf6NavGridRoute(room,revision,ex,tz);
    if(points==null || points.length==0)return null;
    this.cf6GroundRoute={target:target,version:target.version,revision:revision,layer:_root.collisionLayer,
        points:points,index:0,tx:tx,tz:tz,expires:frame+240,best:100000,progress:frame};
    this.cf6NavPlans++;return points[0];
};
