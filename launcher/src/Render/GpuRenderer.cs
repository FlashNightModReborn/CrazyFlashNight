using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Threading;
using CF7Launcher.Guardian;
using SharpDX;
using SharpDX.Direct3D;
using SharpDX.Direct3D11;
using SharpDX.DXGI;
using D3DBuffer = SharpDX.Direct3D11.Buffer;
using D3DDevice = SharpDX.Direct3D11.Device;

namespace CF7Launcher.Render
{
    class GpuRenderer : IDisposable
    {
        private D3DDevice _device;
        private DeviceContext _context;

        private VertexShader _vertexShader;
        private PixelShader _pixelShader;
        private SamplerState _sampler;
        private D3DBuffer _casParamsCB;

        private Texture2D _inputTexture;
        private ShaderResourceView _inputSRV;

        private Texture2D _outputTexture;
        private RenderTargetView _outputRTV;
        private Texture2D _stagingTexture;

        private Bitmap _captureBitmap;
        private Bitmap _outputBitmap;
        private readonly object _outputLock = new object();
        private int _captureWidth;
        private int _captureHeight;
        private IntPtr _flashHwnd;

        private Thread _renderThread;
        private volatile bool _stop;
        private volatile float _sharpness = 0.5f;

        public event Action OnFallbackRequested;

        public float Sharpness
        {
            get { return _sharpness; }
            set { _sharpness = Math.Max(0f, Math.Min(1f, value)); }
        }

        public int CaptureWidth { get { return _captureWidth; } }
        public int CaptureHeight { get { return _captureHeight; } }

        public Bitmap GetOutputFrame()
        {
            lock (_outputLock)
            {
                return _outputBitmap;
            }
        }

        public bool DrawOutput(Graphics g, Rectangle destRect)
        {
            lock (_outputLock)
            {
                if (_outputBitmap == null)
                    return false;

                Rectangle drawRect = GetAspectFitRect(destRect, _outputBitmap.Width, _outputBitmap.Height);
                if (drawRect.Width <= 0 || drawRect.Height <= 0)
                    return false;

                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(_outputBitmap, drawRect);
                return true;
            }
        }

        public bool Init(int captureW, int captureH)
        {
            _captureWidth = captureW;
            _captureHeight = captureH;

            try
            {
                FeatureLevel[] featureLevels = new FeatureLevel[]
                {
                    FeatureLevel.Level_11_0,
                    FeatureLevel.Level_10_1,
                    FeatureLevel.Level_10_0
                };

                bool created = false;
                DriverType[] drivers = { DriverType.Hardware, DriverType.Warp };
                foreach (DriverType driver in drivers)
                {
                    try
                    {
                        _device = new D3DDevice(driver, DeviceCreationFlags.None, featureLevels);
                        created = true;
                        LogManager.Log("[GpuRenderer] Device: " + driver + " FL=" + _device.FeatureLevel);
                        break;
                    }
                    catch (Exception ex)
                    {
                        LogManager.Log("[GpuRenderer] " + driver + " failed: " + ex.Message);
                    }
                }

                if (!created)
                    return false;

                _context = _device.ImmediateContext;

                Texture2DDescription inputDesc = new Texture2DDescription();
                inputDesc.Width = captureW;
                inputDesc.Height = captureH;
                inputDesc.MipLevels = 1;
                inputDesc.ArraySize = 1;
                inputDesc.Format = Format.B8G8R8A8_UNorm;
                inputDesc.SampleDescription = new SampleDescription(1, 0);
                inputDesc.Usage = ResourceUsage.Default;
                inputDesc.BindFlags = BindFlags.ShaderResource;
                _inputTexture = new Texture2D(_device, inputDesc);
                _inputSRV = new ShaderResourceView(_device, _inputTexture);

                Texture2DDescription outputDesc = inputDesc;
                outputDesc.BindFlags = BindFlags.RenderTarget;
                _outputTexture = new Texture2D(_device, outputDesc);
                _outputRTV = new RenderTargetView(_device, _outputTexture);

                Texture2DDescription stagingDesc = inputDesc;
                stagingDesc.Usage = ResourceUsage.Staging;
                stagingDesc.BindFlags = BindFlags.None;
                stagingDesc.CpuAccessFlags = CpuAccessFlags.Read;
                _stagingTexture = new Texture2D(_device, stagingDesc);

                if (!CreateShaders())
                    return false;

                SamplerStateDescription sd = new SamplerStateDescription();
                sd.Filter = Filter.MinMagMipLinear;
                sd.AddressU = TextureAddressMode.Clamp;
                sd.AddressV = TextureAddressMode.Clamp;
                sd.AddressW = TextureAddressMode.Clamp;
                sd.ComparisonFunction = Comparison.Never;
                sd.MaximumAnisotropy = 1;
                sd.MaximumLod = float.MaxValue;
                _sampler = new SamplerState(_device, sd);

                BufferDescription cbd = new BufferDescription();
                cbd.SizeInBytes = 16;
                cbd.Usage = ResourceUsage.Default;
                cbd.BindFlags = BindFlags.ConstantBuffer;
                _casParamsCB = new D3DBuffer(_device, cbd);

                _captureBitmap = new Bitmap(captureW, captureH, PixelFormat.Format32bppArgb);
                _outputBitmap = new Bitmap(captureW, captureH, PixelFormat.Format32bppArgb);

                LogManager.Log("[GpuRenderer] Init complete (off-screen): " + captureW + "x" + captureH);
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuRenderer] Init failed: " + ex.Message);
                Dispose();
                return false;
            }
        }

