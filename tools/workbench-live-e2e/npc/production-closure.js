"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { canonicalJson, fail, isPlainObject, sha256Bytes, sha256Text } = require("./common");

const CLOSURE_SCHEMA = "workbench-live-e2e.npc.production-closure.v12";
const INVENTORY_SURFACE_CONTRACT_SCHEMA =
  "workbench-live-e2e.npc.production-inventory-surface.v10";
const INVENTORY_SURFACE_SOURCE_SCHEMA =
  "workbench-live-e2e.npc.production-inventory-source-anchors.v8";
const BINDING_SCHEMA = "workbench-live-e2e.npc.production-binding.v3";
const SHOP_BINDING_SCHEMA = "workbench-live-e2e.npc.actual-shop-binding.v1";
const LOADED_SCHEMA = "workbench-live-e2e.npc.loaded-production.v6";
const CANDIDATE_PRODUCER_SCHEMA = "workbench-live-e2e.npc.candidate-producer-binding.v2";
const RUNTIME_INPUTS_SCHEMA = "workbench-live-e2e.npc.runtime-inputs.v1";
const SHA256_RE = /^[A-F0-9]{64}$/;
const artifactSourceCache = new Map();
const runtimeInputCache = new Map();
const resourceFileCache = new Map();
const INVENTORY_SURFACE_CONSUMER_ANCHORS = Object.freeze([
  Object.freeze({ id: "npc_adapter_delegation", source:
    "NpcShopRuntime.createPhysicalInventoryAdapter({"
      + "inventoryRuntime:InventoryRuntime,request:requestInventory,owner:_owner," }),
  Object.freeze({ id: "npc_on_open_session_reset", source:
    "if(!_inventoryAdapter.resetSession())returnfalse;" }),
  Object.freeze({ id: "npc_owner_open", source:
    "if(!_owner.open(initData.panelInstanceId))returnfalse;" }),
  Object.freeze({ id: "npc_refresh_delegation", source:
    "functionrefreshInventory(callback){return_inventoryAdapter.refresh(callback);}" }),
  Object.freeze({ id: "npc_receipt_projection", source:
    "inventorySurface:_inventoryAdapter.getReceipt()" }),
  Object.freeze({ id: "npc_inventory_write_fence", source:
    "functioninventoryWriteUnavailable(){return!_inventoryState.ready"
      + "||!!_inventoryState.busyOwner||!!_inventoryState.refreshRequired;}" }),
  Object.freeze({ id: "npc_retry_surface", source:
    "_retryButton.className='workbench-mode-btn warning npcshop-retry-btn';" }),
  Object.freeze({ id: "npc_retry_listener", source:
    "_retryButton=document.createElement('button');"
      + "_retryButton.type='button';"
      + "_retryButton.className='workbench-mode-btn warning npcshop-retry-btn';"
      + "_retryButton.textContent='重新同步';"
      + "_retryButton.addEventListener('click',refreshSnapshot);"
      + "_shell.addHeaderAction(_retryButton);" }),
  Object.freeze({ id: "npc_retry_status", source:
    "elseif(needsInventoryRetry)_shell.setStatus('库存需要重新同步','error');" }),
  Object.freeze({ id: "npc_open_settlement_write_fence", source:
    "if(!selectionCount()||_busy||_owner.needsReconcile||inventoryWriteUnavailable())return;" }),
  Object.freeze({ id: "npc_preview_write_fence", source:
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
      + "||!_settlementPresenter||!_settlementPresenter.isActive())return;" }),
  Object.freeze({ id: "npc_commit_write_fence", source:
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()"
      + "||!_settlement||!_settlement.canCommit||_previewBusy)return;" }),
  Object.freeze({ id: "npc_write_dispatch_fence", source:
    "if(_busy||_owner.needsReconcile||inventoryWriteUnavailable()){"
      + "toast(_owner.needsReconcile||_inventoryState.refreshRequired||!_inventoryState.ready"
      + "?'请先重新同步商店状态。':'正在处理上一项交易。');returnfalse;}" }),
  Object.freeze({ id: "npc_checkout_write_fence", source:
    "if(_checkoutButton){_checkoutButton.textContent=count?'结算 ('+count+')':'结算';"
      + "_checkoutButton.disabled=!count||_busy||_owner.needsReconcile"
      + "||inventoryWriteUnavailable();}" }),
]);
const INVENTORY_SURFACE_ADAPTER_ANCHORS = Object.freeze([
  Object.freeze({ id: "adapter_definition", source:
    "functionPhysicalInventoryAdapter(options)" }),
  Object.freeze({ id: "adapter_exact_owner", source:
    "returnruntime.readPhysicalInventorySurface(request,"
      + "{isActive:isActive,expectedPanel:'npcshop',"
      + "expectedPanelInstanceId:owner.panelInstanceId},callback);" }),
  Object.freeze({ id: "adapter_initial_windows", source:
    "requests:[{containerId:'背包',offset:0,limit:50,filterKey:'all'},"
      + "{containerId:'战备箱',offset:0,limit:40,filterKey:'all'}]" }),
  Object.freeze({ id: "adapter_refresh_open_only", source:
    "PhysicalInventoryAdapter.prototype.refresh=function(callback){"
      + "varself=this,coordinator=this.coordinator;coordinator.open(function(result){" }),
  Object.freeze({ id: "adapter_receipt_copy", source:
    "self._surfaceReceipt=result.success&&result.surface"
      + "?JSON.parse(JSON.stringify(result.surface)):null;" }),
  Object.freeze({ id: "adapter_reset_definition", source:
    "PhysicalInventoryAdapter.prototype.resetSession=function(){" }),
  Object.freeze({ id: "adapter_reset_closed_only", source:
    "if(coordinator.debugState().opened)returnfalse;" }),
  Object.freeze({ id: "adapter_reset_reads_backpack", source:
    "varbackpack=coordinator.getRequest('背包');" }),
  Object.freeze({ id: "adapter_reset_reads_battlebox", source:
    "varbattlebox=coordinator.getRequest('战备箱');" }),
  Object.freeze({ id: "adapter_reset_clears_receipt", source:
    "this._surfaceReceipt=null;returncoordinator.configureRequests([" }),
  Object.freeze({ id: "adapter_reset_atomic_configure", source:
    "returncoordinator.configureRequests([{containerId:'背包',"
      + "offset:backpack.offset,limit:50,filterKey:'all'},"
      + "{containerId:'战备箱',offset:battlebox.offset,limit:40,filterKey:'all'}]);" }),
  Object.freeze({ id: "adapter_cleanup", source:
    "this.coordinator.close();this._surfaceReceipt=null;" }),
]);
const INVENTORY_SURFACE_ADAPTER_FORBIDDEN_ANCHORS = Object.freeze([
  Object.freeze({ id: "refresh_calls_reset_session", method: "refresh", source: "resetSession(" }),
  Object.freeze({ id: "refresh_calls_configure_requests", method: "refresh", source:
    "configureRequests(" }),
  Object.freeze({ id: "refresh_calls_reset_window", method: "refresh", source: "resetWindow(" }),
  Object.freeze({ id: "refresh_closes_coordinator", method: "refresh", source: "coordinator.close(" }),
  Object.freeze({ id: "reset_uses_sequential_window_mutation", method: "resetSession", source:
    "resetWindow(" }),
  Object.freeze({ id: "reset_opens_coordinator", method: "resetSession", source: "coordinator.open(" }),
  Object.freeze({ id: "reset_closes_coordinator", method: "resetSession", source: "coordinator.close(" }),
]);
const INVENTORY_SURFACE_PROVIDER_ANCHORS = Object.freeze([
  Object.freeze({ id: "battle_access_set", source:
    "varPHYSICAL_BATTLE_ACCESS={0:true,40:true,80:true,120:true,160:true,200:true,240:true};" }),
  Object.freeze({ id: "first_batch", source:
    "{containerId:'背包',offset:0,limit:50,filterKey:'all'},"
      + "{containerId:'战备箱',offset:0,limit:100,filterKey:'all'}" }),
  Object.freeze({ id: "supplement_100", source:
    "if(accessibleCapacity>100){batches.push([{containerId:'战备箱',offset:100,limit:100,filterKey:'all'}]);}" }),
  Object.freeze({ id: "supplement_200", source:
    "if(accessibleCapacity>200){batches.push([{containerId:'战备箱',offset:200,"
      + "limit:accessibleCapacity-200,filterKey:'all'}]);}" }),
  Object.freeze({ id: "response_exact_panel", source:
    "response.cmd!=='snapshot'||response.panel!==expectedPanel" }),
  Object.freeze({ id: "response_call_id_equals_expected", source:
    "||!isIdentityText(response.callId,160)||response.callId!==expectedCallId"
      + "||!isIdentityText(response.panel,64)" }),
  Object.freeze({ id: "response_exact_instance", source:
    "if(expectedPanelInstanceId!=null&&response.panelInstanceId!==expectedPanelInstanceId)returnnull;" }),
  Object.freeze({ id: "request_returns_expected_call_id", source:
    "expectedCallId=request('snapshot',{v:1,requests:expectedRequests},function(response){" }),
  Object.freeze({ id: "physical_sync_duplicate_fence", source:
    "if(!returned){if(queued)queuedDuplicate=true;"
      + "else{queued=true;queuedResponse=response;}return;}handleResponse(response);" }),
  Object.freeze({ id: "request_exception_fail_closed", source:
    "}catch(_error){returned=true;if(ordinal===0)"
      + "reject('inventory_surface_request_contract_invalid',true);"
      + "elsereject('inventory_surface_request_contract_invalid');returnfalse;}" }),
  Object.freeze({ id: "invalid_request_return_fail_closed", source:
    "if(!isIdentityText(expectedCallId,160)||queuedDuplicate){if(ordinal===0)"
      + "reject('inventory_surface_request_contract_invalid',true);"
      + "elsereject('inventory_surface_request_contract_invalid');returnfalse;}" }),
  Object.freeze({ id: "queued_response_after_valid_return", source:
    "if(queued)handleResponse(queuedResponse);returntrue;" }),
  Object.freeze({ id: "owner_invalid_fail_closed", source:
    "if(!isIdentityText(expectedPanel,64)||(expectedPanelInstanceId!=null"
      + "&&!isIdentityText(expectedPanelInstanceId,128))){"
      + "reject('inventory_surface_owner_invalid',true);returnfalse;}" }),
  Object.freeze({ id: "provider_export", source:
    "readPhysicalInventorySurface:readPhysicalInventorySurface" }),
  Object.freeze({ id: "projection_constraint_classifier", source:
    "functionrequestNeedsAuthorityProjection(request){"
      + "returnnormalizeFilterKey(request&&request.filterKey)!=='all'"
      + "||!!request&&own(request,'filterSpec')"
      + "||normalizeProjectionScope(request&&request.scope)!=='all';}" }),
  Object.freeze({ id: "local_projection_rejects_constrained", source:
    "if(requestNeedsAuthorityProjection(request))returnnull;" }),
  Object.freeze({ id: "constrained_authority_followup", source:
    "if(requestsNeedAuthorityProjection(desiredRequests)){" }),
  Object.freeze({ id: "projection_exact_desired_request", source:
    "expectedCallId=self._request('snapshot',"
      + "{v:1,requests:cloneRequests(desiredRequests)},function(response){" }),
  Object.freeze({ id: "projection_exact_call_id", source:
    "if(!response||response.callId!==expectedCallId){" }),
  Object.freeze({ id: "projection_sync_duplicate_fence", source:
    "if(!returned){if(queued)queuedDuplicate=true;"
      + "else{queued=true;queuedResponse=response;}return;}"
      + "handleProjectionResponse(response);" }),
  Object.freeze({ id: "projection_exception_fence", source:
    "}catch(_projectionRequestError){returned=true;"
      + "failProjectionRequestContract();return;}" }),
  Object.freeze({ id: "projection_invalid_return_fence", source:
    "if(!isIdentityText(expectedCallId,160)||queuedDuplicate){"
      + "failProjectionRequestContract();return;}" }),
  Object.freeze({ id: "projection_failure_single_completion", source:
    "functionfailProjectionRequestContract(){"
      + "if(projectionDone||!self._isActiveOperation(operation))return;"
      + "projectionDone=true;finish(" }),
  Object.freeze({ id: "projection_response_single_completion", source:
    "functionhandleProjectionResponse(response){"
      + "if(projectionDone||!self._isActiveOperation(operation))return;"
      + "projectionDone=true;if(!response||response.callId!==expectedCallId){" }),
  Object.freeze({ id: "projection_response_v1", source:
    "||!Array.isArray(surface.windows)||!Array.isArray(surface.snapshots)"
      + "||!response||response.success!==true||response.v!==1"
      + "||!isIdentityText(response.sessionNonce,128)" }),
  Object.freeze({ id: "projection_same_session", source:
    "||response.sessionNonce!==surface.sessionNonce)returnfalse;" }),
  Object.freeze({ id: "projection_same_capacity", source:
    "snapshot.capacity!==full.capacity" }),
  Object.freeze({ id: "projection_same_accessibility", source:
    "snapshot.accessibleCapacity!==full.accessibleCapacity" }),
  Object.freeze({ id: "projection_same_page_size", source:
    "snapshot.pageSizeHint!==full.pageSizeHint" }),
  Object.freeze({ id: "projection_same_lock_state", source:
    "snapshot.locked!==full.locked" }),
  Object.freeze({ id: "projection_same_epoch", source:
    "snapshot.containerEpoch!==full.containerEpoch" }),
  Object.freeze({ id: "projection_same_version", source:
    "if(!full||snapshot.capacity!==full.capacity"
      + "||snapshot.accessibleCapacity!==full.accessibleCapacity"
      + "||snapshot.pageSizeHint!==full.pageSizeHint"
      + "||snapshot.locked!==full.locked"
      + "||snapshot.containerEpoch!==full.containerEpoch"
      + "||snapshot.containerVersion!==full.containerVersion"
      + "||snapshot.snapshotSeq<=maximumSurfaceSequence)returnfalse;",
    orderSource:"snapshot.containerVersion!==full.containerVersion" }),
  Object.freeze({ id: "projection_later_sequence", source:
    "snapshot.snapshotSeq<=maximumSurfaceSequence" }),
  Object.freeze({ id: "projection_same_filter_facets", source:
    "!sameProjectionValue(snapshot.filterFacets,full.filterFacets)" }),
  Object.freeze({ id: "projection_same_filter_count", source:
    "snapshot.filterItemCount!==full.filterItemCount" }),
  Object.freeze({ id: "projection_same_set_facets", source:
    "!sameProjectionValue(snapshot.setFacets,full.setFacets)" }),
  Object.freeze({ id: "projection_same_set_count", source:
    "snapshot.setFilterItemCount!==full.setFilterItemCount" }),
  Object.freeze({ id: "projection_exact_physical_slots", source:
    "!sameProjectionValue(visibleSlot,full.slots[physicalSlot])" }),
  Object.freeze({ id: "projection_retains_physical_receipt", source:
    "varvalid=authorityProjectionMatchesPhysicalSurface(response,result.surface,"
      + "desiredRequests,self._windows)"
      + "&&self._applySnapshots(response.snapshots,desiredRequests);"
      + "finish(valid?{success:true}:{success:false,"
      + "error:'inventory_surface_projection_invalid'},result.surface);" }),
]);
const INVENTORY_SURFACE_PROVIDER_FORBIDDEN_ANCHORS = Object.freeze([
  Object.freeze({ id: "legacy_owner_return_reject", source:
    "returnreject('inventory_surface_owner_invalid');" }),
  Object.freeze({ id: "boolean_request_return", source: "expectedCallId=true;" }),
  Object.freeze({ id: "object_request_return", source: "expectedCallId={" }),
  Object.freeze({ id: "constrained_projection_bypassed", source:
    "if(false){varreturned=false;varqueued=false;" }),
]);
const INVENTORY_SURFACE_CONSUMER_SCOPES = Object.freeze({
  npc_adapter_delegation: "file",
  npc_on_open_session_reset: "onOpen",
  npc_owner_open: "onOpen",
  npc_refresh_delegation: "refreshInventory",
  npc_receipt_projection: "file",
  npc_inventory_write_fence: "inventoryWriteUnavailable",
  npc_retry_surface: "buildDOM",
  npc_retry_listener: "buildDOM",
  npc_retry_status: "refreshControls",
  npc_open_settlement_write_fence: "openSettlement",
  npc_preview_write_fence: "requestTradePreview",
  npc_commit_write_fence: "commitTrade",
  npc_write_dispatch_fence: "write",
  npc_checkout_write_fence: "refreshControls",
});
const INVENTORY_SURFACE_ADAPTER_SCOPES = Object.freeze({
  adapter_definition: "constructor",
  adapter_exact_owner: "constructor",
  adapter_initial_windows: "constructor",
  adapter_refresh_open_only: "refresh",
  adapter_receipt_copy: "refresh",
  adapter_reset_definition: "resetSession",
  adapter_reset_closed_only: "resetSession",
  adapter_reset_reads_backpack: "resetSession",
  adapter_reset_reads_battlebox: "resetSession",
  adapter_reset_clears_receipt: "resetSession",
  adapter_reset_atomic_configure: "resetSession",
  adapter_cleanup: "close",
});
const INVENTORY_SURFACE_PROVIDER_SCOPES = Object.freeze({
  battle_access_set: "file",
  first_batch: "physicalSurfaceRequests",
  supplement_100: "physicalSurfaceRequests",
  supplement_200: "physicalSurfaceRequests",
  response_exact_panel: "readPhysicalInventorySurface",
  response_call_id_equals_expected: "readPhysicalInventorySurface",
  response_exact_instance: "readPhysicalInventorySurface",
  request_returns_expected_call_id: "readPhysicalInventorySurface",
  physical_sync_duplicate_fence: "readPhysicalInventorySurface",
  request_exception_fail_closed: "readPhysicalInventorySurface",
  invalid_request_return_fail_closed: "readPhysicalInventorySurface",
  queued_response_after_valid_return: "readPhysicalInventorySurface",
  owner_invalid_fail_closed: "readPhysicalInventorySurface",
  provider_export: "file",
  projection_constraint_classifier: "requestNeedsAuthorityProjection",
  local_projection_rejects_constrained: "projectPhysicalSurfaceToVisibleRequests",
  constrained_authority_followup: "refreshPhysicalSurface",
  projection_exact_desired_request: "refreshPhysicalSurface",
  projection_exact_call_id: "refreshPhysicalSurface",
  projection_sync_duplicate_fence: "refreshPhysicalSurface",
  projection_exception_fence: "refreshPhysicalSurface",
  projection_invalid_return_fence: "refreshPhysicalSurface",
  projection_failure_single_completion: "refreshPhysicalSurface",
  projection_response_single_completion: "refreshPhysicalSurface",
  projection_response_v1: "authorityProjectionMatchesPhysicalSurface",
  projection_same_session: "authorityProjectionMatchesPhysicalSurface",
  projection_same_capacity: "authorityProjectionMatchesPhysicalSurface",
  projection_same_accessibility: "authorityProjectionMatchesPhysicalSurface",
  projection_same_page_size: "authorityProjectionMatchesPhysicalSurface",
  projection_same_lock_state: "authorityProjectionMatchesPhysicalSurface",
  projection_same_epoch: "authorityProjectionMatchesPhysicalSurface",
  projection_same_version: "authorityProjectionMatchesPhysicalSurface",
  projection_later_sequence: "authorityProjectionMatchesPhysicalSurface",
  projection_same_filter_facets: "authorityProjectionMatchesPhysicalSurface",
  projection_same_filter_count: "authorityProjectionMatchesPhysicalSurface",
  projection_same_set_facets: "authorityProjectionMatchesPhysicalSurface",
  projection_same_set_count: "authorityProjectionMatchesPhysicalSurface",
  projection_exact_physical_slots: "authorityProjectionMatchesPhysicalSurface",
  projection_retains_physical_receipt: "refreshPhysicalSurface",
});
const INVENTORY_SURFACE_PROVIDER_FORBIDDEN_SCOPES = Object.freeze({
  legacy_owner_return_reject: "readPhysicalInventorySurface",
  boolean_request_return: "readPhysicalInventorySurface",
  object_request_return: "readPhysicalInventorySurface",
  constrained_projection_bypassed: "refreshPhysicalSurface",
});
const INVENTORY_SURFACE_REQUIRED_DEPTHS = Object.freeze({
  "consumer:npc_retry_listener": 1,
  "consumer:npc_open_settlement_write_fence": 1,
  "consumer:npc_preview_write_fence": 1,
  "consumer:npc_commit_write_fence": 1,
  "consumer:npc_write_dispatch_fence": 1,
  "consumer:npc_checkout_write_fence": 1,
  "adapter:adapter_reset_closed_only": 1,
  "provider:projection_same_version": 2,
});
const INVENTORY_SURFACE_ACTIVE_PREFIX_SHA256 = Object.freeze({
  "consumer:npc_retry_listener": "9d77c894a951f1af61760a1454baaefc9ae423b103ed7b5f60bc47587cdc2015",
  "consumer:npc_open_settlement_write_fence": "f1c36f231c26e23194227feeb4bd37ecb53022687dc4a8e1ee4916183d91cda5",
  "consumer:npc_preview_write_fence": "218e92858f0d888ffdc1241c5dc09d1287183d492d247e1885410a0787fc31be",
  "consumer:npc_commit_write_fence": "ec7d78ca12302679b949a4af7bc19ed3c8d2e0c5a8bae8172a01606e54ac2a30",
  "consumer:npc_write_dispatch_fence": "3b6ffec98a09bd48b174fa1242996663462ba9806765b280423717b6f4118bf8",
  "consumer:npc_checkout_write_fence": "fce99c73e3c3513b248899b18a15d389860d374ec31f8fd2c15efaddbf32bac5",
  "adapter:adapter_reset_closed_only": "462dbe3169b94457c015f1482b94e56cfdef4f4c270c2980d6cbd26341040b24",
  "provider:projection_same_version": "ba7e628b5d10ac37e2abd2ebcc067aeb0848de165914cca88301a64470244ea9",
});
// This is deliberately a closed governance pin, not a best-effort JavaScript
// rewrite detector. Any executable, inert, whitespace, string, comment, ASI,
// Unicode-escape, template, alias, destructuring, or reflection change to one
// of the three audited production sources requires an explicit review and pin
// refresh in the same current tree.
const INVENTORY_SURFACE_EXACT_SOURCE_SHA256 = Object.freeze({
  consumer: "aac86d778cd3773dc7b3fbe63d37d5464397e9b88ecb053d2c5f9e7537bdeec0",
  adapter: "2abc6d198607eb45185111ebf5269e946fb81dc5d0286a9ac0d465efdf9e9267",
  provider: "b2c6b06baadb3677d7434334cc06e2795d30a407c9499e5caec93df34c4a95dc",
});
const INVENTORY_SURFACE_ORDER_GROUPS = Object.freeze([
  Object.freeze({ id: "consumer_session_open", sourceName: "consumer", anchors: Object.freeze([
    "npc_on_open_session_reset", "npc_owner_open",
  ]) }),
  Object.freeze({ id: "adapter_session_reset", sourceName: "adapter", anchors: Object.freeze([
    "adapter_reset_definition", "adapter_reset_closed_only", "adapter_reset_reads_backpack",
    "adapter_reset_reads_battlebox", "adapter_reset_clears_receipt",
    "adapter_reset_atomic_configure",
  ]) }),
  Object.freeze({ id: "provider_physical_issue", sourceName: "provider", anchors: Object.freeze([
    "request_returns_expected_call_id", "physical_sync_duplicate_fence",
    "request_exception_fail_closed", "invalid_request_return_fail_closed",
    "queued_response_after_valid_return",
  ]) }),
  Object.freeze({ id: "provider_projection_coherence", sourceName: "provider", anchors: Object.freeze([
    "projection_same_session", "projection_same_capacity", "projection_same_accessibility",
    "projection_same_page_size", "projection_same_lock_state", "projection_same_epoch",
    "projection_same_version", "projection_later_sequence", "projection_same_filter_facets",
    "projection_same_filter_count", "projection_same_set_facets", "projection_same_set_count",
    "projection_exact_physical_slots",
  ]) }),
  Object.freeze({ id: "provider_projection_issue", sourceName: "provider", anchors: Object.freeze([
    "constrained_authority_followup", "projection_exact_desired_request",
    "projection_exception_fence", "projection_invalid_return_fence",
  ]) }),
]);
const EXPECTED_RUNTIME_DOMAIN_COUNTS = Object.freeze({
  artifactSource: 298,
  producerRecipe: 9,
  toolchainLock: 3,
});

