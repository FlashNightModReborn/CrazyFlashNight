namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Immutable post-acquire witness for the narrow materials-to-NPCShop transition.
    /// Each owning task validates its own task name, lease token, owner tuple and generation;
    /// task-specific authority fields are populated only by the task that owns them.
    /// </summary>
    internal sealed class MaterialShopSettlementWitness
    {
        internal string TaskName;
        internal string LeaseToken;
        internal string OwnerPanel;
        internal string OwnerPanelInstanceId;
        internal long Generation;
        internal string MaterialSnapshotId;
        internal string MaterialName;
        internal string ShopId;
        internal bool RequiresCatalogAuthority;
    }
}
