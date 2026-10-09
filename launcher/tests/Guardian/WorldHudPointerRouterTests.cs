using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class WorldHudPointerRouterTests
{
    private sealed class Input : IWorldHudInput
    {
        internal readonly List<(int Message,Point Point,object Target)> Events=new();
        internal int Cancels;
        public object HitTest(Point point) => point.X<100?"bottom":null;
        public void Dispatch(int message,Point point,uint data,object target) => Events.Add((message,point,target));
        public void Cancel() { Cancels++; }
    }
    private static void Pump(Queue<Action> jobs) { while(jobs.TryDequeue(out var job))job(); }
    [Fact]
    public void HookIntakeDefersDomainWorkAndKeepsMotionBeforeButtonEdges()
    {
        var jobs=new Queue<Action>();var input=new Input();var router=new WorldHudPointerRouter(jobs.Enqueue);
        router.SetInput(input);
        Assert.True(router.TryRoute(0x200,new Point(10,20),0,false));
        Assert.True(router.TryRoute(0x200,new Point(30,20),0,false));
        Assert.True(router.TryRoute(0x201,new Point(30,20),0,false));
        Assert.True(router.TryRoute(0x202,new Point(30,20),0,false));
        Assert.Empty(input.Events);
        Pump(jobs);
        Assert.Equal(new[]{0x200,0x201,0x202},input.Events.Select(x=>x.Message));
        Assert.Equal(new Point(30,20),input.Events[0].Point);
        Assert.False(router.IsDragging);
    }
    [Fact]
    public void GestureCannotChangeOwnersWhileHeldAndDragOutReleaseStaysOnHud()
    {
        var jobs=new Queue<Action>();var input=new Input();var router=new WorldHudPointerRouter(jobs.Enqueue);
        router.SetInput(input);
        Assert.False(router.TryRoute(0x200,new Point(10,20),0,true));
        Assert.False(router.TryRoute(0x202,new Point(10,20),0,true));
        Assert.True(router.TryRoute(0x201,new Point(10,20),0,false));
        Assert.True(router.TryRoute(0x200,new Point(200,20),0,false));
        Assert.True(router.TryRoute(0x202,new Point(200,20),0,false));
        Pump(jobs);
        Assert.Equal(new[]{0x201,0x200,0x202},input.Events.Select(x=>x.Message));
        Assert.Null(input.Events[^1].Target);
        Assert.False(router.TryRoute(0x201,new Point(200,20),0,false));
    }
    [Fact]
    public void CancelDropsQueuedActionsAndRequiresReleaseBeforeNewGesture()
    {
        var jobs=new Queue<Action>();var input=new Input();var router=new WorldHudPointerRouter(jobs.Enqueue);
        router.SetInput(input);router.TryRoute(0x201,new Point(10,20),0,false);
        router.Cancel();router.TryRoute(0x202,new Point(10,20),0,false);
        Pump(jobs);Assert.Empty(input.Events);Assert.Equal(1,input.Cancels);
        router.TryRoute(0x201,new Point(10,20),0,false);router.TryRoute(0x202,new Point(10,20),0,false);
        Pump(jobs);Assert.Equal(new[]{0x201,0x202},input.Events.Select(x=>x.Message));
    }
    [Fact]
    public void RetirementCannotLeakHeldReleaseToFlashAndPhysicalAllUpAllowsFreshOwner()
    {
        var jobs=new Queue<Action>();var input=new Input();var router=new WorldHudPointerRouter(jobs.Enqueue);
        router.SetInput(input);router.TryRoute(0x201,new Point(10,20),0,false);Pump(jobs);
        router.SetInput(null);
        Assert.True(router.TryRoute(0x202,new Point(200,20),0,false));
        Assert.False(router.TryRoute(0x201,new Point(200,20),0,false));
        router.SetInput(input);router.TryRoute(0x201,new Point(10,20),0,false);router.Cancel();
        router.ObserveReleased(0);
        router.TryRoute(0x201,new Point(10,20),0,false);router.TryRoute(0x202,new Point(10,20),0,false);
        Pump(jobs);Assert.Equal(new[]{0x201,0x201,0x202},input.Events.Select(x=>x.Message));
    }
    [Fact]
    public void QueueOverflowCancelsInsteadOfReplayingPartialClicks()
    {
        var jobs=new Queue<Action>();var input=new Input();var router=new WorldHudPointerRouter(jobs.Enqueue);
        router.SetInput(input);
        for(int i=0;i<WorldHudPointerRouter.Capacity+1;i++)router.TryRoute(0x201,new Point(10,20),0,false);
        Pump(jobs);Assert.Empty(input.Events);Assert.Equal(1,input.Cancels);
        Assert.True(router.IsDragging);
        Assert.True(router.TryRoute(0x202,new Point(200,20),0,false));
        Assert.False(router.IsDragging);
    }
}