const HOST_FILES = Object.freeze([
  "launcher/src/Tasks/NpcShopTask.cs",
  "launcher/src/Tasks/InventoryTask.cs",
  "launcher/src/Tasks/PanelBridge.cs",
  "launcher/src/Tasks/PanelPendingCallTracker.cs",
  "launcher/src/Guardian/AuthorityLogFormatter.cs",
  "launcher/src/Guardian/PanelHostController.cs",
  "launcher/src/Guardian/PanelRequestOwnerLifecycle.cs",
  "launcher/src/Guardian/WebOverlayForm.cs",
  "launcher/src/Guardian/LauncherCommandRouter.cs",
  "launcher/src/Guardian/LogManager.cs",
  "launcher/src/Bus/TaskRegistry.cs",
  "launcher/src/Bus/XmlSocketServer.cs",
  "launcher/src/Program.cs",
]);

const BUILD_FILES = Object.freeze([
  "launcher/CRAZYFLASHER7MercenaryEmpire.csproj",
  "config/build/runtime-inputs.v2.json",
  "tools/runtime-build-v2-common.ps1",
]);

const AS2_FILES = Object.freeze([
  "scripts/逻辑系统分区/商店系统_兼容.as",
  "scripts/逻辑系统分区/物品系统_WebView.as",
  "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
  "scripts/asLoaderManifest/frame10.as",
  "scripts/asLoaderManifest/_collapsed_frame.as",
]);

