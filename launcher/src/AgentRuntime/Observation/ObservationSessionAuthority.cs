using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Observation
{
    /// <summary>
    /// Supplies capture plans exclusively from Launcher-owned session state.
    /// Implementations must never accept HWNDs or safety classifications from
    /// wire requests.
    /// </summary>
    internal interface IObservationSessionAuthority
    {
        bool TryCreateCapturePlan(
            string sessionId,
            string targetId,
            out ObservationCapturePlan plan,
            out string reasonCode);

        bool TryValidateCapturePlan(
            ObservationCapturePlan capturedPlan,
            out string reasonCode);
    }

    /// <summary>
    /// Read-only adapter over the positive-registration session registry.
    /// Security/system/foreign surfaces never occur in its returned plans.
    /// </summary>
    internal sealed class SessionSurfaceObservationAuthority
        : IObservationSessionAuthority
    {
        private readonly SessionSurfaceRegistry _registry;

        public SessionSurfaceObservationAuthority(
            SessionSurfaceRegistry registry)
        {
            _registry = registry
                ?? throw new ArgumentNullException(nameof(registry));
        }

        public bool TryCreateCapturePlan(
            string sessionId,
            string targetId,
            out ObservationCapturePlan plan,
            out string reasonCode)
        {
            return TryBuildPlan(
                _registry.GetSnapshot(),
                sessionId,
                targetId,
                out plan,
                out reasonCode);
        }

        public bool TryValidateCapturePlan(
            ObservationCapturePlan capturedPlan,
            out string reasonCode)
        {
            if (capturedPlan == null)
            {
                reasonCode = "arguments_invalid";
                return false;
            }

            SessionSurfaceRegistrySnapshot snapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                snapshot.FindSession(capturedPlan.SessionId);
            if (session == null
                || session.LifecycleGeneration
                    != capturedPlan.LifecycleGeneration)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            if (!string.Equals(
                    session.AttemptId,
                    capturedPlan.AttemptId,
                    StringComparison.Ordinal)
                || session.AttemptGeneration
                    != capturedPlan.AttemptGeneration)
            {
                reasonCode = "stale_attempt";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.HumanOnlySecurity)
            {
                reasonCode = "human_only_security_surface";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.Foreign)
            {
                reasonCode = "foreign_modal";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.Unknown)
            {
                reasonCode = "unknown_modal";
                return false;
            }
            if (session.HumanReauthorizationRequired)
            {
                reasonCode = "human_intervention_required";
                return false;
            }
            if (session.ModalEpoch != capturedPlan.ModalEpoch
                || session.BlockingModalKind
                    != capturedPlan.BlockingModalKind)
            {
                reasonCode = "stale_modal";
                return false;
            }
            if (session.FocusEpoch != capturedPlan.FocusEpoch)
            {
                reasonCode = "stale_focus";
                return false;
            }
            if (!string.Equals(
                    session.PanelInstanceIdForTarget(
                        capturedPlan.PrimarySurface.TargetId),
                    capturedPlan.PanelInstanceId,
                    StringComparison.Ordinal))
            {
                reasonCode = "stale_panel_instance";
                return false;
            }
            if (!session.DesktopAvailable)
            {
                reasonCode = "desktop_unavailable";
                return false;
            }

            foreach (ObservationSurfacePlan expected
                in capturedPlan.CaptureSurfaces)
            {
                SessionSurfaceSnapshot current = session.Surfaces
                    .FirstOrDefault(surface => string.Equals(
                        surface.TargetId,
                        expected.TargetId,
                        StringComparison.Ordinal));
                if (current == null
                    || current.SafetyKind
                        != AgentTargetSafetyKind.RuntimeOwned
                    || current.WindowHandle != expected.WindowHandle
                    || current.OwnerWindowHandle
                        != expected.OwnerWindowHandle
                    || current.OwnerProcess.ProcessId
                        != expected.OwnerProcessId
                    || current.OwnerProcess.StartTimeUtc.UtcDateTime.Ticks
                        != expected.OwnerProcessStartTimeUtc.UtcDateTime.Ticks
                    || !string.Equals(
                        current.OwnerProcess.ExecutablePath,
                        expected.OwnerExecutablePath,
                        StringComparison.OrdinalIgnoreCase))
                {
                    reasonCode = "stale_surface";
                    return false;
                }
                if (current.CoordinateSpaceVersion
                        != expected.CoordinateSpaceVersion
                    || current.Dpi != expected.Dpi
                    || !SameRect(
                        current.BoundsPhysical,
                        expected.BoundsPhysical)
                    || !SameRect(
                        current.ClientRectPhysical,
                        expected.ClientRectPhysical)
                    || !SameRect(
                        current.ContentRectPhysical,
                        expected.ContentRectPhysical))
                {
                    reasonCode = "stale_coordinate_space";
                    return false;
                }
                if (current.SurfaceEpoch != expected.SurfaceEpoch)
                {
                    reasonCode = "stale_surface";
                    return false;
                }
                if (current.DocumentGeneration
                    != expected.DocumentGeneration)
                {
                    reasonCode = "stale_document";
                    return false;
                }
                if (current.SemanticGeneration
                    != expected.SemanticGeneration)
                {
                    reasonCode = "stale_semantic_snapshot";
                    return false;
                }
                if (current.Minimized)
                {
                    reasonCode = "target_minimized";
                    return false;
                }
                if (!current.Visible)
                {
                    reasonCode = "target_not_visible";
                    return false;
                }
                if (current.Active != expected.Active)
                {
                    reasonCode = "stale_focus";
                    return false;
                }
            }

            reasonCode = null;
            return true;
        }

        private static bool TryBuildPlan(
            SessionSurfaceRegistrySnapshot snapshot,
            string sessionId,
            string targetId,
            out ObservationCapturePlan plan,
            out string reasonCode)
        {
            plan = null;
            SessionSnapshot session = snapshot.FindSession(
                sessionId ?? string.Empty);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (!session.DesktopAvailable)
            {
                reasonCode = "desktop_unavailable";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.HumanOnlySecurity)
            {
                reasonCode = "human_only_security_surface";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.Foreign)
            {
                reasonCode = "foreign_modal";
                return false;
            }
            if (session.BlockingModalKind
                == BlockingModalKind.Unknown)
            {
                reasonCode = "unknown_modal";
                return false;
            }
            if (session.HumanReauthorizationRequired)
            {
                reasonCode = "human_intervention_required";
                return false;
            }

            SessionSurfaceSnapshot primary = session.Surfaces
                .FirstOrDefault(surface => string.Equals(
                    surface.TargetId,
                    targetId,
                    StringComparison.Ordinal));
            if (primary == null)
            {
                reasonCode = "target_not_authoritative";
                return false;
            }
            if (primary.SafetyKind
                != AgentTargetSafetyKind.RuntimeOwned)
            {
                reasonCode = "human_only_security_surface";
                return false;
            }
            if (primary.Minimized)
            {
                reasonCode = "target_minimized";
                return false;
            }
            if (!primary.Visible)
            {
                reasonCode = "target_not_visible";
                return false;
            }

            var includedTargets = new HashSet<string>(
                StringComparer.Ordinal)
            {
                primary.TargetId
            };
            bool changed;
            do
            {
                changed = false;
                foreach (SessionSurfaceSnapshot surface
                    in session.Surfaces)
                {
                    if (surface.Kind == SurfaceKind.BusinessModal
                        && surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && includedTargets.Contains(
                            surface.OwnerTargetId ?? string.Empty)
                        && includedTargets.Add(surface.TargetId))
                    {
                        changed = true;
                    }
                }
            }
            while (changed);

            SessionSurfaceSnapshot[] captureSurfaces = session.Surfaces
                .Where(surface => includedTargets.Contains(
                    surface.TargetId))
                .OrderBy(surface => surface.ZIndex)
                .ThenBy(
                    surface => surface.TargetId,
                    StringComparer.Ordinal)
                .ToArray();
            if (session.BlockingModalKind
                    == BlockingModalKind.BusinessOwned
                && !captureSurfaces.Any(surface =>
                    surface.Kind == SurfaceKind.BusinessModal))
            {
                reasonCode = "blocking_modal_out_of_scope";
                return false;
            }
            foreach (SessionSurfaceSnapshot surface in captureSurfaces)
            {
                if (surface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned)
                {
                    reasonCode = "human_only_security_surface";
                    return false;
                }
                if (surface.WindowHandle == 0)
                {
                    reasonCode = "target_not_authoritative";
                    return false;
                }
                if (surface.Minimized)
                {
                    reasonCode = "target_minimized";
                    return false;
                }
                if (!surface.Visible)
                {
                    reasonCode = "target_not_visible";
                    return false;
                }
                if (!surface.ObservationModes.Contains(
                    ObservationMode.WindowGraphicsCapture))
                {
                    reasonCode = "unsupported_for_surface";
                    return false;
                }
            }

            ObservationSurfacePlan[] surfaces = captureSurfaces
                .Select(ToPlan)
                .ToArray();
            ObservationSurfacePlan primaryPlan = surfaces.Single(
                surface => string.Equals(
                    surface.TargetId,
                    primary.TargetId,
                    StringComparison.Ordinal));
            plan = new ObservationCapturePlan(
                session.SessionId,
                session.LifecycleGeneration,
                session.AttemptId,
                session.AttemptGeneration,
                session.PanelInstanceIdForTarget(
                    primary.TargetId),
                session.FocusEpoch,
                session.ModalEpoch,
                session.BlockingModalKind,
                primaryPlan,
                surfaces);
            reasonCode = null;
            return true;
        }

        private static ObservationSurfacePlan ToPlan(
            SessionSurfaceSnapshot surface)
        {
            return new ObservationSurfacePlan(
                surface.TargetId,
                surface.Kind,
                surface.WindowHandle,
                surface.OwnerProcess.ProcessId,
                surface.OwnerProcess.StartTimeUtc,
                surface.OwnerProcess.ExecutablePath,
                surface.OwnerWindowHandle,
                surface.SurfaceEpoch,
                surface.CoordinateSpaceVersion,
                surface.FocusEpoch,
                surface.ModalEpoch,
                surface.SemanticGeneration,
                surface.DocumentGeneration,
                surface.BoundsPhysical.ToContract(),
                surface.ClientRectPhysical.ToContract(),
                surface.ContentRectPhysical.ToContract(),
                surface.Dpi,
                surface.ZIndex,
                surface.Visible,
                surface.Minimized,
                surface.Active,
                surface.ObservationModes);
        }

        private static bool SameRect(
            SessionPhysicalRect left,
            PhysicalRect right)
        {
            return left != null
                && right != null
                && left.X == right.X
                && left.Y == right.Y
                && left.Width == right.Width
                && left.Height == right.Height;
        }
    }
}
