using CF7Launcher.Guardian;
using Xunit;
namespace CF7Launcher.Tests.Guardian {
 public class BookComicPresentationPriorityTests {
  [Theory]
  [InlineData(true, true, true, false)]
  [InlineData(true, true, false, true)]
  [InlineData(true, false, false, false)]
  [InlineData(false, true, false, false)]
  public void LateCurtainHideCannotTakeFocusFromComic(bool requested, bool admitted, bool exclusive, bool expected) {
   Assert.Equal(expected, SceneTransitionController.AllowsFocusHandoff(requested, admitted, exclusive));
  }
  [Theory]
  [InlineData("book-comic", "panel:1", true)]
  [InlineData("book-comic", "", false)]
  [InlineData("book-comic", null, false)]
  [InlineData("loot", "panel:1", false)]
  [InlineData(null, "panel:1", false)]
  public void OnlyBoundComicSuppressesLowerTransition(string panel, string instance, bool expected) {
   Assert.Equal(expected, SceneTransitionController.IsExclusivePresentation(panel, instance));
  }
 }
}
