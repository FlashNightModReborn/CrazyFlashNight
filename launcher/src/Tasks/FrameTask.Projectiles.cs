using System;
using System.Diagnostics;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Tasks
{
    public partial class FrameTask
    {
        private readonly object _projectileLock=new object();
        private VisualWireNegotiator _visualWire;
        internal void SetVisualWire(VisualWireNegotiator wire) => _visualWire = wire;
        private readonly RayVisualEngine _rayVisualEngine=new RayVisualEngine();
        private readonly ChainVisualEngine _chainVisualEngine=new ChainVisualEngine();
        private BulletVisualInstance[] _chainVisualItems=Array.Empty<BulletVisualInstance>();
        private int _projectileStyleCount,_projectileGeneration=-1,_minimumRayEpoch,_minimumChainEpoch;
        private int _minimumBulletEpoch,_lastBulletEpoch=-1;
        internal Action<RayVisualDrawFrame,float,float,float> RayVisualObserved;
        internal Action RayVisualRejected,RayVisualCleared,ChainVisualRejected;
        internal Action<string,string> VisualFaultReported;
        internal Action<SceneLightState> SceneLightObserved;
        internal Action<int,bool> SceneLightClockObserved;

        /// <summary>
        /// AS2 视觉桥上报的通道级致命故障：V{channel}|{reason}。
        /// 进入本方法的消息已被 socket 层按当前连接代过滤，这里只做有界字段校验后
        /// 交给现有会话渲染失败路径；畸形报文丢弃而不是影响其他世代。
        /// </summary>
        internal void HandleVisualFault(string payload)
        {
            string channel=payload??"",reason="";
            int sep=channel.IndexOf('|');
            if(sep>=0){reason=channel.Substring(sep+1);channel=channel.Substring(0,sep);}
            if((channel!="bullet"&&channel!="chain"&&channel!="ray"&&channel!="scene")
                ||reason.Length==0||reason.Length>64)
            {
                CF7Launcher.Guardian.PerfTrace.Counter("visual_fault.malformed");
                return;
            }
            VisualFaultReported?.Invoke(channel,reason);
        }

        internal void ConfigureProjectileVisuals(BulletVisualCatalog catalog)
        {
            lock(_projectileLock) _projectileStyleCount=catalog?.Styles.Count??0;
        }
        internal void ConfigureRayLighting(RayLightingCatalog catalog)
        {
            lock(_projectileLock) _rayVisualEngine.ConfigureLighting(catalog);
        }
        internal void ResetProjectileVisualsForGeneration(int generation)
        {
            lock(_projectileLock) {
                if(generation<_projectileGeneration)return;
                _projectileGeneration=generation+1;_minimumRayEpoch=0;_minimumChainEpoch=0;_minimumBulletEpoch=0;
                ResetProjectileVisuals();
            }
        }
        private void ResetProjectileVisuals()
        {
            lock(_projectileLock) {
                _rayVisualEngine.Reset();_chainVisualEngine.Reset();
                _chainVisualItems=Array.Empty<BulletVisualInstance>();
                _lastBulletEpoch=-1;
                _lastOrdinaryCount=0;
                RayVisualCleared?.Invoke();
            }
        }
        internal void ResetProjectileScene()
        {
            lock(_projectileLock) {
                _minimumRayEpoch=Math.Max(_minimumRayEpoch,_rayVisualEngine.Epoch+1);
                _minimumChainEpoch=Math.Max(_minimumChainEpoch,_chainVisualEngine.Epoch+1);
                _minimumBulletEpoch=Math.Max(_minimumBulletEpoch,_lastBulletEpoch+1);
                ResetProjectileVisuals();
            }
        }
        // Capability cycles retire only ray state. Preserve the rejected epoch before
        // resetting its engine so delayed packets cannot resurrect the previous beam.
        internal void InvalidateRayVisuals()
        {
            lock(_projectileLock) {
                _minimumRayEpoch=Math.Max(_minimumRayEpoch,_rayVisualEngine.Epoch+1);
                _rayVisualEngine.Reset();
                RayVisualCleared?.Invoke();
            }
        }
        // The shared bullet capability retires both F5 snapshot ownership and F8
        // groups. F5 advances on each AS2 capability configure; F8 advances on
        // resync/scene retirement. Queued snapshots cannot redraw retired units.
        internal void InvalidateChainVisuals()
        {
            lock(_projectileLock) {
                _minimumChainEpoch=Math.Max(_minimumChainEpoch,_chainVisualEngine.Epoch+1);
                _minimumBulletEpoch=Math.Max(_minimumBulletEpoch,_lastBulletEpoch+1);
                _chainVisualEngine.Reset();
                _chainVisualItems=Array.Empty<BulletVisualInstance>();
                BulletVisualCleared?.Invoke();
            }
        }
        private void RejectRayVisuals(int rejectedEpoch=-1)
        {
            lock(_projectileLock) {
                _minimumRayEpoch=Math.Max(_minimumRayEpoch,rejectedEpoch+1);
                InvalidateRayVisuals();
                RayVisualRejected?.Invoke();
            }
        }
        internal void ObserveProjectileVisuals(string rayPayload,string chainPayload,int generation,HitNumberCamera camera)
        {
            lock(_projectileLock) {
                if(generation<_projectileGeneration)return;
                if(generation>_projectileGeneration) {
                    ResetProjectileVisuals();_minimumRayEpoch=0;_minimumChainEpoch=0;_minimumBulletEpoch=0;_projectileGeneration=generation;
                }
                if(rayPayload!=null) {
                    if(!RayVisualFrame.TryParse(rayPayload,out var frame)) {
                        RejectRayVisuals();
                    } else if(frame.Epoch>=_minimumRayEpoch) {
                        int rejected=_rayVisualEngine.Rejected;
                        if(_rayVisualEngine.Apply(frame,generation))
                            RayVisualObserved?.Invoke(_rayVisualEngine.BuildDraw(),camera.OffsetX,camera.OffsetY,camera.Scale);
                        else if(_rayVisualEngine.Rejected!=rejected) RejectRayVisuals(frame.Epoch);
                    }
                }
                if(chainPayload!=null && _projectileStyleCount>0) {
                    if(ChainVisualFrame.TryReadHeader(chainPayload,out int epoch,out _,out _)
                        && epoch<_minimumChainEpoch)return;
                    var items=_chainVisualEngine.Consume(generation,chainPayload,_projectileStyleCount);
                    if(_chainVisualEngine.NeedsResync) {
                        _chainVisualItems=Array.Empty<BulletVisualInstance>();ChainVisualRejected?.Invoke();
                    } else if(items!=null && _chainVisualEngine.Epoch>=_minimumChainEpoch)
                        _chainVisualItems=items;
                }
            }
        }
        // F5 is a complete snapshot. Shadow.Observe returns null for valid stale
        // snapshots too; only malformed data may revoke ownership. Scene reset keeps
        // a separate F5 epoch floor because its source counter differs from F7/F8.
        private void ObserveOrdinaryBulletVisuals(string payload,int generation,HitNumberCamera camera)
        {
            lock(_projectileLock) {
                if(generation<_projectileGeneration)return;
                bool q1 = payload.StartsWith("Q1|", StringComparison.Ordinal);
                BulletVisualFrame visual;
                if (q1)
                {
                    long started = Stopwatch.GetTimestamp();
                    if (!BulletVisualWireQ1.TryParse(payload, _bulletVisualStyleCount, out var parsed)
                        || _visualWire?.CanDecodeQ1(generation, parsed.OfferId) != true)
                    { BulletVisualRejected?.Invoke(); return; }
                    if (parsed.Epoch < _minimumBulletEpoch) return;
                    visual = _bulletVisualShadow.ObserveParsed(parsed, generation, payload.Length, started);
                    if (visual != null && !_visualWire.ActivateQ1(generation)) return;
                }
                else
                {
                    if (_visualWire?.LegacyRetired(generation) == true) return;
                    visual = _bulletVisualShadow.Observe(payload,generation);
                }
                if(visual!=null) {
                    if(visual.Epoch<_minimumBulletEpoch)return;
                    _lastBulletEpoch=visual.Epoch;
                    _lastOrdinaryCount=visual.NormalCount;
                    DispatchProjectileBullets(visual,camera);
                } else if(!q1 && !BulletVisualFrame.TryParse(payload,_bulletVisualStyleCount,out _)) {
                    BulletVisualRejected?.Invoke();
                }
            }
        }
        internal void DispatchProjectileBullets(BulletVisualFrame ordinary,HitNumberCamera camera)
        {
            lock(_projectileLock) {
                var composed=BulletVisualFrame.ComposeOwned(ordinary,_chainVisualItems,
                    _chainVisualEngine.Epoch,_chainVisualEngine.Tick);
                BulletVisualObserved?.Invoke(composed,camera.OffsetX,camera.OffsetY,camera.Scale);
            }
        }
        private int _lastOrdinaryCount;
        internal bool HasCleanWorkerProjections()
        {
            lock (_projectileLock)
                if (_lastOrdinaryCount != 0 || _chainVisualEngine.HasLiveGroups || _rayVisualEngine.ActiveCount != 0) return false;
            lock (_combatFxLock) return _combatFxEngine?.HasDecorationState != true;
        }
    }
}
