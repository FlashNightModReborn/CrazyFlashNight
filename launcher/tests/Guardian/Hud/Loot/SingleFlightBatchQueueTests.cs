using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public class SingleFlightBatchQueueTests
    {
        [Fact]
        public void Burst_RequestsExactlyOneUiPostAndOneBatch()
        {
            var queue = new SingleFlightBatchQueue<int>();
            int postRequests = 0;

            Parallel.For(0, 1000, i =>
            {
                if (queue.Enqueue(i))
                    Interlocked.Increment(ref postRequests);
            });

            Assert.Equal(1, postRequests);
            Assert.True(queue.IsScheduled);
            Assert.Equal(1000, queue.PendingCount);
            Assert.Equal(Enumerable.Range(0, 1000).OrderBy(i => i),
                queue.BeginDrain().OrderBy(i => i));
            Assert.False(queue.CompleteDrain());
            Assert.False(queue.IsScheduled);
        }

        [Fact]
        public void ArrivalsDuringDrain_CollapseIntoOneFollowUpPost()
        {
            var queue = new SingleFlightBatchQueue<int>();
            Assert.True(queue.Enqueue(1));
            Assert.Equal(new[] { 1 }, queue.BeginDrain());

            Assert.False(queue.Enqueue(2));
            Assert.False(queue.Enqueue(3));
            Assert.True(queue.CompleteDrain());
            Assert.True(queue.IsScheduled);

            Assert.Equal(new[] { 2, 3 }, queue.BeginDrain());
            Assert.False(queue.CompleteDrain());
            Assert.False(queue.IsScheduled);
        }

        [Fact]
        public void Abort_ClearsBatchAndAllowsFreshScheduling()
        {
            var queue = new SingleFlightBatchQueue<int>();
            Assert.True(queue.Enqueue(1));
            queue.Abort();

            Assert.Equal(0, queue.PendingCount);
            Assert.False(queue.IsScheduled);
            Assert.True(queue.Enqueue(2));
        }
    }
}
