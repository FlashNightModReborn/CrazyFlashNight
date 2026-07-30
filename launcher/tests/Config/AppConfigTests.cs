using System;
using System.IO;
using CF7Launcher.Config;
using Xunit;

namespace CF7Launcher.Tests.Config
{
    [CollectionDefinition(
        EnvironmentCollectionName,
        DisableParallelization = true)]
    public sealed class AppConfigEnvironmentCollection
    {
        public const string EnvironmentCollectionName =
            "AppConfig environment";
    }

    [Collection(
        AppConfigEnvironmentCollection.EnvironmentCollectionName)]
    public class AppConfigTests
    {
        private const string DeveloperModeEnvironment =
            "CF7_WEBVIEW2_DEV_MODE";

        [Fact]
        public void MissingConfig_DefaultsDeveloperModeFalse()
        {
            WithDeveloperModeEnvironment(
                null,
                delegate
                {
                    using (TemporaryProjectRoot root =
                        new TemporaryProjectRoot())
                    {
                        AppConfig config =
                            new AppConfig(root.Path);
                        Assert.False(
                            config.WebView2DeveloperMode);
                    }
                });
        }

        [Fact]
        public void MissingConfig_DefaultsPreparationNavigationV1True()
        {
            using (TemporaryProjectRoot root =
                new TemporaryProjectRoot())
            {
                AppConfig config =
                    new AppConfig(root.Path);

                Assert.True(
                    config.PreparationNavigationV1);
            }
        }

        [Theory]
        [InlineData("true", true)]
        [InlineData("false", false)]
        [InlineData("invalid", false)]
        public void TomlParsesPreparationNavigationV1(
            string value,
            bool expected)
        {
            using (TemporaryProjectRoot root =
                new TemporaryProjectRoot())
            {
                File.WriteAllText(
                    System.IO.Path.Combine(
                        root.Path,
                        "config.toml"),
                    "preparationNavigationV1 = "
                    + value);

                AppConfig config =
                    new AppConfig(root.Path);

                Assert.Equal(
                    expected,
                    config.PreparationNavigationV1);
            }
        }

        [Theory]
        [InlineData("true", true)]
        [InlineData("false", false)]
        [InlineData("invalid", false)]
        public void TomlParsesExplicitDeveloperMode(
            string value,
            bool expected)
        {
            WithDeveloperModeEnvironment(
                null,
                delegate
                {
                    using (TemporaryProjectRoot root =
                        new TemporaryProjectRoot())
                    {
                        File.WriteAllText(
                            System.IO.Path.Combine(
                                root.Path,
                                "config.toml"),
                            "webView2DeveloperMode = "
                            + value);

                        AppConfig config =
                            new AppConfig(root.Path);

                        Assert.Equal(
                            expected,
                            config.WebView2DeveloperMode);
                    }
                });
        }

        [Theory]
        [InlineData("1", true)]
        [InlineData("yes", true)]
        [InlineData("on", true)]
        [InlineData("0", false)]
        [InlineData("no", false)]
        [InlineData("off", false)]
        public void EnvironmentOverridesToml(
            string environmentValue,
            bool expected)
        {
            WithDeveloperModeEnvironment(
                environmentValue,
                delegate
                {
                    using (TemporaryProjectRoot root =
                        new TemporaryProjectRoot())
                    {
                        File.WriteAllText(
                            System.IO.Path.Combine(
                                root.Path,
                                "config.toml"),
                            "webView2DeveloperMode = "
                            + (!expected).ToString().ToLowerInvariant());

                        AppConfig config =
                            new AppConfig(root.Path);

                        Assert.Equal(
                            expected,
                            config.WebView2DeveloperMode);
                    }
                });
        }

        private static void WithDeveloperModeEnvironment(
            string value,
            Action action)
        {
            string previous =
                Environment.GetEnvironmentVariable(
                    DeveloperModeEnvironment);
            try
            {
                Environment.SetEnvironmentVariable(
                    DeveloperModeEnvironment,
                    value);
                action();
            }
            finally
            {
                Environment.SetEnvironmentVariable(
                    DeveloperModeEnvironment,
                    previous);
            }
        }

        private sealed class TemporaryProjectRoot :
            IDisposable
        {
            internal TemporaryProjectRoot()
            {
                Path = System.IO.Path.Combine(
                    System.IO.Path.GetTempPath(),
                    "cf7-app-config-tests-"
                    + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(Path);
            }

            internal string Path { get; }

            public void Dispose()
            {
                if (Directory.Exists(Path))
                    Directory.Delete(Path, true);
            }
        }
    }
}