function listedChildren(root, listRelative, tagNames, baseRelative, role) {
  const listPath = path.resolve(root, listRelative.replace(/\//g, path.sep));
  let source;
  try { source = fs.readFileSync(listPath, "utf8"); }
  catch (_error) {
    fail("production_data_list_missing", "production_closure",
      "canonical data list is missing", { listRelative });
  }
  const tags = tagNames.join("|");
  const expression = new RegExp("<(?:" + tags + ")>([^<]+)</(?:" + tags + ")>", "g");
  const children = [];
  let match;
  while ((match = expression.exec(source)) !== null) {
    const name = match[1].trim().replace(/\\/g, "/");
    if (!name || name.startsWith("/") || name.includes("..") || /[:*?\"<>|]/.test(name)) {
      fail("production_data_list_invalid", "production_closure",
        "canonical data list contains an unsafe child", { listRelative, name });
    }
    children.push({ role, relativePath: baseRelative + "/" + name });
  }
  if (!children.length
      || new Set(children.map((entry) => entry.relativePath.toLowerCase())).size !== children.length) {
    fail("production_data_list_invalid", "production_closure",
      "canonical data list is empty or duplicated", { listRelative });
  }
  return [{ role: role + "_list", relativePath: listRelative }].concat(children);
}

function readExactText(root, relativePath) {
  const file = exactFile(root, { role: "declaration", relativePath });
  return { file, text: fs.readFileSync(path.resolve(root, relativePath), "utf8") };
}

function maskJsCommentsAndStrings(value) {
  const source = String(value || "");
  const output = source.split("");
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (current === "\r" || current === "\n") lineComment = false;
      else output[index] = " ";
      continue;
    }
    if (blockComment) {
      output[index] = current === "\r" || current === "\n" ? current : " ";
      if (current === "*" && next === "/") { output[index + 1] = " "; blockComment = false; index += 1; }
      continue;
    }
    if (quote) {
      output[index] = current === "\r" || current === "\n" ? current : " ";
      if (escaped) escaped = false;
      else if (current === "\\") escaped = true;
      else if (current === quote) quote = null;
      continue;
    }
    if (current === "/" && next === "/") {
      output[index] = output[index + 1] = " "; lineComment = true; index += 1; continue;
    }
    if (current === "/" && next === "*") {
      output[index] = output[index + 1] = " "; blockComment = true; index += 1; continue;
    }
    if (current === "'" || current === "\"" || current === "`") {
      output[index] = " "; quote = current;
    }
  }
  return output.join("");
}

function jsLexicalTokens(value) {
  const source = String(value || "");
  const tokens = [];
  function decodeString(raw) {
    let decoded = "";
    for (let index = 1; index < raw.length - 1; index += 1) {
      let current = raw[index];
      if (current !== "\\") { decoded += current; continue; }
      current = raw[++index];
      if (current === "x" && /^[0-9A-Fa-f]{2}$/.test(raw.slice(index + 1, index + 3))) {
        decoded += String.fromCharCode(parseInt(raw.slice(index + 1, index + 3), 16)); index += 2;
      } else if (current === "u" && /^[0-9A-Fa-f]{4}$/.test(raw.slice(index + 1, index + 5))) {
        decoded += String.fromCharCode(parseInt(raw.slice(index + 1, index + 5), 16)); index += 4;
      } else if (current === "n") decoded += "\n";
      else if (current === "r") decoded += "\r";
      else if (current === "t") decoded += "\t";
      else if (current === "b") decoded += "\b";
      else if (current === "f") decoded += "\f";
      else if (current === "v") decoded += "\v";
      else if (current === "\r" && raw[index + 1] === "\n") index += 1;
      else if (current !== "\r" && current !== "\n") decoded += current;
    }
    return decoded;
  }
  for (let index = 0; index < source.length;) {
    const current = source[index];
    const next = source[index + 1];
    if (/\s/.test(current)) { index += 1; continue; }
    if (current === "/" && next === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index += 1;
      continue;
    }
    if (current === "/" && next === "*") {
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) index += 1;
      if (index < source.length) index += 2;
      continue;
    }
    if (current === "'" || current === "\"" || current === "`") {
      const quote = current;
      const start = index++;
      let escaped = false;
      while (index < source.length) {
        const character = source[index++];
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === quote) break;
      }
      const raw = source.slice(start, index);
      tokens.push({ type: "string", value: decodeString(raw) });
      continue;
    }
    const identifier = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(source.slice(index));
    if (identifier) {
      tokens.push({ type: "identifier", value: identifier[0] });
      index += identifier[0].length;
      continue;
    }
    tokens.push({ type: "punctuator", value: current });
    index += 1;
  }
  return tokens;
}

function activeComputedPropertyNames(sourceValue) {
  const tokens = jsLexicalTokens(sourceValue);
  const names = new Set();
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].value !== "[") continue;
    let cursor = index + 1;
    let value = "";
    let expectString = true;
    while (cursor < tokens.length && tokens[cursor].value !== "]") {
      if (expectString && tokens[cursor].type === "string") {
        value += tokens[cursor].value; expectString = false;
      } else if (!expectString && tokens[cursor].value === "+") {
        expectString = true;
      } else {
        value = ""; break;
      }
      cursor += 1;
    }
    if (value && !expectString && cursor < tokens.length && tokens[cursor].value === "]") {
      names.add(value);
    }
  }
  return names;
}

function canonicalJsProjection(value) {
  const source = String(value || "").replace(/^\uFEFF/, "");
  let output = "";
  const depths = [];
  let braceDepth = 0;
  function append(text, depth) {
    output += text;
    for (let index = 0; index < text.length; index += 1) depths.push(depth);
  }
  for (let index = 0; index < source.length;) {
    const current = source[index];
    const next = source[index + 1];
    if (/\s/.test(current)) { index += 1; continue; }
    if (current === "/" && next === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index += 1;
      continue;
    }
    if (current === "/" && next === "*") {
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) index += 1;
      if (index < source.length) index += 2;
      continue;
    }
    if (current === "'" || current === "\"" || current === "`") {
      const quote = current;
      const start = index++;
      let escaped = false;
      while (index < source.length) {
        const character = source[index++];
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === quote) break;
      }
      append("@S" + sha256Text(source.slice(start, index)) + "@", braceDepth);
      continue;
    }
    if (current === "}") braceDepth -= 1;
    append(current, braceDepth);
    if (current === "{") braceDepth += 1;
    index += 1;
  }
  return { source: output, depths };
}

function canonicalJsSource(value) {
  return canonicalJsProjection(value).source;
}

function countExactOccurrences(source, needle) {
  let count = 0;
  let offset = 0;
  while ((offset = source.indexOf(needle, offset)) >= 0) {
    count += 1;
    offset += needle.length || 1;
  }
  return count;
}

function braceDepthAt(source, position) {
  let depth = 0;
  for (let index = 0; index < position; index += 1) {
    if (source[index] === "{") depth += 1;
    else if (source[index] === "}") depth -= 1;
  }
  return depth;
}

function callableSpan(sourceValue, marker, bindingContract) {
  const source = String(sourceValue || "");
  const masked = maskJsCommentsAndStrings(source);
  const expression = new RegExp(marker.source, marker.flags.includes("g") ? marker.flags : marker.flags + "g");
  const matches = Array.from(masked.matchAll(expression));
  if (matches.length !== 1) return { source: "", markerDepth: null,
    matchCount: matches.length, definitionComplete: false, bindingContract };
  const match = matches[0];
  const markerDepth = braceDepthAt(masked, match.index);
  const opening = masked.indexOf("{", match.index + match[0].length);
  if (opening < 0) return { source: "", markerDepth, matchCount: 1,
    definitionComplete: false, bindingContract };
  let depth = 0;
  for (let index = opening; index < masked.length; index += 1) {
    if (masked[index] === "{") depth += 1;
    else if (masked[index] === "}") {
      depth -= 1;
      if (depth === 0) {
        let end = index + 1;
        let definitionComplete = true;
        if (bindingContract && bindingContract.kind === "prototype_assignment") {
          while (end < masked.length && /\s/.test(masked[end])) end += 1;
          definitionComplete = masked[end] === ";";
          if (definitionComplete) end += 1;
        }
        return { source: source.slice(match.index, end), markerDepth, matchCount: 1,
          definitionComplete, bindingContract };
      }
    }
  }
  return { source: "", markerDepth, matchCount: 1,
    definitionComplete: false, bindingContract };
}

