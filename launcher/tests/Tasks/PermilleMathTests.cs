using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class PermilleMathTests
    {
        [Theory]
        [InlineData(18900L, 820L, 15498L)]
        [InlineData(300L, 820L, 246L)]
        [InlineData(1001L, 850L, 850L)]
        // These two vectors intentionally correct the former AS2 binary-float off-by-one results.
        [InlineData(17100L, 940L, 16074L)]
        [InlineData(2700L, 700L, 1890L)]
        public void TryFloor_UsesExactPermilleContract(
            long amount,
            long ratePermille,
            long expected)
        {
            Assert.True(PermilleMath.TryFloor(amount, ratePermille, out long actual));
            Assert.Equal(expected, actual);
        }

        [Fact]
        public void TryFloor_RejectsInvalidOrUnsafeInputs()
        {
            Assert.False(PermilleMath.TryFloor(-1, 1000, out _));
            Assert.False(PermilleMath.TryFloor(1, -1, out _));
            Assert.False(PermilleMath.TryFloor(
                PermilleMath.MaxSafeInteger + 1,
                1,
                out _));
            Assert.False(PermilleMath.TryFloor(
                PermilleMath.MaxSafeInteger,
                2,
                out _));
        }

        [Fact]
        public void TryFloor_AcceptsSafeUpperBoundaryOnlyWhenIntermediateIsSafe()
        {
            Assert.True(PermilleMath.TryFloor(
                PermilleMath.MaxSafeInteger,
                1,
                out long actual));
            Assert.Equal(9007199254740L, actual);
            Assert.False(PermilleMath.TryFloor(
                PermilleMath.MaxSafeInteger,
                PermilleMath.Scale,
                out _));
        }

        [Fact]
        public void TryReadSafeNonNegativeInteger_RejectsFloatNaNInfinityAndBounds()
        {
            Assert.False(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(1.5), out _));
            Assert.False(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(double.NaN), out _));
            Assert.False(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(double.PositiveInfinity), out _));
            Assert.False(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(-1), out _));
            Assert.False(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(PermilleMath.MaxSafeInteger + 1), out _));
            Assert.True(PermilleMath.TryReadSafeNonNegativeInteger(
                new JValue(PermilleMath.MaxSafeInteger), out long actual));
            Assert.Equal(PermilleMath.MaxSafeInteger, actual);
        }

        [Fact]
        public void PurchaseOrder_KeepsFloorAfterQuantityMultiplication()
        {
            Assert.True(PermilleMath.TryMultiply(1001, 2, out long amount));
            Assert.True(PermilleMath.TryFloor(amount, 850, out long total));
            Assert.Equal(1701, total);

            Assert.True(PermilleMath.TryFloor(1001, 850, out long unitPrice));
            Assert.Equal(850, unitPrice);
            Assert.NotEqual(unitPrice * 2, total);
        }

        [Fact]
        public void SignedArithmetic_StaysExactInsideSafeIntegerDomain()
        {
            Assert.True(PermilleMath.TrySubtract(100, 200, out long netDelta));
            Assert.Equal(-100, netDelta);
            Assert.True(PermilleMath.TryAddSigned(50, netDelta, out long projected));
            Assert.Equal(-50, projected);

            Assert.False(PermilleMath.TryAddSigned(
                PermilleMath.MaxSafeInteger,
                1,
                out _));
            Assert.False(PermilleMath.TrySubtract(
                -PermilleMath.MaxSafeInteger,
                1,
                out _));
        }
    }
}
