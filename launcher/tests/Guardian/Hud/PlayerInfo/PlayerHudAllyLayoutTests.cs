using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public class PlayerHudAllyLayoutTests
{
    [Theory]
    [InlineData(2, 1, 28)]
    [InlineData(2, 4, 31)]
    [InlineData(4, 1, 31)]
    [InlineData(10, 1, 31)]
    [InlineData(11, 1, 59)]
    [InlineData(20, 1, 59)]
    [InlineData(21, 1, 87)]
    public void TrayEndsAfterLastOccupiedRow(int occupiedSlots,int focus,int height)
    {
        var tray=PlayerHudAllyLayout.Tray(occupiedSlots,focus,63);
        Assert.Equal(height,tray.Height);
        float expectedWidth=occupiedSlots<=10 ? PlayerHudAllyLayout.Cell(occupiedSlots-1,occupiedSlots,focus,tray.Top).Right-tray.X+5 : 294;
        Assert.Equal(expectedWidth,tray.Width);
        Assert.True(tray.Contains(PlayerHudAllyLayout.Cell(occupiedSlots-1,occupiedSlots,focus,tray.Top)));
        if (occupiedSlots>=4)
            Assert.Equal(PlayerHudAllyLayout.Cell(0,4,focus,tray.Top),PlayerHudAllyLayout.Cell(0,occupiedSlots,focus,tray.Top));
    }
}