function bindingContract(kind, binding, prototypeRoot) {
  return Object.freeze({ kind, binding, prototypeRoot: prototypeRoot || null,
    id: binding.replace(/[^A-Za-z0-9_$]+/g, "_") });
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const BINDING_WRITE_OPERATOR =
  "(?:\\+\\+|--|&&=|\\|\\|=|\\?\\?=|\\*\\*=|>>>=|<<=|>>=|\\+=|-=|\\*=|/=|%=|&=|\\|=|\\^=|=(?!=|>))";

function countPattern(source, expression) {
  return Array.from(String(source || "").matchAll(expression)).length;
}

function prototypeRootHasUnsafeUse(masked, prototypeRoot) {
  let offset = 0;
  while ((offset = masked.indexOf(prototypeRoot, offset)) >= 0) {
    const before = masked[offset - 1];
    const afterIndex = offset + prototypeRoot.length;
    if ((before && /[A-Za-z0-9_$]/.test(before))
        || (masked[afterIndex] && /[A-Za-z0-9_$]/.test(masked[afterIndex]))) {
      offset = afterIndex;
      continue;
    }
    let cursor = afterIndex;
    while (cursor < masked.length && /\s/.test(masked[cursor])) cursor += 1;
    if (masked[cursor] !== ".") return true;
    cursor += 1;
    const property = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(masked.slice(cursor));
    if (!property) return true;
    cursor += property[0].length;
    while (cursor < masked.length && /\s/.test(masked[cursor])) cursor += 1;
    if (masked[cursor] !== "=" || masked[cursor + 1] === "=" || masked[cursor + 1] === ">") {
      return true;
    }
    cursor += 1;
    while (cursor < masked.length && /\s/.test(masked[cursor])) cursor += 1;
    if (!/^function\b/.test(masked.slice(cursor))) return true;
    offset = afterIndex;
  }
  return false;
}

function collectBindingViolations(sourceName, sourceValue, scopedBindings, forbidden) {
  const masked = maskJsCommentsAndStrings(sourceValue);
  const computedProperties = activeComputedPropertyNames(sourceValue);
  function add(value) {
    if (!forbidden.includes(value)) forbidden.push(value);
  }
  if (/\beval\b/.test(masked)) add(sourceName + ":dynamic_eval");
  if (/\bFunction\b/.test(masked)) add(sourceName + ":dynamic_function_constructor");
  if (/\.\s*constructor\s*(?:\.|\[|\()/.test(masked)
      || computedProperties.has("constructor") || computedProperties.has("Function")) {
    add(sourceName + ":dynamic_function_constructor");
  }
  if (computedProperties.has("eval")) add(sourceName + ":dynamic_eval");
  const seen = new Set();
  Object.keys(scopedBindings).forEach((scopeName) => {
    const scope = scopedBindings[scopeName];
    const contract = scope && typeof scope === "object" ? scope.bindingContract : null;
    if (!contract || seen.has(contract.binding)) return;
    seen.add(contract.binding);
    const label = sourceName + ":binding_rewrite_" + contract.id;
    const escapedBinding = escapeRegExp(contract.binding);
    if (scope.matchCount === 1 && scope.definitionComplete === false) {
      add(sourceName + ":binding_definition_incomplete_" + contract.id);
    }
    if (contract.kind === "declaration") {
      const directWrite = new RegExp("(?:^|[^A-Za-z0-9_$.[\\]])" + escapedBinding
        + "\\s*" + BINDING_WRITE_OPERATOR, "g");
      const prefixUpdate = new RegExp("(?:\\+\\+|--)\\s*" + escapedBinding
        + "(?![A-Za-z0-9_$])", "g");
      const destructuringWrite = new RegExp("(?:\\{[^{}]*\\b" + escapedBinding
        + "\\b[^{}]*\\}|\\[[^\\[\\]]*\\b" + escapedBinding
        + "\\b[^\\[\\]]*\\])\\s*=", "g");
      const iterationWrite = new RegExp("\\bfor\\s*\\(\\s*" + escapedBinding
        + "\\s+(?:of|in)\\b", "g");
      if (countPattern(masked, directWrite) > 0 || countPattern(masked, prefixUpdate) > 0
          || countPattern(masked, destructuringWrite) > 0
          || countPattern(masked, iterationWrite) > 0) add(label);
      return;
    }
    const directWrites = new RegExp("(?:^|[^A-Za-z0-9_$])" + escapedBinding
      + "\\s*" + BINDING_WRITE_OPERATOR, "g");
    const prefixUpdate = new RegExp("(?:\\+\\+|--)\\s*" + escapedBinding
      + "(?![A-Za-z0-9_$])", "g");
    const escapedRoot = escapeRegExp(contract.prototypeRoot);
    const constructorName = contract.prototypeRoot.slice(0, -".prototype".length);
    const bracketWrite = new RegExp(escapedRoot + "\\s*\\[[^\\]]*\\]\\s*"
      + BINDING_WRITE_OPERATOR, "g");
    const directDelete = new RegExp("\\bdelete\\s+(?:" + escapedBinding
      + "|" + escapedRoot + "\\s*\\[[^\\]]*\\])", "g");
    const prototypeReplacement = new RegExp("(?:^|[^A-Za-z0-9_$])" + escapedRoot
      + "\\s*" + BINDING_WRITE_OPERATOR, "g");
    const propertyMutation = new RegExp("\\b(?:Object\\.(?:assign|defineProperty|defineProperties)"
      + "|Reflect\\.(?:set|defineProperty))\\s*\\(\\s*" + escapedRoot + "(?:\\s*[,)]|\\s*$)", "g");
    const computedConstructorAccess = new RegExp("\\b" + escapeRegExp(constructorName)
      + "\\s*\\[", "g");
    const reflectedPrototypeAccess = new RegExp("\\bObject\\.getPrototypeOf\\s*\\(\\s*new\\s+"
      + escapeRegExp(constructorName) + "\\b", "g");
    const destructuredPrototypeAccess = new RegExp("\\{[^{}]*\\bprototype\\b[^{}]*\\}\\s*=\\s*"
      + escapeRegExp(constructorName) + "\\b", "g");
    if (countPattern(masked, directWrites) !== 1 || countPattern(masked, prefixUpdate) > 0
        || countPattern(masked, bracketWrite) > 0 || countPattern(masked, directDelete) > 0
        || countPattern(masked, prototypeReplacement) > 0
        || countPattern(masked, propertyMutation) > 0
        || countPattern(masked, computedConstructorAccess) > 0
        || countPattern(masked, reflectedPrototypeAccess) > 0
        || countPattern(masked, destructuredPrototypeAccess) > 0
        || /\b__proto__\b/.test(masked)
        || prototypeRootHasUnsafeUse(masked, contract.prototypeRoot)) add(label);
  });
}

function scopeSource(scope) {
  return scope && typeof scope === "object" ? scope.source : String(scope || "");
}

function inventorySourceScopes(consumerSource, adapterSource, providerSource) {
  return {
    consumer: {
      file: String(consumerSource || ""),
      createDOM: callableSpan(consumerSource, /function\s+createDOM\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "createDOM")),
      buildDOM: callableSpan(consumerSource, /function\s+buildDOM\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "buildDOM")),
      inventoryWriteUnavailable: callableSpan(consumerSource,
        /function\s+inventoryWriteUnavailable\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "inventoryWriteUnavailable")),
      openSettlement: callableSpan(consumerSource, /function\s+openSettlement\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "openSettlement")),
      requestTradePreview: callableSpan(consumerSource,
        /function\s+requestTradePreview\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "requestTradePreview")),
      commitTrade: callableSpan(consumerSource, /function\s+commitTrade\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "commitTrade")),
      onOpen: callableSpan(consumerSource, /function\s+onOpen\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "onOpen")),
      refreshInventory: callableSpan(consumerSource,
        /function\s+refreshInventory\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "refreshInventory")),
      write: callableSpan(consumerSource, /function\s+write\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "write")),
      refreshControls: callableSpan(consumerSource, /function\s+refreshControls\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "refreshControls")),
    },
    adapter: {
      constructor: callableSpan(adapterSource,
        /function\s+PhysicalInventoryAdapter\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "PhysicalInventoryAdapter")),
      refresh: callableSpan(adapterSource,
        /PhysicalInventoryAdapter\.prototype\.refresh\s*=\s*function\s*\([^)]*\)\s*/g,
        bindingContract("prototype_assignment", "PhysicalInventoryAdapter.prototype.refresh",
          "PhysicalInventoryAdapter.prototype")),
      resetSession: callableSpan(adapterSource,
        /PhysicalInventoryAdapter\.prototype\.resetSession\s*=\s*function\s*\([^)]*\)\s*/g,
        bindingContract("prototype_assignment", "PhysicalInventoryAdapter.prototype.resetSession",
          "PhysicalInventoryAdapter.prototype")),
      close: callableSpan(adapterSource,
        /PhysicalInventoryAdapter\.prototype\.close\s*=\s*function\s*\([^)]*\)\s*/g,
        bindingContract("prototype_assignment", "PhysicalInventoryAdapter.prototype.close",
          "PhysicalInventoryAdapter.prototype")),
    },
    provider: {
      file: String(providerSource || ""),
      physicalSurfaceRequests: callableSpan(providerSource,
        /function\s+physicalSurfaceRequests\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "physicalSurfaceRequests")),
      readPhysicalInventorySurface: callableSpan(providerSource,
        /function\s+readPhysicalInventorySurface\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "readPhysicalInventorySurface")),
      requestNeedsAuthorityProjection: callableSpan(providerSource,
        /function\s+requestNeedsAuthorityProjection\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "requestNeedsAuthorityProjection")),
      projectPhysicalSurfaceToVisibleRequests: callableSpan(providerSource,
        /function\s+projectPhysicalSurfaceToVisibleRequests\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "projectPhysicalSurfaceToVisibleRequests")),
      authorityProjectionMatchesPhysicalSurface: callableSpan(providerSource,
        /function\s+authorityProjectionMatchesPhysicalSurface\s*\([^)]*\)\s*/g,
        bindingContract("declaration", "authorityProjectionMatchesPhysicalSurface")),
      refreshPhysicalSurface: callableSpan(providerSource,
        /InventoryCoordinator\.prototype\._refreshPhysicalSurfaceWhileOwned\s*=\s*function\s*\([^)]*\)\s*/g,
        bindingContract("prototype_assignment",
          "InventoryCoordinator.prototype._refreshPhysicalSurfaceWhileOwned",
          "InventoryCoordinator.prototype")),
    },
  };
}

function inspectInventorySurfaceSourceContract(consumerSource, adapterSource, providerSource) {
  const scopes = inventorySourceScopes(consumerSource, adapterSource, providerSource);
  const missing = [];
  const misplaced = [];
  const activePrefixes = {};
  const positions = new Map();
  function addUnique(target, value) {
    if (!target.includes(value)) target.push(value);
  }
  const forbidden = [];
  const exactSourceSha256 = {
    consumer: sha256Text(String(consumerSource || "")),
    adapter: sha256Text(String(adapterSource || "")),
    provider: sha256Text(String(providerSource || "")),
  };
  Object.keys(INVENTORY_SURFACE_EXACT_SOURCE_SHA256).forEach((sourceName) => {
    if (exactSourceSha256[sourceName] !== INVENTORY_SURFACE_EXACT_SOURCE_SHA256[sourceName]) {
      forbidden.push(sourceName + ":closed_source_bytes_changed");
    }
  });
  collectBindingViolations("consumer", consumerSource, scopes.consumer, forbidden);
  collectBindingViolations("adapter", adapterSource, scopes.adapter, forbidden);
  collectBindingViolations("provider", providerSource, scopes.provider, forbidden);
  const bindingGuards = [];
  Object.keys(scopes).forEach((sourceName) => {
    const seen = new Set();
    Object.keys(scopes[sourceName]).forEach((scopeName) => {
      const scope = scopes[sourceName][scopeName];
      const contract = scope && typeof scope === "object" ? scope.bindingContract : null;
      if (!contract || seen.has(contract.binding)) return;
      seen.add(contract.binding);
      bindingGuards.push({ id: sourceName + ":" + contract.id,
        kind: contract.kind, binding: contract.binding,
        definition: contract.kind === "prototype_assignment"
          ? "single_complete_assignment_with_semicolon" : "single_complete_declaration",
        rewrite: "forbidden_file_wide" });
    });
  });
  bindingGuards.sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
  function inspectRequired(sourceName, anchors, scopeNames) {
    anchors.forEach((anchor) => {
      const label = sourceName + ":" + anchor.id;
      const scope = scopes[sourceName][scopeNames[anchor.id]];
      const projection = canonicalJsProjection(scopeSource(scope));
      const compact = projection.source;
      const needle = canonicalJsSource(anchor.source);
      const count = countExactOccurrences(compact, needle);
      const position = count === 1 ? compact.indexOf(needle) : -1;
      const orderNeedle = canonicalJsSource(anchor.orderSource || anchor.source);
      const orderPosition = count === 1 ? compact.indexOf(orderNeedle, position) : -1;
      const expectedDepth = INVENTORY_SURFACE_REQUIRED_DEPTHS[label];
      const callableDepthValid = !scope || typeof scope !== "object" || scope.markerDepth === 1;
      const anchorDepthValid = expectedDepth == null || position < 0
        || projection.depths[position] === expectedDepth;
      let activePrefixValid = true;
      if (count === 1 && Object.prototype.hasOwnProperty.call(
        INVENTORY_SURFACE_ACTIVE_PREFIX_SHA256, label)) {
        const actual = sha256Text(compact.slice(0, position + needle.length));
        activePrefixes[label] = actual;
        activePrefixValid = actual === INVENTORY_SURFACE_ACTIVE_PREFIX_SHA256[label];
      }
      const definitionComplete = !scope || typeof scope !== "object"
        || scope.definitionComplete !== false;
      const structuralValid = callableDepthValid && anchorDepthValid
        && activePrefixValid && definitionComplete;
      positions.set(label, count === 1 && structuralValid ? orderPosition : -1);
      if (count !== 1) addUnique(missing, label);
      else if (!structuralValid) addUnique(misplaced, label);
    });
  }
  inspectRequired("consumer", INVENTORY_SURFACE_CONSUMER_ANCHORS,
    INVENTORY_SURFACE_CONSUMER_SCOPES);
  inspectRequired("adapter", INVENTORY_SURFACE_ADAPTER_ANCHORS,
    INVENTORY_SURFACE_ADAPTER_SCOPES);
  inspectRequired("provider", INVENTORY_SURFACE_PROVIDER_ANCHORS,
    INVENTORY_SURFACE_PROVIDER_SCOPES);
  INVENTORY_SURFACE_PROVIDER_FORBIDDEN_ANCHORS.forEach((anchor) => {
    const compact = canonicalJsSource(scopeSource(scopes.provider[
      INVENTORY_SURFACE_PROVIDER_FORBIDDEN_SCOPES[anchor.id]]));
    if (countExactOccurrences(compact, canonicalJsSource(anchor.source)) > 0) {
      forbidden.push("provider:" + anchor.id);
    }
  });
  INVENTORY_SURFACE_ADAPTER_FORBIDDEN_ANCHORS.forEach((anchor) => {
    const compact = canonicalJsSource(scopeSource(scopes.adapter[anchor.method]));
    if (countExactOccurrences(compact, canonicalJsSource(anchor.source)) > 0) {
      forbidden.push("adapter:" + anchor.id);
    }
  });
  const outOfOrder = [];
  INVENTORY_SURFACE_ORDER_GROUPS.forEach((group) => {
    let previous = -1;
    group.anchors.forEach((id) => {
      const position = positions.get(group.sourceName + ":" + id);
      if (position == null || position < 0) return;
      if (position <= previous) outOfOrder.push(group.id + ":" + id);
      previous = position;
    });
  });
  return {
    schema: INVENTORY_SURFACE_SOURCE_SCHEMA,
    tokenCanonicalization:
      "exact-source-byte-pin-plus-js-binding-depth-active-prefix-rewrite-fence.v5",
    valid: missing.length === 0 && misplaced.length === 0
      && forbidden.length === 0 && outOfOrder.length === 0,
    missing,
    misplaced,
    activePrefixes,
    bindingGuards,
    closedSourceBytes: { policy: "exact_utf8_bytes_governance_pin",
      expected: INVENTORY_SURFACE_EXACT_SOURCE_SHA256, actual: exactSourceSha256 },
    dynamicCode: { eval: "forbidden_file_wide", Function: "forbidden_file_wide" },
    forbidden,
    outOfOrder,
  };
}

