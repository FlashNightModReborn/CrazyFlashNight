using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading.Tasks;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public class FocusInputBufferTests
    {
        [Fact]
        public void HistoryRetainsUpOutsideNewDownAndReportsAmbiguityAndExpiry()
        {
            var history = new FocusMouseHistory();
            var p = new Point(10, 20);
            history.Edge(true, true, p, "first", 100);
            history.Edge(false, false, Point.Empty, null, 110);
            history.Edge(true, false, new Point(500, 500), null, 120);
            Assert.Equal("first", history.Candidate(p, 4000, out int count));
            Assert.Equal(1, count);
            history.Edge(true, true, p, "second", 5000);
            Assert.Null(history.Candidate(p, 5001, out count));
            Assert.Equal(2, count);
            Assert.Equal("second", history.Candidate(p, 11000, out count));
            Assert.Equal(1, count);
            Assert.Null(history.Candidate(p, 15001, out count));
        }

        [Fact]
        public void HistoryOverflowIsExplicitAndDoesNotGrow()
        {
            var history = new FocusMouseHistory();
            for (int i = 0; i < 129; i++) history.Edge(true, true, new Point(i, 1), i.ToString(), i);
            Assert.Equal(1, history.Overwritten);
            Assert.Null(history.Candidate(new Point(0, 1), 200, out _));
            Assert.Equal("128", history.Candidate(new Point(128, 1), 200, out _));
        }

        [Fact]
        public void ParallelWritersNeverExposePartialRowsAndAccountForEveryDrop()
        {
            var buffer = new FocusInputBuffer();
            const int total = 5000;
            Parallel.For(0, total, i => buffer.Add(new InputRow { name = "fixture", sequence = i,
                data = new InputData { invocationId = i, wParam = i + 11 } }));
            JObject[] rows = buffer.Drain("fixture").Select(x => JObject.Parse(x.Substring(13))).ToArray();
            JObject[] delivered = rows.Where(x => (string)x["event"] == "fixture").ToArray();
            Assert.True(delivered.Length <= FocusInputBuffer.Capacity);
            Assert.Equal(delivered.Length, delivered.Select(x => (long)x["seq"]).Distinct().Count());
            Assert.All(delivered, x => Assert.Equal((long)x["seq"] + 11, (long)x["data"]["wParam"]));
            Assert.Equal(total, delivered.Length + rows.Where(x => (string)x["event"] == "input.dropped").Sum(x => (int)x["count"]));
            Assert.Empty(buffer.Drain("fixture"));
        }

        [Fact]
        public void FastInputKeepsOriginalTimeAndNeverCallsRichSnapshot()
        {
            var lines = new List<string>();
            FocusTrace.Start(lines.Add, false);
            try
            {
                FocusTrace.HudInputSnapshot = _ => throw new Exception("must not call");
                FocusTrace.Input("early", new InputData { messageTime = uint.MaxValue, flags = 0 }, qpc: 123);
                FocusTrace.Input("removed", new InputData { messageTime = 1, flags = 1 }, qpc: 456);
                FocusTrace.Flush();
                var rows = lines.SelectMany(x => x.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                    .Select(x => JObject.Parse(x.Substring(13))).ToArray();
                Assert.Equal(123, (long)rows.Single(x => (string)x["event"] == "early")["ticks"]);
                Assert.Equal(uint.MaxValue, (uint)rows.Single(x => (string)x["event"] == "early")["data"]["messageTime"]);
                Assert.Equal(1U, (uint)rows.Single(x => (string)x["event"] == "removed")["data"]["flags"]);
            }
            finally { FocusTrace.HudInputSnapshot = null; FocusTrace.Stop(); }
        }
    }
}
