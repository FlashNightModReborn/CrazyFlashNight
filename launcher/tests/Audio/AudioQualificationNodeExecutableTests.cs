using System;
using System.IO;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioQualificationNodeExecutableTests
    {
        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("node")]
        public void ResolveRejectsMissingOrNonAbsoluteBinding(string value)
        {
            Assert.Throws<InvalidOperationException>(() =>
                AudioQualificationNodeExecutable.Resolve(value));
        }

        [Fact]
        public void ResolveAcceptsCanonicalAbsoluteExecutable()
        {
            string executable = Environment.ProcessPath;
            Assert.False(string.IsNullOrEmpty(executable));
            Assert.Equal(
                Path.GetFullPath(executable),
                AudioQualificationNodeExecutable.Resolve(executable));
        }

        [Fact]
        public void ResolveRejectsMissingAbsoluteExecutable()
        {
            string missing = Path.Combine(
                Path.GetTempPath(),
                Guid.NewGuid().ToString("N"),
                "node.exe");
            Assert.Throws<InvalidOperationException>(() =>
                AudioQualificationNodeExecutable.Resolve(missing));
        }
    }
}