function inventorySurfaceContract(root) {
  const consumerPath = "launcher/web/modules/npcshop.js";
  const adapterPath = "launcher/web/modules/npcshop-runtime.js";
  const providerPath = "launcher/web/modules/inventory-runtime.js";
  const consumer = readExactText(root, consumerPath);
  const adapter = readExactText(root, adapterPath);
  const provider = readExactText(root, providerPath);
  const sourceContract = inspectInventorySurfaceSourceContract(
    consumer.text, adapter.text, provider.text);
  if (!sourceContract.valid) {
    fail("production_inventory_surface_contract_missing", "production_closure",
      "NPC production Web must consume the canonical complete physical Inventory surface reader",
      { missing: sourceContract.missing, misplaced: sourceContract.misplaced,
        forbidden: sourceContract.forbidden,
        outOfOrder: sourceContract.outOfOrder });
  }
  return {
    schema: INVENTORY_SURFACE_CONTRACT_SCHEMA,
    consumer: { locator: "root:" + consumerPath, sha256: consumer.file.sha256 },
    adapter: { locator: "root:" + adapterPath, sha256: adapter.file.sha256 },
    provider: { locator: "root:" + providerPath, sha256: provider.file.sha256 },
    owner: { expectedPanel: "npcshop", expectedPanelInstanceId: "current_exact_owner",
      supplements: "same_exact_owner" },
    requestCallId: { requestReturn: "bounded_expected_call_id",
      synchronousCallback: "single_callback_queued_until_request_return",
      responseEcho: "exact_expected_call_id", invalidReturn: "fail_closed_once" },
    sessionReset: { order: "before_owner_open", availability: "closed_only",
      mutation: "single_atomic_configure", offsets: "preserved",
      limits: { backpack: 50, battlebox: 40 },
      projection: "filterKey_all_without_filterSpec_or_scope",
      refresh: "open_current_requests_without_reconfiguration" },
    projection: { constrainedRequests: "physical_then_exact_authority_visible",
      ownerRelease: "after_exact_visible_response",
      visibleRequestState: "preserved",
      pairedCoherence: ["responseV1", "session", "capacity", "accessibleCapacity", "pageSizeHint",
        "locked", "containerEpoch", "containerVersion", "laterSnapshotSeq",
        "filterFacets", "filterItemCount", "setFacets", "setFilterItemCount",
        "exactPhysicalSlot"],
      failureFence: ["callId", "singleCompletion", "synchronousDuplicate",
        "exception", "invalidReturn"],
      receipt: "one_to_three_batch_physical_surface" },
    sourceContract: { schema: sourceContract.schema,
      tokenCanonicalization: sourceContract.tokenCanonicalization,
      bindingGuards: sourceContract.bindingGuards,
      closedSourceBytes: sourceContract.closedSourceBytes,
      dynamicCode: sourceContract.dynamicCode,
      structuralAnchors: Object.keys(INVENTORY_SURFACE_REQUIRED_DEPTHS).sort().map((id) => ({
        id, callableBraceDepth: 1, anchorBraceDepth: INVENTORY_SURFACE_REQUIRED_DEPTHS[id],
        activePrefixSha256: INVENTORY_SURFACE_ACTIVE_PREFIX_SHA256[id],
      })),
      requiredAnchors: INVENTORY_SURFACE_CONSUMER_ANCHORS.map((anchor) => "consumer:" + anchor.id)
        .concat(INVENTORY_SURFACE_ADAPTER_ANCHORS.map((anchor) => "adapter:" + anchor.id))
        .concat(INVENTORY_SURFACE_PROVIDER_ANCHORS.map((anchor) => "provider:" + anchor.id)),
      forbiddenAnchors: INVENTORY_SURFACE_PROVIDER_FORBIDDEN_ANCHORS
        .map((anchor) => "provider:" + anchor.id)
        .concat(INVENTORY_SURFACE_ADAPTER_FORBIDDEN_ANCHORS
          .map((anchor) => "adapter:" + anchor.id)),
      orderedAnchors: INVENTORY_SURFACE_ORDER_GROUPS.map((group) => ({
        id: group.id,
        anchors: group.anchors.map((id) => group.sourceName + ":" + id),
      })) },
    firstBatch: [
      { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
      { containerId: "战备箱", offset: 0, limit: 100, filterKey: "all" },
    ],
    battleAccessibleCapacities: [0, 40, 80, 120, 160, 200, 240],
    supplements: [
      { when: "A>100", containerId: "战备箱", offset: 100, limit: 100 },
      { when: "A>200", containerId: "战备箱", offset: 200, limit: "A-200" },
    ],
    authorityVisibleFollowup: { when: "filterKey_not_all_or_filterSpec_present_or_scope_not_all",
      request: "exact_current_visible_requests", responseCount: 1 },
  };
}

function declaredWebDependencies(root) {
  const overlay = readExactText(root, "launcher/web/overlay.html").text;
  const bootSources = Array.from(overlay.matchAll(
    /<script\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"][^>]*>/gi)).map((match) => match[1]);
  if (!bootSources.length || new Set(bootSources).size !== bootSources.length
      || bootSources.some((source) => !/^(?:modules|lib)\/[A-Za-z0-9._/-]+\.js$/.test(source)
        || source.includes("..") || source.startsWith("/"))) {
    fail("production_overlay_boot_invalid", "production_closure",
      "Overlay startup script inventory is empty, duplicated, or outside the local JS contract", {
        bootSources,
      });
  }
  const bootWeb = bootSources.map((source) => "launcher/web/" + source);
  const registryRelative = "launcher/web/modules/panels-lazy-registry.js";
  if (bootWeb.filter((entry) => entry === registryRelative).length !== 1) {
    fail("production_overlay_boot_invalid", "production_closure",
      "Overlay startup closure must load the lazy registry exactly once");
  }

  const registry = readExactText(root, registryRelative).text;
  const registrations = Array.from(registry.matchAll(
    /Panels\.registerLazy\(\s*['"]npcshop['"]\s*,\s*\[([\s\S]*?)\]\s*,\s*noop\s*\)/g));
  if (registrations.length !== 1) {
    fail("production_npc_registry_invalid", "production_closure",
      "lazy registry must contain one exact NPC Shop declaration");
  }
  const declared = Array.from(registrations[0][1].matchAll(/['"]([^'"]+)['"]/g))
    .map((match) => match[1]);
  if (!declared.length || new Set(declared).size !== declared.length
      || declared.some((source) => !/^modules\/[A-Za-z0-9._/-]+\.js$/.test(source)
        || source.includes(".."))) {
    fail("production_npc_registry_invalid", "production_closure",
      "NPC Shop lazy dependency list is empty, duplicated, or unsafe", { declared });
  }
  const npcLazyWeb = declared.map((source) => "launcher/web/" + source);

  const styleSources = Array.from(overlay.matchAll(
    /<link\b(?=[^>]*\brel\s*=\s*['"]stylesheet['"])[^>]*\bhref\s*=\s*['"]([^'"]+)['"][^>]*>/gi))
    .map((match) => match[1]);
  if (!styleSources.length || new Set(styleSources).size !== styleSources.length
      || styleSources.some((source) => !/^[A-Za-z0-9._/-]+\.css$/.test(source)
        || source.includes("..") || source.startsWith("/"))) {
    fail("production_overlay_stylesheet_invalid", "production_closure",
      "Overlay stylesheet inventory is empty, duplicated, or outside the local CSS contract", {
        styleSources,
      });
  }
  const styleWeb = [];
  const styleRoles = Object.create(null);
  function visitStyle(relative, role, ancestry) {
    const normalized = path.posix.normalize(relative.replace(/\\/g, "/"));
    if (!/^launcher\/web\/[A-Za-z0-9._/-]+\.css$/.test(normalized)
        || normalized.includes("..") || ancestry.includes(normalized)) {
      fail("production_stylesheet_import_invalid", "production_closure",
        "Overlay stylesheet import graph is unsafe or cyclic", { relative, ancestry });
    }
    if (styleRoles[normalized]) {
      if (styleRoles[normalized] !== role && role === "overlay_boot_stylesheet") {
        styleRoles[normalized] = role;
      }
      return;
    }
    styleRoles[normalized] = role;
    styleWeb.push(normalized);
    const css = readExactText(root, normalized).text;
    const imports = Array.from(css.matchAll(
      /@import\s+(?:url\(\s*)?['"]?([^'"\s);]+\.css)['"]?\s*\)?[^;]*;/gi))
      .map((match) => match[1]);
    imports.forEach((source) => {
      if (/^(?:[a-z]+:|\/|\\)/i.test(source)) {
        fail("production_stylesheet_import_invalid", "production_closure",
          "Overlay stylesheet import must stay local", { source, normalized });
      }
      visitStyle(path.posix.join(path.posix.dirname(normalized), source),
        "overlay_import_stylesheet", ancestry.concat(normalized));
    });
  }
  styleSources.forEach((source) => visitStyle("launcher/web/" + source,
    "overlay_boot_stylesheet", []));
  return { bootWeb, npcLazyWeb, styleWeb,
    styleRoles: styleWeb.map((relativePath) => ({ relativePath, role: styleRoles[relativePath] })) };
}

function productionFiles(root) {
  const declarations = declaredWebDependencies(root);
  const bootSet = new Set(declarations.bootWeb);
  const web = declarations.bootWeb.map((relativePath) => ({
    role: relativePath === "launcher/web/modules/panels-lazy-registry.js"
      ? "lazy_registry" : "overlay_boot_web",
    relativePath,
  })).concat(declarations.npcLazyWeb.filter((entry) => !bootSet.has(entry))
    .map((relativePath) => ({ role: "npc_lazy_web", relativePath })));
  const styles = declarations.styleRoles.map((entry) => ({
    role: entry.role, relativePath: entry.relativePath,
  }));
  const all = [
    { role: "page", relativePath: "launcher/web/overlay.html" },
    ...web,
    ...styles,
    ...HOST_FILES.map((relativePath) => ({ role: "host_source", relativePath })),
    ...BUILD_FILES.map((relativePath) => ({ role: "build_source", relativePath })),
    ...AS2_FILES.map((relativePath) => ({ role: "as2_source", relativePath })),
    { role: "as2_swf", relativePath: "scripts/asLoader.swf" },
    ...listedChildren(root, "data/shops/list.xml", ["shops"], "data/shops", "shop_data"),
    ...listedChildren(root, "data/items/list.xml", ["items", "itemSets"], "data/items", "item_data"),
  ];
  if (new Set(all.map((entry) => entry.relativePath.toLowerCase())).size !== all.length) {
    fail("production_closure_inventory_invalid", "production_closure",
      "NPC production closure contains duplicate paths");
  }
  return all;
}

function exactFile(root, descriptor) {
  const canonicalRoot = path.resolve(root);
  const filePath = path.resolve(canonicalRoot, descriptor.relativePath.replace(/\//g, path.sep));
  const relative = path.relative(canonicalRoot, filePath);
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("production_closure_file_missing", "production_closure",
      "required NPC production file is missing", descriptor);
  }
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)
      || !stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()) {
    fail("production_closure_file_invalid", "production_closure",
      "required NPC production path is not one exact regular file", descriptor);
  }
  const bytes = fs.readFileSync(filePath);
  return { role: descriptor.role,
    locator: "root:" + descriptor.relativePath.replace(/\\/g, "/"),
    sha256: sha256Bytes(bytes), bytes: bytes.length };
}

function treeDigest(files) {
  return sha256Text(canonicalJson(files));
}

function enumerateArtifactSourceFiles(root) {
  const configPath = path.resolve(root, "config", "build", "runtime-inputs.v2.json");
  let config;
  try { config = JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime artifact-source config is not valid JSON");
  }
  if (!config || config.schema !== "cf7-runtime-inputs.v2"
      || !config.domains || !config.domains.artifactSource) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime artifact-source config is missing or unsupported");
  }
  const domain = config.domains.artifactSource;
  const values = new Set((domain.fixedFiles || []).map((value) => String(value).replace(/\\/g, "/")));
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const full = path.join(directory, entry.name);
      const relative = (base ? base + "/" : "") + entry.name;
      if (entry.isDirectory()) { walk(full, relative, tree); return; }
      if (!entry.isFile() || entry.isSymbolicLink()) return;
      const normalized = String(tree.path).replace(/\\/g, "/").replace(/\/$/, "") + "/" + relative;
      const extensions = (tree.includeExtensions || []).map((value) => String(value).toLowerCase());
      if (extensions.length && !extensions.includes(path.extname(normalized).toLowerCase())) return;
      const excludes = (tree.excludePaths || []).map((value) => String(value).replace(/\\/g, "/"));
      const prefixes = (tree.excludePrefixes || []).map((value) => String(value).replace(/\\/g, "/"));
      if (excludes.includes(normalized) || prefixes.some((prefix) => normalized.startsWith(prefix))) return;
      values.add(normalized);
    });
  }
  (domain.trees || []).forEach((tree) => {
    const base = path.resolve(root, String(tree.path).replace(/\//g, path.sep));
    let stat;
    try { stat = fs.statSync(base); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory()) {
      fail("runtime_input_tree_invalid", "production_closure",
        "runtime artifact-source tree is missing", { path: tree.path });
    }
    walk(base, "", tree);
  });
  return Array.from(values).sort();
}

function enumerateRuntimeDomainFiles(root, domainName) {
  const configPath = path.resolve(root, "config", "build", "runtime-inputs.v2.json");
  let config;
  try { config = JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime input config is not valid JSON");
  }
  const domain = config && config.schema === "cf7-runtime-inputs.v2"
    && config.domains && config.domains[domainName];
  if (!domain || !Object.prototype.hasOwnProperty.call(EXPECTED_RUNTIME_DOMAIN_COUNTS, domainName)) {
    fail("runtime_input_domain_invalid", "production_closure",
      "required runtime input domain is missing", { domain: domainName });
  }
  const values = new Set((domain.fixedFiles || []).map((value) =>
    String(value).replace(/\\/g, "/")));
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const full = path.join(directory, entry.name);
      const relative = (base ? base + "/" : "") + entry.name;
      if (entry.isDirectory()) { walk(full, relative, tree); return; }
      if (!entry.isFile() || entry.isSymbolicLink()) return;
      const normalized = String(tree.path).replace(/\\/g, "/").replace(/\/$/, "") + "/" + relative;
      const extensions = (tree.includeExtensions || []).map((value) => String(value).toLowerCase());
      if (extensions.length && !extensions.includes(path.extname(normalized).toLowerCase())) return;
      const excludes = (tree.excludePaths || []).map((value) => String(value).replace(/\\/g, "/"));
      const prefixes = (tree.excludePrefixes || []).map((value) => String(value).replace(/\\/g, "/"));
      if (excludes.includes(normalized) || prefixes.some((prefix) => normalized.startsWith(prefix))) return;
      values.add(normalized);
    });
  }
  (domain.trees || []).forEach((tree) => {
    const base = path.resolve(root, String(tree.path).replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(base); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("runtime_input_tree_invalid", "production_closure",
        "runtime input tree is missing or not a plain directory", { domain: domainName, path: tree.path });
    }
    walk(base, "", tree);
  });
  const files = Array.from(values).sort();
  if (files.length !== EXPECTED_RUNTIME_DOMAIN_COUNTS[domainName]) {
    fail("runtime_input_domain_count_invalid", "production_closure",
      "runtime input domain count differs from the frozen NPC A3 baseline", {
        domain: domainName,
        expected: EXPECTED_RUNTIME_DOMAIN_COUNTS[domainName],
        actual: files.length,
      });
  }
  files.forEach((relativePath) => exactFile(root, { role: "runtime_" + domainName, relativePath }));
  return files;
}

function currentRuntimeInputIdentity(root) {
  const resolvedRoot = path.resolve(root);
  const domains = ["artifactSource", "producerRecipe", "toolchainLock"];
  const files = Object.create(null);
  const fingerprintRows = [];
  domains.forEach((domain) => {
    files[domain] = enumerateRuntimeDomainFiles(resolvedRoot, domain);
    files[domain].forEach((relativePath) => {
      const value = exactFile(resolvedRoot, { role: "runtime_" + domain, relativePath });
      fingerprintRows.push({ domain, relativePath, sha256: value.sha256, bytes: value.bytes });
    });
  });
  const fingerprint = sha256Text(canonicalJson(fingerprintRows));
  const cacheKey = resolvedRoot.toLowerCase();
  const cached = runtimeInputCache.get(cacheKey);
  if (cached && cached.fingerprint === fingerprint) return cached.value;
  const script = ". (Join-Path $env:CF7_NPC_SOURCE_ROOT 'tools/runtime-build-v2-common.ps1'); "
    + "$a=Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $env:CF7_NPC_SOURCE_ROOT -Mode Worktree; "
    + "$p=Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $env:CF7_NPC_SOURCE_ROOT -Mode Worktree; "
    + "$t=Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $env:CF7_NPC_SOURCE_ROOT -Mode Worktree; "
    + "$b=Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $a -ProducerRecipeHash $p -ToolchainLockHash $t; "
    + "[pscustomobject][ordered]@{artifactSourceHash=$a;producerRecipeHash=$p;toolchainLockHash=$t;buildIdentityHash=$b}|ConvertTo-Json -Compress";
  const result = childProcess.spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass",
    "-Command", script], { cwd: resolvedRoot, encoding: "utf8", windowsHide: true,
    maxBuffer: 4 * 1024 * 1024,
    env: Object.assign({}, process.env, { CF7_NPC_SOURCE_ROOT: resolvedRoot }) });
  let canonical;
  try { canonical = JSON.parse(String(result.stdout || "").trim()); } catch (_error) { canonical = null; }
  if (result.status !== 0 || !canonical
      || ![canonical.artifactSourceHash, canonical.producerRecipeHash,
        canonical.toolchainLockHash, canonical.buildIdentityHash]
        .every((value) => SHA256_RE.test(String(value || "").toUpperCase()))) {
    fail("runtime_input_identity_failed", "production_closure",
      "canonical runtime input identity could not be recomputed", {
        status: result.status, stderr: String(result.stderr || "").slice(0, 400),
      });
  }
  const value = {
    schema: RUNTIME_INPUTS_SCHEMA,
    domains: {
      artifactSource: { fileCount: files.artifactSource.length,
        sha256: String(canonical.artifactSourceHash).toUpperCase() },
      producerRecipe: { fileCount: files.producerRecipe.length,
        sha256: String(canonical.producerRecipeHash).toUpperCase() },
      toolchainLock: { fileCount: files.toolchainLock.length,
        sha256: String(canonical.toolchainLockHash).toUpperCase() },
    },
    buildIdentityHash: String(canonical.buildIdentityHash).toUpperCase(),
  };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  runtimeInputCache.set(cacheKey, { fingerprint, value });
  return value;
}

function currentArtifactSourceIdentity(root) {
  const resolvedRoot = path.resolve(root);
  const files = enumerateArtifactSourceFiles(resolvedRoot);
  const rows = files.map((relativePath) => {
    const value = exactFile(resolvedRoot, { role: "artifact_source", relativePath });
    return { relativePath, sha256: value.sha256, bytes: value.bytes };
  });
  const fingerprint = sha256Text(canonicalJson(rows));
  const cached = artifactSourceCache.get(resolvedRoot.toLowerCase());
  if (cached && cached.fingerprint === fingerprint) return cached;
  const script = ". (Join-Path $env:CF7_NPC_SOURCE_ROOT 'tools/runtime-build-v2-common.ps1'); "
    + "Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $env:CF7_NPC_SOURCE_ROOT -Mode Worktree";
  const result = childProcess.spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass",
    "-Command", script], { cwd: resolvedRoot, encoding: "utf8", windowsHide: true,
    maxBuffer: 4 * 1024 * 1024,
    env: Object.assign({}, process.env, { CF7_NPC_SOURCE_ROOT: resolvedRoot }) });
  const artifactSourceHash = String(result.stdout || "").trim().toUpperCase();
  if (result.status !== 0 || !SHA256_RE.test(artifactSourceHash)) {
    fail("runtime_artifact_source_hash_failed", "production_closure",
      "canonical runtime artifact-source hash could not be recomputed", {
        status: result.status, stderr: String(result.stderr || "").slice(0, 400),
      });
  }
  const value = { fingerprint, artifactSourceHash, fileCount: files.length };
  artifactSourceCache.set(resolvedRoot.toLowerCase(), value);
  return value;
}

function captureProductionClosure(root, capturedAt) {
  const declarations = declaredWebDependencies(root);
  const files = productionFiles(root).map((entry) => exactFile(root, entry));
  const runtimeInputs = currentRuntimeInputIdentity(root);
  const semanticContracts = { inventoryPhysicalSurface: inventorySurfaceContract(root) };
  const value = { schema: CLOSURE_SCHEMA,
    capturedAt: capturedAt || new Date().toISOString(), root: path.resolve(root),
    files, declarations, semanticContracts,
    artifactSource: currentArtifactSourceIdentity(root), runtimeInputs,
    treeSha256: treeDigest(files) };
  value.closureSha256 = sha256Text(canonicalJson(value));
  return value;
}

function verifyProductionClosure(root, closure, options) {
  const descriptors = productionFiles(root);
  if (!isPlainObject(closure) || closure.schema !== CLOSURE_SCHEMA
      || path.resolve(closure.root || "").toLowerCase() !== path.resolve(root).toLowerCase()
      || !Number.isFinite(Date.parse(closure.capturedAt))
      || !Array.isArray(closure.files) || closure.files.length !== descriptors.length
      || closure.treeSha256 !== treeDigest(closure.files)
      || canonicalJson(closure.declarations) !== canonicalJson(declaredWebDependencies(root))
      || canonicalJson(closure.semanticContracts)
        !== canonicalJson({ inventoryPhysicalSurface: inventorySurfaceContract(root) })
      || canonicalJson(closure.artifactSource) !== canonicalJson(currentArtifactSourceIdentity(root))
      || canonicalJson(closure.runtimeInputs) !== canonicalJson(currentRuntimeInputIdentity(root))
      || closure.artifactSource.artifactSourceHash !== closure.runtimeInputs.domains.artifactSource.sha256
      || closure.artifactSource.fileCount !== closure.runtimeInputs.domains.artifactSource.fileCount) {
    fail("production_closure_invalid", "production_closure",
      "NPC production closure envelope, declarations, or artifact source is incomplete");
  }
  const unsigned = Object.assign({}, closure);
  delete unsigned.closureSha256;
  if (closure.closureSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("production_closure_digest_invalid", "production_closure",
      "NPC production closure digest is detached");
  }
  if (!options || options.currentTree !== false) {
    const current = descriptors.map((entry) => exactFile(root, entry));
    if (canonicalJson(current) !== canonicalJson(closure.files)) {
      fail("production_closure_current_tree_mismatch", "production_closure",
        "captured NPC production bytes differ from the current canonical tree");
    }
  }
  return closure;
}

function sameProductionTree(before, after) {
  if (!isPlainObject(before) || !isPlainObject(after)
      || before.root.toLowerCase() !== after.root.toLowerCase()
      || before.treeSha256 !== after.treeSha256
      || canonicalJson(before.files) !== canonicalJson(after.files)
      || canonicalJson(before.declarations) !== canonicalJson(after.declarations)
      || canonicalJson(before.semanticContracts) !== canonicalJson(after.semanticContracts)
      || canonicalJson(before.artifactSource) !== canonicalJson(after.artifactSource)
      || canonicalJson(before.runtimeInputs) !== canonicalJson(after.runtimeInputs)) {
    fail("production_closure_restart_drift", "production_closure",
      "NPC production source/artifact/data tree changed between captures");
  }
  return true;
}

function publicCandidateIdentity(identity) {
  return { runtimeMode: identity.runtimeMode, processPath: path.resolve(identity.processPath || ""),
    coreSha256: identity.coreSha256, buildIdentity: identity.buildIdentity,
    payloadClosure: identity.payloadClosure };
}

function exactCandidateFile(candidateRoot, relativePath, maximumBytes) {
  const resolvedRoot = path.resolve(candidateRoot);
  const filePath = path.resolve(resolvedRoot, relativePath.replace(/\//g, path.sep));
  const relative = path.relative(resolvedRoot, filePath);
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("candidate_producer_file_missing", "production_closure",
      "candidate producer evidence file is missing", { relativePath });
  }
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)
      || !stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size < 1 || stat.size > maximumBytes) {
    fail("candidate_producer_file_invalid", "production_closure",
      "candidate producer evidence is not one bounded exact regular file", { relativePath });
  }
  const bytes = fs.readFileSync(filePath);
  return { filePath, bytes, sha256: sha256Bytes(bytes), size: bytes.length };
}

function safeCandidateRelative(relativePath) {
  const normalized = String(relativePath || "").replace(/\\/g, "/");
  if (!normalized || normalized.startsWith("/") || /(^|\/)\.\.?(\/|$)/.test(normalized)
      || /[\t\r\n:*?"<>|]/.test(normalized)) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload path is not one canonical relative path", { relativePath });
  }
  return normalized;
}

function candidatePayloadContract(root) {
  let config;
  try {
    config = JSON.parse(fs.readFileSync(path.resolve(root,
      "config", "build", "runtime-inputs.v2.json"), "utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime input config cannot define the candidate payload", { message: error.message });
  }
  const payload = config && config.schema === "cf7-runtime-inputs.v2" && config.payload;
  if (!payload || !Array.isArray(payload.fixedRoots) || !Array.isArray(payload.trees)
      || !Array.isArray(payload.excludePaths) || !Array.isArray(payload.excludePrefixes)) {
    fail("runtime_payload_config_invalid", "production_closure",
      "candidate payload contract is missing or malformed");
  }
  return {
    fixedRoots: payload.fixedRoots.map(safeCandidateRelative),
    trees: payload.trees.map(safeCandidateRelative),
    excludePaths: payload.excludePaths.map(safeCandidateRelative),
    excludePrefixes: payload.excludePrefixes.map((value) => {
      const normalized = safeCandidateRelative(String(value).replace(/\/$/, ""));
      return normalized + "/";
    }),
  };
}

function excludedPayloadPath(relativePath, payload) {
  return payload.excludePaths.includes(relativePath)
    || payload.excludePrefixes.some((prefix) => relativePath.startsWith(prefix));
}

function enumerateCandidatePayload(candidateRoot, payload) {
  const root = path.resolve(candidateRoot);
  let rootStat;
  try { rootStat = fs.lstatSync(root); } catch (_error) { rootStat = null; }
  if (!rootStat || !rootStat.isDirectory() || rootStat.isSymbolicLink()) {
    fail("candidate_producer_root_invalid", "production_closure",
      "candidate root is missing or indirect");
  }
  const paths = new Set();
  payload.fixedRoots.forEach((relativePath) => {
    if (!excludedPayloadPath(relativePath, payload)) paths.add(relativePath);
  });
  function walk(directory, relativeBase, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const childBase = relativeBase ? relativeBase + "/" + entry.name : entry.name;
      const relative = tree + "/" + childBase;
      const full = path.join(directory, entry.name);
      const stat = fs.lstatSync(full);
      if (entry.isSymbolicLink() || stat.isSymbolicLink()) {
        fail("candidate_payload_file_invalid", "production_closure",
          "candidate payload contains a symbolic link", { path: relative });
      }
      if (entry.isDirectory() && stat.isDirectory()) {
        walk(full, childBase, tree);
        return;
      }
      if (!entry.isFile() || !stat.isFile()) {
        fail("candidate_payload_file_invalid", "production_closure",
          "candidate payload contains a non-regular entry", { path: relative });
      }
      if (!excludedPayloadPath(relative, payload)) paths.add(relative);
    });
  }
  payload.trees.forEach((tree) => {
    const directory = path.resolve(root, tree.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(directory); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("candidate_payload_tree_invalid", "production_closure",
        "candidate payload tree is missing or indirect", { tree });
    }
    walk(directory, "", tree);
  });
  return Array.from(paths).sort().map((relativePath) => {
    const file = exactCandidateFile(root, relativePath, 1024 * 1024 * 1024);
    return { path: relativePath, size: file.size, sha256: file.sha256.toUpperCase() };
  });
}

