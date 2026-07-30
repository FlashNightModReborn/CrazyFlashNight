using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal sealed class AgentObservationEnvelopeStore
        : IAgentObservationBindingStore
    {
        private const int MaximumEntries = 1024;
        private readonly object _sync = new object();
        private readonly Dictionary<string, Entry> _byObservation =
            new Dictionary<string, Entry>(
                StringComparer.Ordinal);
        private readonly Dictionary<string, ContentBinding>
            _byHandle =
                new Dictionary<string, ContentBinding>(
                    StringComparer.Ordinal);
        private readonly Queue<string> _order =
            new Queue<string>();

        public void Store(
            AgentRuntimeDispatchContext context,
            string dataScope,
            ObservationEnvelope envelope)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            if (envelope == null)
                throw new ArgumentNullException(nameof(envelope));
            var entry = new Entry(
                context.Principal.ClientInstanceId,
                context.Principal.SecurityPrincipalId,
                dataScope,
                envelope);
            lock (_sync)
            {
                if (_byObservation.ContainsKey(
                        envelope.ObservationId))
                {
                    throw new InvalidOperationException(
                        "observation_already_cached");
                }
                _byObservation.Add(
                    envelope.ObservationId,
                    entry);
                _order.Enqueue(envelope.ObservationId);
                foreach (FrameEnvelope frame
                    in envelope.Frames)
                {
                    _byHandle.Add(
                        frame.OpaqueContentHandle,
                        new ContentBinding(
                            entry,
                            frame.TargetId,
                            frame.OpaqueContentHandle));
                }
                while (_byObservation.Count
                    > MaximumEntries)
                {
                    RemoveLocked(_order.Dequeue());
                }
            }
        }

        public bool TryGet(
            AgentRuntimeDispatchContext context,
            string observationGrantId,
            string sessionId,
            string observationId,
            out ObservationEnvelope envelope,
            out string dataScope,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveOwnerLocked(
                        context,
                        observationId,
                        out Entry entry,
                        out reasonCode))
                {
                    envelope = null;
                    dataScope = null;
                    return false;
                }
                if (!string.Equals(
                        entry.Envelope.ObservationGrantId,
                        observationGrantId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        entry.Envelope.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                {
                    envelope = null;
                    dataScope = null;
                    reasonCode =
                        "observation_scope_mismatch";
                    return false;
                }
                envelope = entry.Envelope;
                dataScope = entry.DataScope;
                reasonCode = null;
                return true;
            }
        }

        public bool TryAcknowledge(
            AgentRuntimeDispatchContext context,
            string observationGrantId,
            string sessionId,
            string observationId,
            out ObservationEnvelope envelope,
            out string dataScope,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!TryResolveOwnerLocked(
                        context,
                        observationId,
                        out Entry entry,
                        out reasonCode))
                {
                    envelope = null;
                    dataScope = null;
                    return false;
                }
                if (!string.Equals(
                        entry.Envelope.ObservationGrantId,
                        observationGrantId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        entry.Envelope.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                {
                    envelope = null;
                    dataScope = null;
                    reasonCode =
                        "observation_scope_mismatch";
                    return false;
                }
                envelope = entry.Envelope;
                dataScope = entry.DataScope;
                RemoveLocked(observationId);
                reasonCode = null;
                return true;
            }
        }

        public bool TryResolveContent(
            AgentRuntimeDispatchContext context,
            string handle,
            out PixelContentReadRequest binding,
            out string reasonCode)
        {
            lock (_sync)
            {
                binding = null;
                if (!_byHandle.TryGetValue(
                        handle ?? string.Empty,
                        out ContentBinding content))
                {
                    reasonCode =
                        "content_handle_not_found";
                    return false;
                }
                if (!OwnerMatches(
                        context,
                        content.Entry))
                {
                    reasonCode =
                        "content_handle_binding_mismatch";
                    return false;
                }
                binding = new PixelContentReadRequest
                {
                    Handle = handle,
                    ClientInstanceId =
                        content.Entry.ClientInstanceId,
                    SecurityPrincipalId =
                        content.Entry.SecurityPrincipalId,
                    SessionId =
                        content.Entry.Envelope.SessionId,
                    ObservationGrantId =
                        content.Entry.Envelope
                            .ObservationGrantId,
                    ObservationId =
                        content.Entry.Envelope.ObservationId
                };
                reasonCode = null;
                return true;
            }
        }

        public bool TryResolveForAction(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            out string dataScope,
            out string reasonCode)
        {
            lock (_sync)
            {
                dataScope = null;
                if (!TryResolveOwnerLocked(
                        context,
                        action.ObservationId,
                        out Entry entry,
                        out reasonCode))
                {
                    return false;
                }
                ObservationEnvelope envelope =
                    entry.Envelope;
                if (!string.Equals(
                        envelope.ObservationGrantId,
                        action.ObservationGrantId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        envelope.SessionId,
                        action.SessionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        envelope.TargetId,
                        action.TargetId,
                        StringComparison.Ordinal))
                {
                    reasonCode =
                        "observation_scope_mismatch";
                    return false;
                }
                if (envelope.LifecycleGeneration
                    != action.ExpectedLifecycleGeneration)
                {
                    reasonCode = "stale_lifecycle";
                    return false;
                }
                if (!string.Equals(
                        envelope.AttemptId,
                        action.ExpectedAttemptId,
                        StringComparison.Ordinal)
                    || envelope.AttemptGeneration
                        != action.ExpectedAttemptGeneration)
                {
                    reasonCode = "stale_attempt";
                    return false;
                }
                if (envelope.SurfaceEpoch
                    != action.ExpectedSurfaceEpoch)
                {
                    reasonCode = "stale_surface";
                    return false;
                }
                if (envelope.CoordinateSpaceVersion
                    != action.ExpectedCoordinateSpaceVersion)
                {
                    reasonCode =
                        "stale_coordinate_space";
                    return false;
                }
                if (envelope.FocusEpoch
                    != action.ExpectedFocusEpoch)
                {
                    reasonCode = "stale_focus";
                    return false;
                }
                if (envelope.ModalEpoch
                    != action.ExpectedModalEpoch)
                {
                    reasonCode = "stale_modal";
                    return false;
                }
                if (!string.Equals(
                        envelope.PanelInstanceId,
                        action.ExpectedPanelInstanceId,
                        StringComparison.Ordinal))
                {
                    reasonCode =
                        "stale_panel_instance";
                    return false;
                }
                if (action.ExpectedDocumentGeneration.HasValue
                    && envelope.DocumentGeneration
                        != action.ExpectedDocumentGeneration)
                {
                    reasonCode = "stale_document";
                    return false;
                }
                if (action.ExpectedSemanticGeneration.HasValue
                    && envelope.SemanticGeneration
                        != action.ExpectedSemanticGeneration)
                {
                    reasonCode =
                        "stale_semantic_node";
                    return false;
                }
                if (action.SemanticSnapshotId != null
                    && !string.Equals(
                        envelope.SemanticSnapshotId,
                        action.SemanticSnapshotId,
                        StringComparison.Ordinal))
                {
                    reasonCode =
                        "stale_semantic_node";
                    return false;
                }
                if (action.FrameId != null
                    && !envelope.Frames.Any(
                        frame => string.Equals(
                            frame.FrameId,
                            action.FrameId,
                            StringComparison.Ordinal)
                            && string.Equals(
                                frame.TargetId,
                                action.TargetId,
                                StringComparison.Ordinal)))
                {
                    reasonCode = "stale_observation";
                    return false;
                }
                dataScope = entry.DataScope;
                reasonCode = null;
                return true;
            }
        }

        public bool TryResolveAuditFrame(
            AgentRuntimeDispatchContext context,
            string observationId,
            string targetId,
            string frameId,
            out string resolvedFrameId,
            out string frameHash,
            out string reasonCode)
        {
            lock (_sync)
            {
                resolvedFrameId = null;
                frameHash = null;
                if (!TryResolveOwnerLocked(
                        context,
                        observationId,
                        out Entry entry,
                        out reasonCode))
                {
                    return false;
                }
                FrameEnvelope frame = entry.Envelope.Frames
                    .FirstOrDefault(candidate =>
                        string.Equals(
                            candidate.TargetId,
                            targetId,
                            StringComparison.Ordinal)
                        && (frameId == null
                            || string.Equals(
                                candidate.FrameId,
                                frameId,
                                StringComparison.Ordinal)));
                if (frame == null
                    || string.IsNullOrWhiteSpace(
                        frame.ContentHash))
                {
                    reasonCode =
                        "keyframe_hash_unavailable";
                    return false;
                }
                resolvedFrameId = frame.FrameId;
                frameHash = frame.ContentHash;
                reasonCode = null;
                return true;
            }
        }

        public bool TryGetFrame(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            out FrameEnvelope frame,
            out string reasonCode)
        {
            lock (_sync)
            {
                frame = null;
                if (!TryResolveOwnerLocked(
                        context,
                        action.ObservationId,
                        out Entry entry,
                        out reasonCode))
                {
                    return false;
                }
                frame = entry.Envelope.Frames
                    .FirstOrDefault(candidate =>
                        string.Equals(
                            candidate.FrameId,
                            action.FrameId,
                            StringComparison.Ordinal)
                        && string.Equals(
                            candidate.TargetId,
                            action.TargetId,
                            StringComparison.Ordinal));
                if (frame == null)
                {
                    reasonCode = "stale_observation";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        private bool TryResolveOwnerLocked(
            AgentRuntimeDispatchContext context,
            string observationId,
            out Entry entry,
            out string reasonCode)
        {
            entry = null;
            if (context == null
                || !_byObservation.TryGetValue(
                    observationId ?? string.Empty,
                    out entry))
            {
                reasonCode = "stale_observation";
                return false;
            }
            if (!OwnerMatches(context, entry))
            {
                reasonCode =
                    "observation_scope_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool OwnerMatches(
            AgentRuntimeDispatchContext context,
            Entry entry)
        {
            return context != null
                && string.Equals(
                    context.Principal.ClientInstanceId,
                    entry.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    context.Principal.SecurityPrincipalId,
                    entry.SecurityPrincipalId,
                    StringComparison.Ordinal);
        }

        private void RemoveLocked(string observationId)
        {
            if (!_byObservation.Remove(
                    observationId,
                    out Entry entry))
            {
                return;
            }
            foreach (FrameEnvelope frame
                in entry.Envelope.Frames)
            {
                _byHandle.Remove(
                    frame.OpaqueContentHandle);
            }
        }

        private sealed class Entry
        {
            public Entry(
                string clientInstanceId,
                string securityPrincipalId,
                string dataScope,
                ObservationEnvelope envelope)
            {
                ClientInstanceId = clientInstanceId;
                SecurityPrincipalId = securityPrincipalId;
                DataScope = dataScope;
                Envelope = envelope;
            }

            public string ClientInstanceId { get; }
            public string SecurityPrincipalId { get; }
            public string DataScope { get; }
            public ObservationEnvelope Envelope { get; }
        }

        private sealed record ContentBinding(
            Entry Entry,
            string TargetId,
            string Handle);
    }
}
