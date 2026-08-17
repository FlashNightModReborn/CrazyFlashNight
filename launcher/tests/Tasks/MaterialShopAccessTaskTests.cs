using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MaterialShopAccessTaskTests
    {
        [Fact]
        public void TryAuthorize_SendsExactRequestAndStartsAtFidOne()
        {
            string sent = null;
            using var task = new MaterialShopAccessTask(
                () => true,
                payload => { sent = payload; return true; });

            bool accepted = task.TryAuthorize(
                Request(),
                () => true,
                _ => { },
                out int fid);

            Assert.True(accepted);
            Assert.Equal(1, fid);
            Assert.EndsWith("\0", sent, StringComparison.Ordinal);
            JObject wire = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal(
                new[]
                {
                    "task", "action", "callId", "v", "materialSnapshotId",
                    "materialName", "shopId", "catalogIndex"
                },
                wire.Properties().Select(p => p.Name));
            Assert.Equal("cmd", wire.Value<string>("task"));
            Assert.Equal("craftingMaterialShopAuthorize", wire.Value<string>("action"));
            Assert.Equal(1, wire.Value<int>("callId"));
            Assert.Equal(1, wire.Value<int>("v"));
            Assert.Equal("materials.snapshot.42", wire.Value<string>("materialSnapshotId"));
            Assert.Equal("战术握把", wire.Value<string>("materialName"));
            Assert.Equal("迷之盔甲君", wire.Value<string>("shopId"));
            Assert.Equal(57, wire.Value<int>("catalogIndex"));
        }

        [Fact]
        public void ProcurementAuthorization_BindsStableRecipeTupleAndExactReceipt()
        {
            string sent = null;
            MaterialShopAccessTask.Result observed = null;
            using var task = new MaterialShopAccessTask(
                () => true,
                payload => { sent = payload; return true; });

            Assert.True(task.TryAuthorize(
                ProcurementRequest(),
                () => true,
                value => observed = value,
                out int fid));

            JObject wire = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal(
                new[]
                {
                    "task", "action", "callId", "v", "materialName",
                    "shopId", "catalogIndex", "recipeId",
                    "category", "recipeIndex"
                },
                wire.Properties().Select(p => p.Name));
            Assert.Equal("craftingProcurementShopAuthorize", wire.Value<string>("action"));
            Assert.Equal("craft.weapon.004", wire.Value<string>("recipeId"));
            Assert.Equal("武器合成", wire.Value<string>("category"));
            Assert.Equal(3, wire.Value<int>("recipeIndex"));

            task.HandleFlashResponse(ProcurementAllow(fid), _ => { });

            Assert.NotNull(observed);
            Assert.Equal(MaterialShopAccessTask.ResultKind.Allowed, observed.Kind);
            Assert.Equal("战术握把", observed.ItemName);
            Assert.Equal(0, task.PendingCount);
        }

        [Fact]
        public void ProcurementAllowResponse_RejectsAnyRecipeTupleDrift()
        {
            foreach (Action<JObject> mutate in new Action<JObject>[]
            {
                value => value["recipeId"] = "craft.weapon.005",
                value => value["category"] = "属性武器",
                value => value["recipeIndex"] = 4,
                value => value["reason"] = "indexed_live_match"
            })
            {
                MaterialShopAccessTask.Result observed = null;
                using var task = ConnectedTask();
                task.TryAuthorize(
                    ProcurementRequest(),
                    () => true,
                    value => observed = value,
                    out int fid);
                JObject response = ProcurementAllow(fid);
                mutate(response);

                task.HandleFlashResponse(response, _ => { });

                Assert.Equal(MaterialShopAccessTask.ResultKind.MalformedResponse, observed.Kind);
            }
        }

        [Fact]
        public void KShopProcurementAuthorization_BindsExactCatalogAndRecipeTuple()
        {
            string sent = null;
            MaterialShopAccessTask.Result observed = null;
            using var task = new MaterialShopAccessTask(
                () => true,
                payload => { sent = payload; return true; });

            Assert.True(task.TryAuthorize(
                KShopProcurementRequest(), () => true,
                value => observed = value, out int fid));

            JObject wire = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("craftingProcurementKShopAuthorize",
                wire.Value<string>("action"));
            Assert.Null(wire["shopId"]);
            Assert.Null(wire["materialSnapshotId"]);
            Assert.Equal(11, wire.Count);
            Assert.Equal("k-material-7", wire.Value<string>("entryId"));
            Assert.Equal("材料", wire.Value<string>("kshopCategory"));
            Assert.Equal("武器合成", wire.Value<string>("recipeCategory"));

            task.HandleFlashResponse(KShopProcurementAllow(fid), _ => { });

            Assert.NotNull(observed);
            Assert.Equal(MaterialShopAccessTask.ResultKind.Allowed, observed.Kind);
            Assert.Equal("战术握把", observed.ItemName);
        }

        [Fact]
        public void FidAllocator_UsesMaxWrapsAndSkipsPending()
        {
            var sent = new List<JObject>();
            using var task = new MaterialShopAccessTask(
                () => true,
                payload =>
                {
                    sent.Add(JObject.Parse(payload.TrimEnd('\0')));
                    return true;
                });
            task.SetFidCursorForTests(int.MaxValue - 1);

            Assert.True(task.TryAuthorize(Request(), () => true, _ => { }, out int max));
            Assert.Equal(int.MaxValue, max);
            Assert.True(task.TryAuthorize(Request(), () => true, _ => { }, out int one));
            Assert.Equal(1, one);
            task.SetFidCursorForTests(int.MaxValue);
            Assert.True(task.TryAuthorize(Request(), () => true, _ => { }, out int two));
            Assert.Equal(2, two);
            Assert.Equal(new[] { int.MaxValue, 1, 2 },
                sent.Select(v => v.Value<int>("callId")));
        }

        [Fact]
        public void ExactAllowResponse_ValidatesEveryEcho()
        {
            MaterialShopAccessTask.Result observed = null;
            using var task = ConnectedTask();
            task.TryAuthorize(Request(), () => true, value => observed = value, out int fid);

            task.HandleFlashResponse(Allow(fid), _ => { });

            Assert.NotNull(observed);
            Assert.Equal(MaterialShopAccessTask.ResultKind.Allowed, observed.Kind);
            Assert.Equal("战术握把", observed.ItemName);
            Assert.Equal(0, task.PendingCount);
        }

        [Fact]
        public void ExactAllowResponse_AcceptsCatalogIndexZero()
        {
            MaterialShopAccessTask.Result observed = null;
            using var task = ConnectedTask();
            task.TryAuthorize(
                Request(0),
                () => true,
                value => observed = value,
                out int fid);

            task.HandleFlashResponse(Allow(fid, 0), _ => { });

            Assert.NotNull(observed);
            Assert.Equal(MaterialShopAccessTask.ResultKind.Allowed, observed.Kind);
        }

        [Fact]
        public void AllowResponse_RejectsOutOfRangeOrNonIntegerCatalogIndex()
        {
            foreach (JToken invalid in new JToken[]
            {
                -1,
                10001,
                0.0
            })
            {
                MaterialShopAccessTask.Result observed = null;
                using var task = ConnectedTask();
                task.TryAuthorize(
                    Request(0),
                    () => true,
                    value => observed = value,
                    out int fid);
                JObject response = Allow(fid, 0);
                response["catalogIndex"] = invalid;

                task.HandleFlashResponse(response, _ => { });

                Assert.Equal(
                    MaterialShopAccessTask.ResultKind.MalformedResponse,
                    observed.Kind);
            }
        }

        [Theory]
        [InlineData("stale", "stale_snapshot", 1)]
        [InlineData("stale", "source_not_current", 1)]
        [InlineData("stale", "catalog_not_current", 1)]
        [InlineData("deny", "invalid_payload", 2)]
        [InlineData("deny", "authority_unavailable", 2)]
        [InlineData("deny", "access_denied", 2)]
        public void ExactFailureResponse_AcceptsOnlyFrozenPairs(
            string decision,
            string error,
            int expected)
        {
            MaterialShopAccessTask.Result observed = null;
            using var task = ConnectedTask();
            task.TryAuthorize(Request(), () => true, value => observed = value, out int fid);

            task.HandleFlashResponse(
                new JObject
                {
                    ["task"] = "material_shop_access_response",
                    ["callId"] = fid,
                    ["success"] = false,
                    ["v"] = 1,
                    ["decision"] = decision,
                    ["error"] = error
                },
                _ => { });

            Assert.Equal((MaterialShopAccessTask.ResultKind)expected, observed.Kind);
            Assert.Equal(error, observed.Error);
        }

        [Fact]
        public void ResponseWithExtraWrongTypeOrEcho_IsMalformed()
        {
            foreach (Action<JObject> mutate in new Action<JObject>[]
            {
                value => value["extra"] = true,
                value => value["success"] = "true",
                value => value["shopId"] = "漂移商店",
                value => value["itemName"] = "同名漂移"
            })
            {
                MaterialShopAccessTask.Result observed = null;
                using var task = ConnectedTask();
                task.TryAuthorize(Request(), () => true, value => observed = value, out int fid);
                JObject response = Allow(fid);
                mutate(response);

                task.HandleFlashResponse(response, _ => { });

                Assert.Equal(MaterialShopAccessTask.ResultKind.MalformedResponse, observed.Kind);
            }
        }

        [Fact]
        public void CancelOrFalseFence_DropsLateResponse()
        {
            int completions = 0;
            using var task = ConnectedTask();
            task.TryAuthorize(Request(), () => true, _ => completions++, out int cancelled);
            Assert.True(task.Cancel(cancelled));
            task.HandleFlashResponse(Allow(cancelled), _ => { });

            bool current = true;
            task.TryAuthorize(Request(), () => current, _ => completions++, out int fenced);
            current = false;
            task.HandleFlashResponse(Allow(fenced), _ => { });

            Assert.Equal(0, completions);
            Assert.Equal(0, task.PendingCount);
        }

        [Fact]
        public void FenceExpiringImmediatelyAfterFidPublication_DoesNotSendOrLeakPending()
        {
            int sends = 0;
            bool current = true;
            using var task = new MaterialShopAccessTask(
                () => true,
                _ => { sends++; return true; });

            bool accepted = task.TryAuthorize(
                Request(),
                () => current,
                _ => { },
                _ => current = false,
                out int fid);

            Assert.True(accepted);
            Assert.Equal(1, fid);
            Assert.Equal(0, sends);
            Assert.Equal(0, task.PendingCount);
        }

        [Fact]
        public void TaskOwnsNoTimer()
        {
            Assert.DoesNotContain(
                typeof(MaterialShopAccessTask).GetFields(
                    BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public),
                field => typeof(Timer).IsAssignableFrom(field.FieldType));
        }

        private static MaterialShopAccessTask ConnectedTask()
        {
            return new MaterialShopAccessTask(() => true, _ => true);
        }

        private static MaterialShopAccessTask.Request Request(int catalogIndex = 57)
        {
            return new MaterialShopAccessTask.Request
            {
                MaterialSnapshotId = "materials.snapshot.42",
                MaterialName = "战术握把",
                ShopId = "迷之盔甲君",
                CatalogIndex = catalogIndex
            };
        }

        private static MaterialShopAccessTask.Request ProcurementRequest()
        {
            return new MaterialShopAccessTask.Request
            {
                MaterialName = "战术握把",
                ShopId = "迷之盔甲君",
                CatalogIndex = 57,
                IsProcurement = true,
                RecipeId = "craft.weapon.004",
                Category = "武器合成",
                RecipeIndex = 3
            };
        }

        private static MaterialShopAccessTask.Request KShopProcurementRequest()
        {
            return new MaterialShopAccessTask.Request
            {
                MaterialName = "战术握把",
                CatalogIndex = 7,
                IsProcurement = true,
                IsKShop = true,
                EntryId = "k-material-7",
                KShopCategory = "材料",
                RecipeId = "craft.weapon.004",
                Category = "武器合成",
                RecipeIndex = 3
            };
        }

        private static JObject Allow(int fid, int catalogIndex = 57)
        {
            return new JObject
            {
                ["task"] = "material_shop_access_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["decision"] = "allow",
                ["reason"] = "indexed_live_match",
                ["materialSnapshotId"] = "materials.snapshot.42",
                ["materialName"] = "战术握把",
                ["shopId"] = "迷之盔甲君",
                ["catalogIndex"] = catalogIndex,
                ["itemName"] = "战术握把"
            };
        }

        private static JObject ProcurementAllow(int fid)
        {
            JObject response = Allow(fid);
            response.Remove("materialSnapshotId");
            response["reason"] = "procurement_indexed_live_match";
            response["recipeId"] = "craft.weapon.004";
            response["category"] = "武器合成";
            response["recipeIndex"] = 3;
            return response;
        }

        private static JObject KShopProcurementAllow(int fid)
        {
            return new JObject
            {
                ["task"] = "material_shop_access_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["decision"] = "allow",
                ["reason"] = "procurement_kshop_indexed_live_match",
                ["materialName"] = "战术握把",
                ["catalogIndex"] = 7,
                ["entryId"] = "k-material-7",
                ["category"] = "材料",
                ["itemName"] = "战术握把",
                ["recipeId"] = "craft.weapon.004",
                ["recipeCategory"] = "武器合成",
                ["recipeIndex"] = 3
            };
        }
    }
}
