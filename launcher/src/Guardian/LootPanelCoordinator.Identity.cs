namespace CF7Launcher.Guardian
{
    // Shared pure identity validation. Keep the transport tasks independent of the UI
    // coordinator's platform dependencies; production and portable hosts use this one rule.
    public sealed partial class LootPanelCoordinator
    {
        public const int MaximumOpaqueLength = 128;

        public static bool IsOpaque(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > MaximumOpaqueLength) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '~' || c == '-';
                if (!allowed) return false;
            }
            return true;
        }
    }
}
