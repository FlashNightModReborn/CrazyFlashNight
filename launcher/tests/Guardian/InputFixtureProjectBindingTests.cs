using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Xml.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class InputFixtureProjectBindingTests
    {
        [Theory]
        [InlineData("g1-fixture/G1Host.csproj")]
        [InlineData("flash-hover-fixture/FlashHoverHost.csproj")]
        [InlineData("input-ownership-fixture/C1IslandHost.csproj")]
        public void InputFixturesReferenceCurrentCoreInsteadOfCopyingProductionSource(string relative)
        {
            string root=FindRoot();
            string project=Path.Combine(root,"launcher","native","world-compositor",relative.Replace('/',Path.DirectorySeparatorChar));
            var document=XDocument.Load(project);
            var reference=Assert.Single(document.Descendants("ProjectReference"));
            string resolved=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(project),reference.Attribute("Include").Value));
            Assert.Equal(Path.Combine(root,"launcher","CRAZYFLASHER7MercenaryEmpire.csproj"),resolved,true);
            string production=Path.Combine(root,"launcher","src")+Path.DirectorySeparatorChar;
            Assert.DoesNotContain(document.Descendants("Compile"),element=>
                Path.GetFullPath(Path.Combine(Path.GetDirectoryName(project),element.Attribute("Include").Value))
                    .StartsWith(production,StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void CoreGrantsTheExactInputFixtureAssembliesInternalAccess()
        {
            string[] friends=typeof(NativePointerBridge).Assembly.GetCustomAttributes<InternalsVisibleToAttribute>()
                .Select(value=>value.AssemblyName).ToArray();
            Assert.Contains("G1Host",friends);Assert.Contains("FlashHoverHost",friends);Assert.Contains("C1IslandHost",friends);
        }

        private static string FindRoot()
        {
            foreach(string start in new[] {Environment.CurrentDirectory,AppContext.BaseDirectory})
                for(var directory=new DirectoryInfo(start);directory!=null;directory=directory.Parent)
                    if(File.Exists(Path.Combine(directory.FullName,"launcher","CRAZYFLASHER7MercenaryEmpire.csproj")))
                        return directory.FullName;
            throw new DirectoryNotFoundException("Fixture contract tests require the repository source root.");
        }
    }
}
