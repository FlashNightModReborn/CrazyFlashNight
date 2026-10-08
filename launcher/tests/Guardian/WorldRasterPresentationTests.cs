using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldRasterPresentationTests
    {
        private sealed class Scene : IWorldRasterScene
        {
            internal readonly List<(IntPtr Pixels, int Width, int Height, int Stride, int X, int Y)> Uploads = new();
            internal bool Fail;
            public void UploadHud(IntPtr pixels, int width, int height, int stride, int x, int y)
            {
                if (Fail) throw new InvalidOperationException("fixture device loss");
                Uploads.Add((pixels,width,height,stride,x,y));
            }
        }

        [Fact]
        public void Cropping_UsesPhysicalDesktopCoordinatesAndOriginalDibStride()
        {
            var region = WorldRasterRegion.Clip(new Rectangle(-15, 30, 30, 20),new Rectangle(-10, 35, 100, 80),128);
            Assert.Equal(new WorldRasterRegion(25,15,0,0,660),region);
        }

        [Fact]
        public void FrameUpload_DoesNotCopyPixelsOrRequireASeparateWindow()
        {
            using var presenter = new WorldRasterPresentation();
            var scene = new Scene();
            presenter.Adopt(scene,new Rectangle(100,200,300,200),true);
            IntPtr pixels = new IntPtr(4096);
            Assert.True(presenter.TryPresent(pixels,30,20,128,new Point(110,220)));
            var upload = Assert.Single(scene.Uploads);
            Assert.Equal(pixels,upload.Pixels);
            Assert.Equal(10,upload.X); Assert.Equal(20,upload.Y);
            Assert.Equal(128,upload.Stride);
            Assert.Equal(2400UL,presenter.UploadedBytes);
        }

        [Fact]
        public void UnavailableOutput_NeverRetainsOrUploadsASourcePointer()
        {
            using var presenter = new WorldRasterPresentation();
            var scene = new Scene();
            presenter.Adopt(scene,new Rectangle(0,0,100,100),false);
            Assert.False(presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty));
            Assert.Empty(scene.Uploads);
        }

        [Fact]
        public void HideAndSourceReplacement_ClearOldPixelsOnce()
        {
            using var presenter = new WorldRasterPresentation();
            var first = new Scene(); var next = new Scene();
            presenter.Adopt(first,new Rectangle(0,0,100,100),true);
            presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty);
            presenter.Adopt(next,new Rectangle(0,0,100,100),true);
            Assert.Equal(2,first.Uploads.Count);
            var clear = first.Uploads[1];
            Assert.Equal(1,clear.Width); Assert.Equal(1,clear.Height);
            Assert.Equal(0,Marshal.ReadInt32(clear.Pixels));
            presenter.Hide();
            Assert.Empty(next.Uploads);
        }

        [Fact]
        public void DeviceFailure_RetiresTheRasterBeforeNotifyingTheOwner()
        {
            using var presenter = new WorldRasterPresentation();
            var scene = new Scene { Fail=true };
            presenter.Adopt(scene,new Rectangle(0,0,100,100),true);
            int failures = 0;
            presenter.Faulted += _ => { Assert.False(presenter.IsAvailable); failures++; };
            Assert.True(presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty));
            Assert.Equal(1,failures);
            Assert.False(presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty));
        }

        [Fact]
        public void ClearFailureCannotReadoptASceneRetiredByReentrantOwnerTeardown()
        {
            using var presenter = new WorldRasterPresentation();
            var first = new Scene(); var next = new Scene();
            presenter.Adopt(first,new Rectangle(0,0,100,100),true);
            presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty);
            first.Fail=true;
            presenter.Faulted += _ => presenter.Adopt(null,Rectangle.Empty,false);
            presenter.Adopt(next,new Rectangle(0,0,100,100),true);
            Assert.False(presenter.IsAvailable);
            Assert.False(presenter.TryPresent(new IntPtr(1),20,20,80,Point.Empty));
            Assert.Empty(next.Uploads);
        }
    }
}