function normalizedHash(value, field) {
  const normalized = String(value || "").toUpperCase();
  if (!SHA256_RE.test(normalized)) {
    fail("candidate_producer_hash_invalid", "production_closure",
      "candidate producer field is not SHA-256", { field });
  }
  return normalized;
}

function computeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
  return sha256Text("artifactSourceHash\t" + normalizedHash(artifactSourceHash, "artifactSourceHash") + "\n"
    + "producerRecipeHash\t" + normalizedHash(producerRecipeHash, "producerRecipeHash") + "\n"
    + "toolchainLockHash\t" + normalizedHash(toolchainLockHash, "toolchainLockHash") + "\n")
    .toUpperCase();
}

function canonicalPayloadClosureHash(files) {
  const rows = files.slice().sort((left, right) => String(left.path) < String(right.path)
    ? -1 : String(left.path) > String(right.path) ? 1 : 0);
  if (!rows.length || new Set(rows.map((entry) => String(entry.path).toLowerCase())).size !== rows.length) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload file set is empty or duplicated");
  }
  const canonical = rows.map((row) => {
    const relative = String(row.path || "").replace(/\\/g, "/");
    const size = Number(row.size);
    const digest = normalizedHash(row.sha256, "payload.sha256");
    if (!relative || relative.startsWith("/") || /(^|\/)\.\.(\/|$)/.test(relative)
        || /[\t\r\n]/.test(relative) || !Number.isSafeInteger(size) || size < 0) {
      fail("candidate_payload_manifest_invalid", "production_closure",
        "candidate payload row is malformed", { relative, size });
    }
    return relative + "\t" + size + "\t" + digest;
  }).join("\n") + "\n";
  return sha256Text(canonical).toUpperCase();
}