        public void StartRenderLoop(IntPtr flashHwnd)
        {
            _flashHwnd = flashHwnd;
            _stop = false;
            _renderThread = new Thread(RenderThreadProc);
            _renderThread.IsBackground = true;
            _renderThread.Name = "GpuRenderThread";
            _renderThread.Start();
        }

        public void RequestStop()
        {
            _stop = true;
            if (_renderThread != null
                && _renderThread.IsAlive
                && Thread.CurrentThread != _renderThread)
            {
                _renderThread.Join(3000);
            }
        }

        private void RenderThreadProc()
        {
            LogManager.Log("[GpuRenderer] Render thread started");
            int consecutiveFailures = 0;
            int frameCount = 0;

            while (!_stop)
            {
                try
                {
                    bool captured = CaptureFrame();
                    if (!captured)
                    {
                        consecutiveFailures++;
                        if (consecutiveFailures >= 10)
                        {
                            LogManager.Log("[GpuRenderer] 10 consecutive failures, fallback");
                            Action handler = OnFallbackRequested;
                            if (handler != null)
                                handler();
                            return;
                        }

                        Thread.Sleep(33);
                        continue;
                    }

                    consecutiveFailures = 0;

                    UploadTexture();
                    RenderCAS();
                    ReadbackOutput();

                    frameCount++;
                    if (frameCount == 1)
                        LogManager.Log("[GpuRenderer] First frame processed OK");

                    Thread.Sleep(33);
                }
                catch (SharpDXException ex)
                {
                    LogManager.Log("[GpuRenderer] D3D error: " + ex.Message);
                    Action handler = OnFallbackRequested;
                    if (handler != null)
                        handler();
                    return;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[GpuRenderer] Error: " + ex.Message);
                    Thread.Sleep(33);
                }
            }

            LogManager.Log("[GpuRenderer] Render thread stopped");
        }

        private bool CaptureFrame()
        {
            if (_flashHwnd == IntPtr.Zero)
                return false;

            IntPtr srcDC = RenderNativeMethods.GetDC(_flashHwnd);
            if (srcDC == IntPtr.Zero)
                return false;

            try
            {
                using (Graphics g = Graphics.FromImage(_captureBitmap))
                {
                    IntPtr dstDC = g.GetHdc();
                    bool ok = RenderNativeMethods.BitBlt(
                        dstDC,
                        0,
                        0,
                        _captureWidth,
                        _captureHeight,
                        srcDC,
                        0,
                        0,
                        RenderNativeMethods.SRCCOPY);
                    g.ReleaseHdc(dstDC);
                    return ok;
                }
            }
            finally
            {
                RenderNativeMethods.ReleaseDC(_flashHwnd, srcDC);
            }
        }

        private void UploadTexture()
        {
            BitmapData bd = _captureBitmap.LockBits(
                new Rectangle(0, 0, _captureWidth, _captureHeight),
                ImageLockMode.ReadOnly,
                PixelFormat.Format32bppArgb);
            try
            {
                _context.UpdateSubresource(_inputTexture, 0, null, bd.Scan0, bd.Stride, 0);
            }
            finally
            {
                _captureBitmap.UnlockBits(bd);
            }
        }

