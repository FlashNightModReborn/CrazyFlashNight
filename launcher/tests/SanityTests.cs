using Xunit;

namespace CF7Launcher.Tests
{
    public class SanityTests
    {
        [Fact]
        public void TrueIsTrue()
        {
            Assert.True(true);
        }

        [Fact]
        public void MainAssemblyIsReferenced()
        {
            // 触达主工程类型以证明 ProjectReference 生效
            var t = typeof(CF7Launcher.Guardian.LogManager);
            Assert.NotNull(t);
        }
    }
}