function parseCandidateManifest(candidateRoot, manifestFile, payload) {
  const lines = manifestFile.bytes.toString("utf8").replace(/\r/g, "").split("\n");
  if (lines.pop() !== "" || lines.shift() !== "cf7-runtime-manifest-v2") {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest header or final newline is unsupported");
  }
  const metadataNames = ["publishMode", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "toolchainBaseline", "buildIdentityHash", "payloadClosureHash"];
  const metadata = Object.create(null);
  const files = [];
  lines.forEach((line) => {
    const fields = line.split("\t");
    if (fields[0] === "file") {
      if (fields.length !== 4 || !/^\d+$/.test(fields[2])) {
        fail("candidate_payload_manifest_invalid", "production_closure",
          "candidate payload row is malformed");
      }
      files.push({ path: safeCandidateRelative(fields[1]), size: Number(fields[2]),
        sha256: normalizedHash(fields[3], "payload.sha256") });
      return;
    }
    if (fields.length !== 2 || !metadataNames.includes(fields[0])
        || Object.prototype.hasOwnProperty.call(metadata, fields[0]) || !fields[1]) {
      fail("candidate_producer_manifest_invalid", "production_closure",
        "candidate runtime manifest metadata is missing, duplicated, or extra", { line });
    }
    metadata[fields[0]] = fields[1];
  });
  if (Object.keys(metadata).length !== metadataNames.length) {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest metadata set is incomplete");
  }
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((name) => { metadata[name] = normalizedHash(metadata[name], name); });
  const sorted = files.slice().sort((left, right) =>
    left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  if (canonicalJson(files) !== canonicalJson(sorted)) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload rows are not in canonical ordinal order");
  }
  const actualFiles = enumerateCandidatePayload(candidateRoot, payload);
  if (canonicalJson(files) !== canonicalJson(actualFiles)) {
    fail("candidate_payload_file_mismatch", "production_closure",
      "candidate payload manifest differs from the exact candidate payload files", {
        expected: files.map((entry) => entry.path), actual: actualFiles.map((entry) => entry.path),
      });
  }
  if (canonicalPayloadClosureHash(files) !== metadata.payloadClosureHash) {
    fail("candidate_payload_closure_mismatch", "production_closure",
      "candidate payload closure hash differs from exact manifest rows");
  }
  return { metadata, files };
}

function captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure) {
  const metadataFile = exactCandidateFile(candidateRoot, "runtime-build-metadata.v2.json", 64 * 1024);
  const manifestFile = exactCandidateFile(candidateRoot,
    "runtime/cf7-runtime-manifest.tsv", 8 * 1024 * 1024);
  let metadata;
  try { metadata = JSON.parse(metadataFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata is not valid JSON");
  }
  const metadataKeys = ["schema", "builderLabel", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "buildIdentityHash", "payloadClosureHash", "createdAtUtc"].sort();
  if (!isPlainObject(metadata) || metadata.schema !== "cf7-runtime-candidate-metadata.v2"
      || canonicalJson(Object.keys(metadata).sort()) !== canonicalJson(metadataKeys)
      || typeof metadata.builderLabel !== "string" || !metadata.builderLabel.trim()
      || !Number.isFinite(Date.parse(metadata.createdAtUtc))) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata does not have the exact v2 producer schema");
  }
  const hashes = {};
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((field) => { hashes[field] = normalizedHash(metadata[field], field); });
  const parsedManifest = parseCandidateManifest(candidateRoot, manifestFile,
    candidatePayloadContract(closure.root));
  const currentInputs = closure && closure.runtimeInputs && closure.runtimeInputs.domains;
  if (["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].some((field) => parsedManifest.metadata[field] !== hashes[field])
      || computeBuildIdentityHash(hashes.artifactSourceHash, hashes.producerRecipeHash,
        hashes.toolchainLockHash) !== hashes.buildIdentityHash
      || !currentInputs
      || hashes.artifactSourceHash !== currentInputs.artifactSource.sha256
      || hashes.producerRecipeHash !== currentInputs.producerRecipe.sha256
      || hashes.toolchainLockHash !== currentInputs.toolchainLock.sha256
      || hashes.buildIdentityHash !== closure.runtimeInputs.buildIdentityHash
      || hashes.buildIdentityHash !== normalizedHash(candidateIdentity.buildIdentity,
        "candidateIdentity.buildIdentity")
      || hashes.payloadClosureHash !== normalizedHash(candidateIdentity.payloadClosure,
        "candidateIdentity.payloadClosure")) {
    fail("candidate_producer_identity_mismatch", "production_closure",
      "candidate producer/source identity is detached from current tree or runtime identity");
  }
  const core = parsedManifest.files.filter((entry) =>
    entry.path.toLowerCase() === "runtime/crazyflasher7mercenaryempire.core.exe");
  if (core.length !== 1 || core[0].sha256 !== normalizedHash(candidateIdentity.coreSha256,
    "candidateIdentity.coreSha256")) {
    fail("candidate_core_identity_mismatch", "production_closure",
      "candidate runtime identity is detached from the payload manifest Core row");
  }
  const value = { schema: CANDIDATE_PRODUCER_SCHEMA, candidateRoot: path.resolve(candidateRoot),
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: metadataFile.sha256, bytes: metadataFile.size },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: manifestFile.sha256, bytes: manifestFile.size },
    builderLabel: metadata.builderLabel, createdAtUtc: metadata.createdAtUtc,
    artifactSourceHash: hashes.artifactSourceHash,
    producerRecipeHash: hashes.producerRecipeHash,
    toolchainLockHash: hashes.toolchainLockHash,
    buildIdentityHash: hashes.buildIdentityHash,
    runtimeInputCounts: {
      artifactSource: currentInputs.artifactSource.fileCount,
      producerRecipe: currentInputs.producerRecipe.fileCount,
      toolchainLock: currentInputs.toolchainLock.fileCount,
    },
    payloadClosureHash: hashes.payloadClosureHash,
    payloadFileCount: parsedManifest.files.length };
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function verifyCandidateProducerBinding(candidateRoot, candidateIdentity, closure, evidence) {
  const current = captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure);
  if (!isPlainObject(evidence) || evidence.schema !== CANDIDATE_PRODUCER_SCHEMA
      || canonicalJson(current) !== canonicalJson(evidence)) {
    fail("candidate_producer_evidence_mismatch", "production_closure",
      "captured candidate producer evidence differs from exact candidate files");
  }
  return evidence;
}

function bindProductionClosure(closure, candidateIdentity, runId, candidateProducer) {
  const value = { schema: BINDING_SCHEMA, runId,
    productionTreeSha256: closure.treeSha256,
    productionClosureSha256: closure.closureSha256,
    artifactSourceHash: closure.runtimeInputs.domains.artifactSource.sha256,
    producerRecipeHash: closure.runtimeInputs.domains.producerRecipe.sha256,
    toolchainLockHash: closure.runtimeInputs.domains.toolchainLock.sha256,
    buildIdentityHash: closure.runtimeInputs.buildIdentityHash,
    runtimeInputsSha256: closure.runtimeInputs.evidenceSha256,
    candidateIdentitySha256: sha256Text(canonicalJson(publicCandidateIdentity(candidateIdentity))),
    candidateProducerSha256: candidateProducer && candidateProducer.evidenceSha256 };
  value.bindingSha256 = sha256Text(canonicalJson(value));
  return value;
}

