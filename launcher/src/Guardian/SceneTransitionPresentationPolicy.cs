using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // Selected once by the process entry point, never by AS2 or a Web request.
    internal sealed class SceneTransitionPresentationPolicy
    {
        internal static readonly SceneTransitionPresentationPolicy Interactive = new(false);
        internal static readonly SceneTransitionPresentationPolicy ArenaWorker = new(true);

        private SceneTransitionPresentationPolicy(bool nonActivating) => NonActivating = nonActivating;
        internal bool NonActivating { get; }

        internal bool AllowsBackgroundCurtain(JObject projection, bool connected,
            bool retainedSettlement, bool bookshelfActive, bool exclusive)
        {
            // Only the existing v1, report-free curtain can run unattended.
            // In particular revision 2 is not protocol version 2.
            return NonActivating && connected && !retainedSettlement && !bookshelfActive && !exclusive
                && projection?["version"]?.Type == JTokenType.Integer
                && projection.Value<long>("version") == 1
                && projection["report"] == null && projection["reportVisible"] == null
                && projection["reportHandoff"] == null;
        }

        internal bool CanPresentCurtain(bool admitted, bool ownerVisible, bool ownerMinimized,
            bool connected, bool foregroundOwned, bool backgroundQualified) =>
            admitted && ownerVisible && !ownerMinimized && (!NonActivating || connected)
                && (foregroundOwned || NonActivating && backgroundQualified);

        internal bool CanPresentSurface(bool ownerVisible, bool ownerMinimized,
            bool foregroundOwned, bool backgroundQualified) =>
            (!NonActivating || ownerVisible && !ownerMinimized)
                && (foregroundOwned || NonActivating && backgroundQualified);
    }
}
