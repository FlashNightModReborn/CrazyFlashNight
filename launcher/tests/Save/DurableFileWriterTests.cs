using System;
using System.IO;
using System.Text;
using CF7Launcher.Save;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public sealed class DurableFileWriterTests : IDisposable
    {
        private readonly string root = Path.Combine(Path.GetTempPath(), "cf7-durable-" + Guid.NewGuid().ToString("N"));
        public DurableFileWriterTests() { Directory.CreateDirectory(root); }
        private string Target => Path.Combine(root, "测试存档.json");
        private static readonly Encoding Utf8 = new UTF8Encoding(false);

        [Fact]
        public void NewAndReplacementAreReadableWithoutArtifacts()
        {
            DurableFileWriter.WriteAllText(Target, "旧数据", Utf8);
            DurableFileWriter.WriteAllText(Target, "新数据", Utf8);
            Assert.Equal("新数据", File.ReadAllText(Target));
            Assert.Single(Directory.GetFiles(root));
        }

        [Fact]
        public void CommitRejectedPreservesPriorBytesAndRecoveryCopy()
        {
            File.WriteAllText(Target, "old", Utf8);
            Assert.Throws<IOException>(() => DurableFileWriter.WriteAllText(Target, "new", Utf8,
                (temporary, target) => { throw new IOException("injected replacement denial"); }));
            Assert.Equal("old", File.ReadAllText(Target));
            Assert.Equal("old", File.ReadAllText(Assert.Single(Directory.GetFiles(root, "*.previous-*"))));
            Assert.Empty(Directory.GetFiles(root, "*.tmp-*"));
        }

        [Fact]
        public void PartialReplacementFailureRestoresMissingTarget()
        {
            File.WriteAllText(Target, "old", Utf8);
            Assert.Throws<IOException>(() => DurableFileWriter.WriteAllText(Target, "new", Utf8,
                (temporary, target) => { File.Delete(target); throw new IOException("injected partial replacement"); }));
            Assert.Equal("old", File.ReadAllText(Target));
            Assert.Single(Directory.GetFiles(root));
        }

        [Fact]
        public void ThrowAfterCommitIsReconciledAsSuccess()
        {
            File.WriteAllText(Target, "old", Utf8);
            DurableFileWriter.WriteAllText(Target, "new", Utf8, (temporary, target) =>
            {
                File.Replace(temporary, target, null);
                throw new IOException("injected unknown return after commit");
            });
            Assert.Equal("new", File.ReadAllText(Target));
            Assert.Single(Directory.GetFiles(root));
        }

        [Fact]
        public void UnreadableCommittedTargetRemainsUnconfirmedWithPriorCopy()
        {
            File.WriteAllText(Target, "old", Utf8);
            FileStream held = null;
            try
            {
                Assert.Throws<FileCommitUnconfirmedException>(() => DurableFileWriter.WriteAllText(Target, "new", Utf8,
                    (temporary, target) =>
                    {
                        File.Replace(temporary, target, null);
                        held = new FileStream(target, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
                        throw new IOException("committed but readback is inaccessible");
                    }));
            }
            finally { held?.Dispose(); }
            Assert.Equal("new", File.ReadAllText(Target));
            Assert.Equal("old", File.ReadAllText(Assert.Single(Directory.GetFiles(root, "*.previous-*"))));
        }

        [Fact]
        public void LockedPriorFileIsNotTruncated()
        {
            File.WriteAllText(Target, "old", Utf8);
            using (new FileStream(Target, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                Assert.Throws<IOException>(() => DurableFileWriter.WriteAllText(Target, "new", Utf8));
            Assert.Equal("old", File.ReadAllText(Target));
            Assert.Single(Directory.GetFiles(root));
        }

        [Fact]
        public void NewFileMoveFailureDoesNotInventCommittedTarget()
        {
            Assert.Throws<IOException>(() => DurableFileWriter.WriteAllText(Target, "new", Utf8,
                (temporary, target) => { throw new IOException("injected move denial"); }));
            Assert.False(File.Exists(Target));
            Assert.Empty(Directory.GetFiles(root));
        }

        public void Dispose()
        {
            string resolved = Path.GetFullPath(root);
            if (!resolved.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("fixture cleanup escaped temporary root");
            Directory.Delete(resolved, true);
        }
    }
}
