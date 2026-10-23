import org.flashNight.gesh.depth.DepthManager;

/** Owned world children participate in the SAME depth manager as living units. */
class org.flashNight.arki.scene.Cf6PropDepthService {
    private static var serial:Number = 0;

    public static function begin(world:MovieClip, identity:Object, owner:Object):Object {
        if (world == undefined || world !== _root.gameworld || world._name == undefined
                || identity == null || owner == null || world.__stageReturnWorldIdentity !== identity
                || DepthManager.instance == undefined) return null;
        var previous:Object = world.__cf6PropDepthSession;
        if (previous != undefined && previous.closed !== true) {
            if (previous.owner === owner && current(previous)) return previous;
            return null;
        }
        var session:Object = {world:world, identity:identity, owner:owner,
            manager:DepthManager.instance, rows:[], closed:false};
        world.__cf6PropDepthSession = session;
        return session;
    }

    private static function finite(value:Number):Boolean {
        return typeof value == "number" && (value-value) == 0;
    }

    private static function current(session:Object):Boolean {
        return session != null && session.closed === false
            && session.world === _root.gameworld && session.world._name != undefined
            && session.identity === session.world.__stageReturnWorldIdentity
            && session.world.__cf6PropDepthSession === session
            && session.manager === DepthManager.instance;
    }

    /** x/y and sortY are final world coordinates. Visual scale/pivot belong to art below holder. */
    public static function create(session:Object, id:String, x:Number, y:Number, sortY:Number):Object {
        if (!current(session) || typeof id != "string" || id == ""
                || !finite(x) || !finite(y) || !finite(sortY)) return null;
        for (var i:Number=0; i<session.rows.length; i++) {
            var prior:Object=session.rows[i];
            if (prior.id === id && prior.closed !== true) {
                if (valid(prior) && prior.x === x && prior.y === y && prior.sortY === sortY) return prior;
                return null;
            }
        }
        var world:MovieClip=session.world;
        var name:String="__cf6Prop"+(++serial);
        // Never replace someone else's clip, even if it uses our naming prefix.
        while (world[name] != undefined) name="__cf6Prop"+(++serial);
        var holder:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
        if (holder == undefined) return null;
        var ticket:Object={session:session,owner:session.owner,id:id,name:name,holder:holder,
            token:{},x:x,y:y,sortY:sortY,closed:false};
        holder.__cf6PropDepthToken=ticket.token;
        holder._x=x; holder._y=y;
        if (!session.manager.updateDepth(holder,sortY)) {
            holder.removeMovieClip();ticket.closed=true;return null;
        }
        session.rows.push(ticket);
        return ticket;
    }

    /** No MovieClip reference alone is an instance identity in AVM1. */
    private static function owns(ticket:Object):Boolean {
        if (ticket == null || ticket.closed === true) return false;
        var session:Object=ticket.session;
        var holder:MovieClip=ticket.holder;
        return session != null && ticket.owner === session.owner
            && session.world._name != undefined
            && session.world.__stageReturnWorldIdentity === session.identity
            && session.world.__cf6PropDepthSession === session
            && holder._parent === session.world && holder._name === ticket.name
            && session.world[ticket.name] === holder
            && holder.__cf6PropDepthToken === ticket.token;
    }

    /** Call before accepting a loader callback and before touching any art child. */
    public static function valid(ticket:Object):Boolean {
        return owns(ticket) && current(ticket.session);
    }

    /** Explicit feed only: no animation clock, pause bypass, actor mutation or effect-layer swap. */
    public static function update(ticket:Object, sortY:Number):Boolean {
        if (!valid(ticket) || !finite(sortY)) return false;
        if (!ticket.session.manager.updateDepth(ticket.holder,sortY)) return false;
        ticket.sortY=sortY;
        return true;
    }

    public static function release(ticket:Object):Void {
        if (ticket == null || ticket.closed === true) return;
        if (owns(ticket)) {
            // A replaced/disposed manager must never be called through an old session.
            if (ticket.session.manager === DepthManager.instance)
                ticket.session.manager.removeMovieClip(ticket.holder);
            ticket.holder.removeMovieClip();
        }
        ticket.closed=true;
    }

    /** Idempotent; safe after world replacement, death, retreat or an interrupted load. */
    public static function end(session:Object):Void {
        if (session == null || session.closed === true) return;
        for (var i:Number=0; i<session.rows.length; i++) release(session.rows[i]);
        if (session.world.__stageReturnWorldIdentity === session.identity
                && session.world.__cf6PropDepthSession === session)
            delete session.world.__cf6PropDepthSession;
        session.closed=true;
        session.rows=[];
    }
}
