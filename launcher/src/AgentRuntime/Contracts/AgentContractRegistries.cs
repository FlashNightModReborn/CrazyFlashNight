using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public sealed class ReasonCodeDefinition
    {
        public ReasonCodeDefinition(
            string code,
            bool retryable,
            ActionOutcome[] allowedOutcomes,
            ReconcileKind[] allowedReconcileKinds)
        {
            Code = code;
            Retryable = retryable;
            AllowedOutcomes = allowedOutcomes;
            AllowedReconcileKinds = allowedReconcileKinds;
        }

        public string Code { get; }
        public bool Retryable { get; }
        public IReadOnlyList<ActionOutcome> AllowedOutcomes { get; }
        public IReadOnlyList<ReconcileKind> AllowedReconcileKinds { get; }
    }

    public static class AgentReasonCodesV1
    {
        private static readonly ActionOutcome[] Rejected = { ActionOutcome.Rejected };
        private static readonly ActionOutcome[] Unknown = { ActionOutcome.Unknown };
        private static readonly ReconcileKind[] NoReconcile = { ReconcileKind.None };
        private static readonly ReconcileKind[] AnyUnknownReconcile =
        {
            ReconcileKind.DomainAuthoritative,
            ReconcileKind.VisualAmbiguous,
            ReconcileKind.ManualRequired
        };

        private static readonly IReadOnlyDictionary<string, ReasonCodeDefinition> Registry =
            new ReadOnlyDictionary<string, ReasonCodeDefinition>(
                new[]
                {
                    Define("none", false,
                        new[]
                        {
                            ActionOutcome.InputDispatched,
                            ActionOutcome.EffectObserved,
                            ActionOutcome.DomainCommitted
                        },
                        NoReconcile),
                    Define("shutdown_requested", false,
                        new[] { ActionOutcome.InputDispatched },
                        NoReconcile),
                    Define("protocol_version_mismatch", false, Rejected, NoReconcile),
                    Define("malformed_frame", false, Rejected, NoReconcile),
                    Define("malformed_json", false, Rejected, NoReconcile),
                    Define("frame_oversize", false, Rejected, NoReconcile),
                    Define("binary_object_oversize", false, Rejected, NoReconcile),
                    Define("rate_limited", true, Rejected, NoReconcile),
                    Define("queue_full", true, Rejected, NoReconcile),
                    Define("authentication_failed", false, Rejected, NoReconcile),
                    Define("connection_ticket_expired", true, Rejected, NoReconcile),
                    Define("connection_ticket_replayed", false, Rejected, NoReconcile),
                    Define("credential_revoked", false, Rejected, NoReconcile),
                    Define("principal_mismatch", false, Rejected, NoReconcile),
                    Define("capability_denied", false, Rejected, NoReconcile),
                    Define("consent_required", false, Rejected, NoReconcile),
                    Define("consent_invalid", false, Rejected, NoReconcile),
                    Define("consent_expired", true, Rejected, NoReconcile),
                    Define("human_intervention_required", false, Rejected, NoReconcile),
                    Define("occupied_by_other_logon_or_elevation", false, Rejected, NoReconcile),
                    Define("session_not_found", true, Rejected, NoReconcile),
                    Define("session_mismatch", false, Rejected, NoReconcile),
                    Define("runtime_unqualified", false, Rejected, NoReconcile),
                    Define("attempt_mismatch", false, Rejected, NoReconcile),
                    Define("target_not_found", true, Rejected, NoReconcile),
                    Define("unsupported_for_surface", false, Rejected, NoReconcile),
                    Define("human_only_security_surface", false, Rejected, NoReconcile),
                    Define("target_minimized", true, Rejected, NoReconcile),
                    Define("capture_unavailable", true, Rejected, NoReconcile),
                    Define("desktop_unavailable", true, Rejected, NoReconcile),
                    Define("blocking_modal", true, Rejected, NoReconcile),
                    Define("observation_grant_required", false, Rejected, NoReconcile),
                    Define("observation_grant_expired", true, Rejected, NoReconcile),
                    Define("observation_grant_revoked", false, Rejected, NoReconcile),
                    Define("observation_scope_mismatch", false, Rejected, NoReconcile),
                    Define("lease_required", false, Rejected, NoReconcile),
                    Define("lease_expired", true, Rejected, NoReconcile),
                    Define("lease_revoked", false, Rejected, NoReconcile),
                    Define("lease_owner_mismatch", false, Rejected, NoReconcile),
                    Define("lease_busy", true, Rejected, NoReconcile),
                    Define("lease_action_limit", false, Rejected, NoReconcile),
                    Define("stale_observation", true, Rejected, NoReconcile),
                    Define("stale_lifecycle", true, Rejected, NoReconcile),
                    Define("stale_attempt", true, Rejected, NoReconcile),
                    Define("stale_surface", true, Rejected, NoReconcile),
                    Define("stale_coordinate_space", true, Rejected, NoReconcile),
                    Define("stale_focus", true, Rejected, NoReconcile),
                    Define("stale_modal", true, Rejected, NoReconcile),
                    Define("stale_document", true, Rejected, NoReconcile),
                    Define("stale_panel_instance", true, Rejected, NoReconcile),
                    Define("stale_semantic_node", true, Rejected, NoReconcile),
                    Define("input_guard_unhealthy", true, Rejected, NoReconcile),
                    Define("input_not_quiescent", true, Rejected, NoReconcile),
                    Define("foreground_mismatch", true, Rejected, NoReconcile),
                    Define("hit_test_mismatch", true, Rejected, NoReconcile),
                    Define("integrity_mismatch", false, Rejected, NoReconcile),
                    Define("external_input_preempted", true, Rejected, NoReconcile),
                    Define("input_not_inserted", false, Unknown,
                        new[] { ReconcileKind.VisualAmbiguous, ReconcileKind.ManualRequired }),
                    Define("idempotency_conflict", false, Rejected, NoReconcile),
                    Define("action_not_found", false, Rejected, NoReconcile),
                    Define("deadline_exceeded", false,
                        new[] { ActionOutcome.Rejected, ActionOutcome.Unknown },
                        new[]
                        {
                            ReconcileKind.None,
                            ReconcileKind.DomainAuthoritative,
                            ReconcileKind.VisualAmbiguous,
                            ReconcileKind.ManualRequired
                        }),
                    Define("operation_invalid", false, Rejected, NoReconcile),
                    Define("arguments_invalid", false, Rejected, NoReconcile),
                    Define("domain_revision_conflict", true, Rejected, NoReconcile),
                    Define("domain_token_required", false, Rejected, NoReconcile),
                    Define("domain_token_expired", true, Rejected, NoReconcile),
                    Define("domain_token_replayed", false, Rejected, NoReconcile),
                    Define("domain_commit_unknown", false, Unknown,
                        new[] { ReconcileKind.DomainAuthoritative, ReconcileKind.ManualRequired }),
                    Define("reconcile_required", false, Unknown, AnyUnknownReconcile),
                    Define("internal_error", false,
                        new[] { ActionOutcome.Rejected, ActionOutcome.Unknown },
                        new[]
                        {
                            ReconcileKind.None,
                            ReconcileKind.DomainAuthoritative,
                            ReconcileKind.VisualAmbiguous,
                            ReconcileKind.ManualRequired
                        })
                }.ToDictionary(item => item.Code, StringComparer.Ordinal));

        public static IReadOnlyDictionary<string, ReasonCodeDefinition> All
        {
            get { return Registry; }
        }

        public static bool TryGet(string code, out ReasonCodeDefinition definition)
        {
            return Registry.TryGetValue(code ?? string.Empty, out definition);
        }

        private static ReasonCodeDefinition Define(
            string code,
            bool retryable,
            ActionOutcome[] outcomes,
            ReconcileKind[] reconcileKinds)
        {
            return new ReasonCodeDefinition(code, retryable, outcomes, reconcileKinds);
        }
    }

    public sealed class CapabilityApplicability
    {
        public CapabilityApplicability(
            string name,
            string referenceName,
            SessionMode[] modes,
            SurfaceKind[] surfaces,
            bool requiresObservationGrant,
            bool requiresWriteLease,
            bool requiresSemanticProvider,
            bool requiresNativeInputGate,
            bool preLaunchAllowed)
        {
            Name = name;
            ReferenceName = referenceName;
            Modes = modes;
            Surfaces = surfaces;
            RequiresObservationGrant = requiresObservationGrant;
            RequiresWriteLease = requiresWriteLease;
            RequiresSemanticProvider = requiresSemanticProvider;
            RequiresNativeInputGate = requiresNativeInputGate;
            PreLaunchAllowed = preLaunchAllowed;
        }

        public string Name { get; }
        public string ReferenceName { get; }
        public IReadOnlyList<SessionMode> Modes { get; }
        public IReadOnlyList<SurfaceKind> Surfaces { get; }
        public bool RequiresObservationGrant { get; }
        public bool RequiresWriteLease { get; }
        public bool RequiresSemanticProvider { get; }
        public bool RequiresNativeInputGate { get; }
        public bool PreLaunchAllowed { get; }
    }

    public static class CapabilityApplicabilityV1
    {
        private static readonly SessionMode[] AllModes =
        {
            SessionMode.DeveloperInteractive,
            SessionMode.UnattendedTest,
            SessionMode.PlayerAssist
        };

        private static readonly SurfaceKind[] AllProductSurfaces =
        {
            SurfaceKind.Launcher,
            SurfaceKind.Flash,
            SurfaceKind.WebOverlay,
            SurfaceKind.NativeHud,
            SurfaceKind.WingsShell,
            SurfaceKind.BusinessModal
        };

        private static readonly SurfaceKind[] InteractiveSurfaces =
        {
            SurfaceKind.Flash,
            SurfaceKind.WebOverlay,
            SurfaceKind.NativeHud,
            SurfaceKind.WingsShell,
            SurfaceKind.BusinessModal
        };

        private static readonly SurfaceKind[] SemanticSurfaces =
            Array.Empty<SurfaceKind>();

        private static readonly SurfaceKind[] ActivationSurfaces =
        {
            SurfaceKind.Flash
        };

        public static readonly IReadOnlyList<CapabilityApplicability> GuiCapabilities =
            new[]
            {
                Define(AgentCapabilitiesV1.ListWindows, "list_windows", true, false, false, false, false,
                    AllProductSurfaces),
                Define(AgentCapabilitiesV1.GetWindow, "get_window", true, false, false, false, false,
                    AllProductSurfaces),
                Define(AgentCapabilitiesV1.ListApps, "list_apps", false, false, false, false, true,
                    Array.Empty<SurfaceKind>()),
                Define(AgentCapabilitiesV1.LaunchApp, "launch_app", false, false, false, false, true,
                    new[] { SurfaceKind.Launcher }),
                Define(AgentCapabilitiesV1.GetWindowState, "get_window_state", true, false, false, false, false,
                    AllProductSurfaces),
                Define(AgentCapabilitiesV1.Click, "click", true, true, false, true, false,
                    InteractiveSurfaces),
                Define(AgentCapabilitiesV1.PressKey, "press_key", true, true, false, true, false,
                    InteractiveSurfaces),
                Define(AgentCapabilitiesV1.TypeText, "type_text", true, true, false, true, false,
                    InteractiveSurfaces),
                Define(AgentCapabilitiesV1.Scroll, "scroll", true, true, false, true, false,
                    InteractiveSurfaces),
                Define(AgentCapabilitiesV1.SetValue, "set_value", true, true, true, false, false,
                    SemanticSurfaces),
                Define(AgentCapabilitiesV1.Drag, "drag", true, true, false, true, false,
                    InteractiveSurfaces),
                Define(AgentCapabilitiesV1.PerformSecondaryAction, "perform_secondary_action",
                    true, true, true, false, false, SemanticSurfaces),
                Define(AgentCapabilitiesV1.ActivateWindow, "activate_window", true, true, false, true, false,
                    ActivationSurfaces)
            };

        private static CapabilityApplicability Define(
            string name,
            string referenceName,
            bool requiresObservationGrant,
            bool requiresWriteLease,
            bool requiresSemanticProvider,
            bool requiresNativeInputGate,
            bool preLaunchAllowed,
            SurfaceKind[] surfaces)
        {
            return new CapabilityApplicability(
                name,
                referenceName,
                AllModes,
                surfaces,
                requiresObservationGrant,
                requiresWriteLease,
                requiresSemanticProvider,
                requiresNativeInputGate,
                preLaunchAllowed);
        }
    }
}