function bindActualShop(root, closure, shopId) {
  const matches = closure.files.filter((entry) => entry.role === "shop_data")
    .filter((entry) => {
      try {
        const relative = entry.locator.slice("root:".length).replace(/\//g, path.sep);
        const value = JSON.parse(fs.readFileSync(path.resolve(root, relative), "utf8"));
        return value && value.schema === "npc-shop.v2" && value.shopId === shopId;
      } catch (_error) { return false; }
    });
  if (matches.length !== 1) {
    fail("actual_shop_binding_invalid", "production_closure",
      "actual opened shopId must resolve to exactly one canonical shop JSON", {
        shopId, count: matches.length,
      });
  }
  const file = matches[0];
  const value = { schema: SHOP_BINDING_SCHEMA, shopId, locator: file.locator,
    sha256: file.sha256, bytes: file.bytes, productionTreeSha256: closure.treeSha256 };
  value.bindingSha256 = sha256Text(canonicalJson(value));
  return value;
}

function webFiles(closure) {
  return closure.files.filter((entry) => ["page", "overlay_boot_web", "lazy_registry",
    "npc_lazy_web", "overlay_boot_stylesheet", "overlay_import_stylesheet"]
    .includes(entry.role));
}

function resourceMimeTypes(url, resourceType) {
  if (resourceType === "Document") return ["text/html"];
  if (resourceType === "Stylesheet") return ["text/css"];
  if (resourceType === "Script") return ["text/javascript", "application/javascript"];
  const extension = path.posix.extname(new URL(url).pathname).toLowerCase();
  const image = { ".webp": "image/webp", ".png": "image/png", ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg", ".svg": "image/svg+xml" }[extension];
  if (resourceType === "Image" && image) return [image];
  const font = { ".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff",
    ".woff2": "font/woff2" }[extension];
  if (resourceType === "Font" && font) return [font, "application/octet-stream",
    extension === ".ttf" ? "application/x-font-ttf" : font];
  return [];
}

function cachedResourceFile(root, descriptor) {
  const key = path.resolve(root).toLowerCase() + "\n" + descriptor.relativePath.toLowerCase();
  if (!resourceFileCache.has(key)) resourceFileCache.set(key, exactFile(root, descriptor));
  return resourceFileCache.get(key);
}

function authorityIconNames(pairs) {
  const names = [];
  function add(item) {
    const icon = item && item.icon;
    if (typeof icon === "string" && icon && !names.includes(icon)) names.push(icon);
  }
  if (!Array.isArray(pairs)) {
    fail("authority_icon_pair_set_invalid", "production_closure",
      "authority icon projection requires the verified request/response pair set");
  }
  pairs.forEach((pair) => {
    const request = pair && pair.request;
    const response = pair && pair.response;
    const left = response && response.message;
    const right = request && request.message;
    if (!request || !response || !isPlainObject(left) || !isPlainObject(right)
        || response.event.sequence <= request.event.sequence
        || left.type !== "panel_resp" || right.type !== "panel"
        || left.panel !== "npcshop" || right.panel !== "npcshop"
        || left.panelInstanceId !== right.panelInstanceId || left.cmd !== right.cmd
        || left.callId !== right.callId
        || String(left.domain || "") !== String(right.domain || "")) {
      fail("authority_icon_pair_set_invalid", "production_closure",
        "authority icon projection received a response outside one strict NPC pair");
    }
    if (left.success !== true) return;
    const message = left;
    if (message.domain === "inventory" && message.cmd === "snapshot"
        && Array.isArray(message.snapshots)) {
      message.snapshots.forEach((snapshot) => {
        if (snapshot && Array.isArray(snapshot.slots)) snapshot.slots.forEach((slot) => {
          if (slot && slot.occupied === true) add(slot.item);
        });
      });
      return;
    }
    if (message.domain === "npcshop" && ["snapshot", "tradeCommit"].includes(message.cmd)
        && Array.isArray(message.catalog) && isPlainObject(message.views)) {
      message.catalog.forEach(add);
      Object.keys(message.views).sort().forEach((viewId) => {
        const view = message.views[viewId];
        if (view && Array.isArray(view.slots)) view.slots.forEach((slot) => add(slot && slot.item));
      });
    }
  });
  return names;
}

function iconResourceUris(iconEntry) {
  function uriOf(value) {
    return value && (value.uri || value.file || value.filename) || null;
  }
  function frames(value) {
    const source = value && Array.isArray(value.timelineFrames) && value.timelineFrames.length
      ? value.timelineFrames : value && Array.isArray(value.frames) ? value.frames : [];
    const values = source.map(uriOf).filter(Boolean);
    if (value && value.f1 && !values.includes(value.f1)) values.unshift(value.f1);
    if (value && value.f2 && !values.includes(value.f2)) values.push(value.f2);
    return values;
  }
  if (iconEntry.format === "webp-animated") {
    return [iconEntry.uri || frames(iconEntry)[0]].filter(Boolean);
  }
  const nested = isPlainObject(iconEntry.nestedAnimation) ? iconEntry.nestedAnimation : null;
  if (nested && Array.isArray(nested.layers) && nested.layers.length) {
    const output = [];
    const base = typeof nested.base === "string" ? nested.base : uriOf(nested.base) || iconEntry.f1;
    if (base) output.push(base);
    nested.layers.forEach((layer) => frames(layer && layer.export || layer)
      .forEach((uri) => { if (!output.includes(uri)) output.push(uri); }));
    return output;
  }
  const values = frames(iconEntry);
  const animated = iconEntry.animated === true
    || iconEntry.playback && !["static", "static-first-frame"].includes(iconEntry.playback);
  return animated ? values : values.slice(0, 1);
}

function loadedResourcePolicy(root, closure, iconNames) {
  const web = webFiles(closure);
  const overlayUrl = "https://overlay.local/overlay.html";
  function overlayUrlFor(entry) {
    return "https://overlay.local/"
      + entry.locator.slice("root:launcher/web/".length);
  }
  function row(resourceType, url, reason, source) {
    const mimeTypes = resourceMimeTypes(url, resourceType);
    if (!mimeTypes.length) {
      fail("production_resource_policy_invalid", "production_closure",
        "production resource policy contains an unsupported URL/type", { resourceType, url });
    }
    if (!source || !/^[a-f0-9]{64}$/.test(String(source.sha256 || ""))
        || !Number.isInteger(source.bytes) || source.bytes < 1) {
      fail("production_resource_policy_invalid", "production_closure",
        "production resource policy lacks its expected byte identity", { resourceType, url });
    }
    return { resourceType, url, origin: new URL(url).origin, mimeTypes, reason,
      sha256: source.sha256, bytes: source.bytes };
  }
  const page = web.find((entry) => entry.role === "page");
  const required = [row("Document", overlayUrl, "main_document", page)]
    .concat(web.filter((entry) => entry.role.endsWith("stylesheet"))
      .map((entry) => row("Stylesheet", overlayUrlFor(entry), "static_stylesheet", entry)))
    .concat(web.filter((entry) => ["overlay_boot_web", "lazy_registry", "npc_lazy_web"]
      .includes(entry.role)).map((entry) => row("Script", overlayUrlFor(entry),
        "production_script", entry)));

  const mapSource = readExactText(root, "launcher/web/modules/map-panel-data.js").text;
  const baseStart = mapSource.indexOf("id: 'base'");
  const nextStart = mapSource.indexOf("id: 'faction'", baseStart + 1);
  const baseBlock = baseStart >= 0 && nextStart > baseStart
    ? mapSource.slice(baseStart, nextStart) : "";
  const idlePaths = Array.from(baseBlock.matchAll(
    /(?:backgroundUrl|assetUrl)\s*:\s*['"]([^'"]+)['"]/g)).map((match) => match[1]);
  if (idlePaths.length !== 15 || new Set(idlePaths).size !== 15
      || idlePaths[0] !== "assets/map/page-base.webp"
      || idlePaths.some((entry) => !/^assets\/map\/[A-Za-z0-9._/-]+\.webp$/.test(entry))) {
    fail("production_idle_prewarm_policy_invalid", "production_closure",
      "Overlay base idle prewarm must remain one page image plus fourteen scene visuals", {
        count: idlePaths.length,
      });
  }
  idlePaths.forEach((relativePath) => required.push(row("Image",
    "https://overlay.local/" + relativePath, "idle_prewarm_base",
    cachedResourceFile(root, { role: "idle_prewarm_image",
      relativePath: "launcher/web/" + relativePath }))));

  const conditional = [];
  const fontCss = readExactText(root, "launcher/web/css/panels/foundation-top.css").text;
  const fontUrls = Array.from(fontCss.matchAll(/src\s*:\s*url\(\s*['"]([^'"]+)['"]\s*\)/gi))
    .map((match) => match[1]).filter((url) => url.startsWith("https://cfn-fonts.local/"));
  if (!fontUrls.length || new Set(fontUrls).size !== fontUrls.length) {
    fail("production_conditional_font_policy_invalid", "production_closure",
      "conditional font URL inventory is empty or duplicated");
  }
  let fontManifest;
  try {
    fontManifest = JSON.parse(readExactText(root,
      "launcher/web/assets/fonts/font-pack-manifest.json").text);
  } catch (_error) {
    fail("production_conditional_font_policy_invalid", "production_closure",
      "font-pack manifest cannot be parsed");
  }
  const manifestFonts = [];
  Object.keys(fontManifest && fontManifest.groups || {}).forEach((groupName) => {
    const files = fontManifest.groups[groupName] && fontManifest.groups[groupName].files;
    if (Array.isArray(files)) manifestFonts.push(...files);
  });
  const fontByName = new Map();
  manifestFonts.forEach((entry) => {
    if (!isPlainObject(entry) || typeof entry.name !== "string" || fontByName.has(entry.name)
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1) {
      fail("production_conditional_font_policy_invalid", "production_closure",
        "font-pack manifest contains a malformed or duplicate file mapping");
    }
    fontByName.set(entry.name, entry);
  });
  fontUrls.forEach((url) => {
    const name = decodeURIComponent(new URL(url).pathname.slice(1));
    const source = fontByName.get(name);
    if (!source) {
      fail("production_conditional_font_policy_invalid", "production_closure",
        "CSS font URL is absent from font-pack manifest", { url });
    }
    conditional.push(row("Font", url, "conditional_font_manifest", source));
  });

  const skinRelative = "launcher/web/css/workbench/skins.css";
  const skinCss = readExactText(root, skinRelative).text;
  const skinPaths = [];
  Array.from(skinCss.matchAll(/url\(\s*['"]?([^'"\s)]+)['"]?\s*\)/gi))
    .map((match) => match[1]).filter((value) => !/^(?:data:|[a-z]+:|\/)/i.test(value))
    .forEach((value) => {
      const normalized = path.posix.normalize(path.posix.join(path.posix.dirname(skinRelative), value));
      if (/^launcher\/web\/[A-Za-z0-9._/-]+\.(?:png|jpe?g|webp|svg)$/i.test(normalized)
          && !skinPaths.includes(normalized)) skinPaths.push(normalized);
    });
  if (!skinPaths.length) {
    fail("production_conditional_skin_policy_invalid", "production_closure",
      "visible workbench skin asset inventory is empty");
  }
  skinPaths.forEach((relativePath) => conditional.push(row("Image",
    "https://overlay.local/" + relativePath.slice("launcher/web/".length),
    "conditional_visible_workbench_skin",
    cachedResourceFile(root, { role: "conditional_visible_workbench_skin", relativePath }))));

  let iconManifest;
  try {
    iconManifest = JSON.parse(readExactText(root, "launcher/web/icons/manifest.json").text);
  } catch (_error) {
    fail("production_icon_manifest_invalid", "production_closure",
      "production icon manifest cannot be parsed");
  }
  const dynamicNames = Array.isArray(iconNames) ? iconNames : [];
  if (new Set(dynamicNames).size !== dynamicNames.length
      || dynamicNames.some((name) => typeof name !== "string" || !name)) {
    fail("production_icon_projection_invalid", "production_closure",
      "authority icon-name projection is malformed or duplicated");
  }
  dynamicNames.forEach((name) => {
    const entry = iconManifest && iconManifest[name];
    if (!isPlainObject(entry)) {
      fail("production_icon_projection_invalid", "production_closure",
        "authority icon name is absent from the production icon manifest", { name });
    }
    const uris = iconResourceUris(entry);
    if (!uris.length) {
      fail("production_icon_projection_invalid", "production_closure",
        "authority icon manifest entry has no renderable resource", { name });
    }
    uris.forEach((uri) => {
      if (!/^[A-Za-z0-9._-]+\.(?:png|webp)$/i.test(uri)) {
        fail("production_icon_projection_invalid", "production_closure",
          "authority icon resource URI is unsafe", { name, uri });
      }
      const url = "https://overlay.local/icons/" + uri;
      const file = cachedResourceFile(root, { role: "authority_projected_icon",
        relativePath: "launcher/web/icons/" + uri });
      if (!required.some((resource) => resource.resourceType === "Image" && resource.url === url)) {
        required.push(row("Image", url, "authority_projected_icon:" + name, file));
      }
    });
  });
  const all = required.concat(conditional);
  if (new Set(all.map((entry) => entry.resourceType + "\n" + entry.url)).size !== all.length) {
    fail("production_resource_policy_invalid", "production_closure",
      "required and conditional production resource policies overlap or duplicate");
  }
  return { required, conditional };
}

function validateLoadedResourceContract(root, closure, occurrences, frameId, iconNames) {
  const policy = loadedResourcePolicy(root, closure, iconNames);
  if (!Array.isArray(occurrences) || typeof frameId !== "string" || !frameId) {
    fail("loaded_production_resource_set_invalid", "production_closure",
      "raw production resource contract lacks its main frame or occurrence stream");
  }
  const key = (entry) => String(entry.resourceType || "") + "\n" + String(entry.url || "");
  const requiredKeys = policy.required.map(key);
  const conditionalKeys = policy.conditional.map(key);
  const requiredSet = new Set(requiredKeys);
  const conditionalSet = new Set(conditionalKeys);
  const allByKey = new Map(policy.required.concat(policy.conditional)
    .map((entry) => [key(entry), entry]));
  const actualKeys = occurrences.map(key);
  const actualRequired = actualKeys.filter((entry) => requiredSet.has(entry));
  const actualConditional = actualKeys.filter((entry) => conditionalSet.has(entry));
  const expectedConditional = conditionalKeys.filter((entry) => actualConditional.includes(entry));
  if (canonicalJson(actualRequired) !== canonicalJson(requiredKeys)
      || canonicalJson(actualConditional) !== canonicalJson(expectedConditional)
      || new Set(actualKeys).size !== actualKeys.length
      || occurrences.some((entry, index) => {
        const expected = allByKey.get(actualKeys[index]);
        return !isPlainObject(entry) || !expected || entry.occurrence !== index + 1
          || entry.frameId !== frameId
          || entry.frameUrl !== "https://overlay.local/overlay.html"
          || entry.frameOrigin !== "https://overlay.local"
          || entry.origin !== expected.origin
          || !expected.mimeTypes.includes(entry.mimeType)
          || entry.sourceMethod !== "Page.getResourceContent"
          || entry.sourceSha256 !== expected.sha256 || entry.sourceBytes !== expected.bytes;
      })) {
    fail("loaded_production_resource_set_invalid", "production_closure",
      "raw production resources contain an extra, omission, duplicate, reorder, child frame, foreign origin, or MIME drift", {
        actual: actualKeys, required: requiredKeys, conditional: conditionalKeys,
      });
  }
  return policy;
}

function isRelevantScriptUrl(url, closure) {
  const prefix = "https://overlay.local/";
  if (typeof url !== "string" || !url.startsWith(prefix)) return false;
  const relative = url.slice(prefix.length);
  const expected = new Set(webFiles(closure).filter((entry) => entry.role !== "page")
    .map((entry) => entry.locator.slice("root:launcher/web/".length)));
  if (expected.has(relative)) return true;
  return /^[A-Za-z0-9._/-]+\.js$/.test(relative);
}

function isRelevantStylesheetUrl(url, closure) {
  const prefix = "https://overlay.local/";
  if (typeof url !== "string" || !url.startsWith(prefix)) return false;
  const relative = url.slice(prefix.length);
  const expected = new Set(webFiles(closure)
    .filter((entry) => entry.role.endsWith("stylesheet"))
    .map((entry) => entry.locator.slice("root:launcher/web/".length)));
  if (expected.has(relative)) return true;
  return /^[A-Za-z0-9._/-]+\.css$/.test(relative);
}

module.exports = {
  AS2_FILES,
  BINDING_SCHEMA,
  BUILD_FILES,
  CANDIDATE_PRODUCER_SCHEMA,
  CLOSURE_SCHEMA,
  HOST_FILES,
  LOADED_SCHEMA,
  RUNTIME_INPUTS_SCHEMA,
  SHOP_BINDING_SCHEMA,
  bindActualShop,
  bindProductionClosure,
  canonicalPayloadClosureHash,
  captureCandidateProducerBinding,
  captureProductionClosure,
  computeBuildIdentityHash,
  currentArtifactSourceIdentity,
  currentRuntimeInputIdentity,
  declaredWebDependencies,
  inspectInventorySurfaceSourceContract,
  isRelevantScriptUrl,
  isRelevantStylesheetUrl,
  authorityIconNames,
  loadedResourcePolicy,
  validateLoadedResourceContract,
  productionFiles,
  publicCandidateIdentity,
  sameProductionTree,
  verifyCandidateProducerBinding,
  verifyProductionClosure,
  webFiles,
};