        private void RenderCAS()
        {
            float[] cbData = new float[]
            {
                _sharpness,
                1.0f / _captureWidth,
                1.0f / _captureHeight,
                0f
            };
            _context.UpdateSubresource(cbData, _casParamsCB);

            _context.OutputMerger.SetRenderTargets(_outputRTV);
            _context.Rasterizer.SetViewport(0, 0, _captureWidth, _captureHeight);
            _context.InputAssembler.PrimitiveTopology = PrimitiveTopology.TriangleList;
            _context.InputAssembler.InputLayout = null;

            _context.VertexShader.Set(_vertexShader);
            _context.PixelShader.Set(_pixelShader);
            _context.PixelShader.SetShaderResource(0, _inputSRV);
            _context.PixelShader.SetSampler(0, _sampler);
            _context.PixelShader.SetConstantBuffer(0, _casParamsCB);

            _context.Draw(3, 0);
        }

        private void ReadbackOutput()
        {
            _context.CopyResource(_outputTexture, _stagingTexture);

            DataBox mapped = _context.MapSubresource(
                _stagingTexture,
                0,
                MapMode.Read,
                SharpDX.Direct3D11.MapFlags.None);
            try
            {
                lock (_outputLock)
                {
                    BitmapData bd = _outputBitmap.LockBits(
                        new Rectangle(0, 0, _captureWidth, _captureHeight),
                        ImageLockMode.WriteOnly,
                        PixelFormat.Format32bppArgb);
                    try
                    {
                        int rowBytes = _captureWidth * 4;
                        for (int y = 0; y < _captureHeight; y++)
                        {
                            Utilities.CopyMemory(
                                bd.Scan0 + y * bd.Stride,
                                mapped.DataPointer + y * mapped.RowPitch,
                                rowBytes);
                        }
                    }
                    finally
                    {
                        _outputBitmap.UnlockBits(bd);
                    }
                }
            }
            finally
            {
                _context.UnmapSubresource(_stagingTexture, 0);
            }
        }

        private bool CreateShaders()
        {
            byte[] vsBytecode = CasShaderBytecode.GetVertexShaderBytecode();
            byte[] psBytecode = CasShaderBytecode.GetPixelShaderBytecode();

            if (vsBytecode == null || psBytecode == null)
            {
                LogManager.Log("[GpuRenderer] Shader compilation failed");
                return false;
            }

            _vertexShader = new VertexShader(_device, vsBytecode);
            _pixelShader = new PixelShader(_device, psBytecode);

            LogManager.Log("[GpuRenderer] Shaders: VS=" + vsBytecode.Length + "B PS=" + psBytecode.Length + "B");
            return true;
        }

        private static Rectangle GetAspectFitRect(Rectangle bounds, int srcWidth, int srcHeight)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0 || srcWidth <= 0 || srcHeight <= 0)
                return Rectangle.Empty;

            float scale = Math.Min(
                (float)bounds.Width / srcWidth,
                (float)bounds.Height / srcHeight);

            int drawWidth = Math.Max(1, (int)Math.Round(srcWidth * scale));
            int drawHeight = Math.Max(1, (int)Math.Round(srcHeight * scale));
            int drawX = bounds.X + (bounds.Width - drawWidth) / 2;
            int drawY = bounds.Y + (bounds.Height - drawHeight) / 2;

            return new Rectangle(drawX, drawY, drawWidth, drawHeight);
        }

        public void Dispose()
        {
            RequestStop();

            Utilities.Dispose(ref _inputSRV);
            Utilities.Dispose(ref _inputTexture);
            Utilities.Dispose(ref _outputRTV);
            Utilities.Dispose(ref _outputTexture);
            Utilities.Dispose(ref _stagingTexture);
            Utilities.Dispose(ref _casParamsCB);
            Utilities.Dispose(ref _sampler);
            Utilities.Dispose(ref _pixelShader);
            Utilities.Dispose(ref _vertexShader);
            Utilities.Dispose(ref _context);
            Utilities.Dispose(ref _device);

            if (_captureBitmap != null)
            {
                _captureBitmap.Dispose();
                _captureBitmap = null;
            }

            if (_outputBitmap != null)
            {
                _outputBitmap.Dispose();
                _outputBitmap = null;
            }
        }

        public void RequestResize(int w, int h)
        {
        }
    }
}
