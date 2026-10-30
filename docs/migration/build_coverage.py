#!/usr/bin/env python3
"""Read frozen sources/ledgers and write documentation only."""
import collections
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project',type=pathlib.Path,required=True,help='Frozen project tree to audit; writes only docs/migration.')
parser.add_argument('--repo',type=pathlib.Path,required=True,help='Git repository containing the three fixed source revisions.')
parser.add_argument('--inputs',type=pathlib.Path,help='Owner ledger/report directory. Defaults to this project\'s archived evidence; use /tmp only while the live migration is active.')
args=parser.parse_args()
REPO=args.repo.resolve();STAGE=args.project.resolve()
OUT = STAGE / 'docs/migration'
ARCHIVE = OUT / 'evidence/1.22'
INPUTS=args.inputs.resolve() if args.inputs else ARCHIVE
REPORT=INPUTS/'doku-122-stage-report.json'
report=json.loads(REPORT.read_text())
PREPORT=pathlib.Path(report['stage']).parent/'doku-122-preport-jwk47pjm'
OUT.mkdir(parents=True, exist_ok=True)
ARCHIVE.mkdir(parents=True, exist_ok=True)
REFS = {'original_181':'7af200ca1b582a86c92ab3d498c6af43a20d201a', 'framework_181':'d89f94d1dd03d1b3369054351ee95ccc93d9cb93', 'recovery_122':'2af1f49bdde26131f85a453a821fce7351cf4885'}
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
def load(path): return json.loads(pathlib.Path(path).read_text())
mapping = load(INPUTS/'doku-122-full-map.json')['paths']
fixture = load(STAGE/'tools/validation/fixtures/recovery_122_paths.json')['paths']
def mapped(source, fallback=None): return mapping.get('res://'+source,'res://'+(fallback or source)).removeprefix('res://')
def git(*args): return subprocess.check_output(['git',*args],cwd=REPO)
def tree(ref):
    result = {}
    for entry in git('ls-tree','-rz',ref).decode().split('\0'):
        if not entry: continue
        header,path=entry.split('\t',1); mode,kind,oid=header.split()
        result[path]={'mode':mode,'kind':kind,'oid':oid}
    return result
trees={name:tree(ref) for name,ref in REFS.items()}
# The method source always comes from the immutable Git objects, never from a mutable checkout.
gd_sources=sorted(p for p in trees['recovery_122'] if p.endswith('.gd'))
queries=''.join(trees['recovery_122'][p]['oid']+'\n' for p in gd_sources).encode()
batch=subprocess.check_output(['git','cat-file','--batch'],cwd=REPO,input=queries)
original_gd={};offset=0
for p in gd_sources:
    end=batch.index(b'\n',offset);oid,kind,size=batch[offset:end].decode().split();size=int(size);offset=end+1
    data=batch[offset:offset+size];offset+=size+1
    if oid!=trees['recovery_122'][p]['oid'] or kind!='blob':raise ValueError('Unexpected Git batch object for '+p)
    original_gd[p]=data.decode()
raw_changes=git('diff','--name-status','--no-renames','-z',REFS['original_181'],REFS['recovery_122']).decode().split('\0')
changes={raw_changes[i+1]:raw_changes[i] for i in range(0,len(raw_changes)-1,2)}
archive_inputs=[REPORT,INPUTS/'doku-122-full-map.json',INPUTS/'doku122-method-coverage-pending.json',STAGE/'tools/validation/fixtures/recovery_122_paths.json',INPUTS/'doku122-root-resource-moves.json']
ledgers={}; index=collections.defaultdict(list)
for owner,key in [('platform','decisions'),('business','files'),('gameplay','files'),('root',None)]:
    path=INPUTS/('doku122-'+owner+'-resolutions.json');d=load(path);ledgers[owner]=d;archive_inputs.append(path)
    records=d[key] if key else d
    for number,item in enumerate(records):
        target=item.get('target',item.get('path'))
        index[target].append({'owner':owner,'archive':f'docs/migration/evidence/1.22/{path.name}','record_index':number,'record_collection':key,'decision':item.get('resolution',item.get('action',item.get('status'))),'reason':item.get('reason',item.get('basis','')),'recorded_sha256':item.get('after_sha256')})

SUPPLEMENTAL = {
'products/meowdoku/app/platform/auth_manager.gd':('root','_warn_if_luid_stalled','LUID stall warning now uses a child Timer and named callback; node teardown cancels the wait while preserving the authentication gate and warning delay.'),
'products/meowdoku/app/features/abtest/config/health_points_rule_config.gd':('root','lives_for_rule','Extract a pure static DSL evaluator so a round uses its frozen health policy instead of rereading live AB values.'),
'products/meowdoku/app/diagnostics/cheat/fixtures/streak_history_fixture_session.gd':('root','prepare','Both prepare and execute require OS.is_debug_build() and reject custom rel; standard release exports cannot expose history mutation even with empty custom_features.'),
'products/meowdoku/app/diagnostics/cheat/remote_console_access.gd':('root','_get_bridge','Require debug build and non-rel before loading the remote console bridge; product debug UI remains distinct from editor MCP.'),
'products/meowdoku/gameplay/presentation/main/view/base_game_toast.gd':('root','_play_entry_anim','Replace two detached SceneTreeTimer waits with a cancellable child Timer; hide/replay invalidates the token and releases prior animation work.'),
'products/meowdoku/gameplay/presentation/main/view/bullets_area.gd':('gameplay','_layout_bullets','Resolve domain inline icon identifiers to product texture paths in the presentation layer; domain logic no longer depends on assets.'),
'products/meowdoku/app/features/peekaboo/view/peekaboo_confirm_page.gd':('root',None,'Remove duplicate close_requested declaration because the base popup already declares the signal; preserve inherited close behavior.'),
'products/meowdoku/app/features/peekaboo/view/peekaboo_flow.gd':('root','run','Bind asynchronous flow to weak Home ownership and presentation revision; cancellation releases the rank presentation lease once; exact-ID ad rewards and atomic claim_reward replace separate collect/claim writes.'),
'products/meowdoku/app/ui/clock_ticker.gd':('root','_ready','Align a child Timer to the next second then repeat at 1 second; destroying the node cancels the startup wait synchronously.'),
'scripts/framework/ui/extensions/gradient_label.gd':('root',None,'Redirect the shader preload to the shared framework shader path after resource ownership relocation.'),
'scripts/framework/ui/extensions/rolling_number.gd':('root','roll','Kill the existing tween even for a same-value replacement, and use weak label/tween references to break finished-callback cycles.'),
'scripts/framework/ui/extensions/single_line_glyph_label.gd':('root',None,'Redirect the glyph-group shader preload to the shared framework shader path after resource ownership relocation.'),
'products/meowdoku/app/ui/queue/ui_popup_entry.gd':('root',None,'Retain 1.22 key/callable entries and add the framework ui_name/params/condition/once_per_session contract for event-driven queue ownership.'),
'products/meowdoku/app/ui/ui_name.gd':('root',None,'Restore PLAYTEST_SIMULATOR for the retained development-only framework page; UIRegistry gates registration to debug and non-rel.'),
'products/meowdoku/app/diagnostics/ui/playtest_simulator_page.tscn':('root',None,'Restore the preport scene required by the deliberately retained development-only simulator; upstream deletion does not retire the framework diagnostic route.'),
'products/meowdoku/app/diagnostics/view/playtest_simulator_page.gd.uid':('root',None,'Restore the script UID with the retained simulator scene and debug-only registry route.'),
}
method_re=re.compile(r'^(?:static )?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',re.M)
texts={};methods={};classes={};parents={}
for top in ['scripts','products','addons','tools']:
    for path in (STAGE/top).rglob('*.gd'):
        rel=path.relative_to(STAGE).as_posix();text=path.read_text();texts[rel]=text
        methods[rel]={m.group(1):text.count('\n',0,m.start())+1 for m in method_re.finditer(text)}
        c=re.search(r'^class_name\s+(\w+)',text,re.M);p=re.search(r'^extends\s+([^\n]+)',text,re.M)
        if c:classes[c.group(1)]=rel
        parents[rel]=p.group(1).strip() if p else ''
def evidence(path,method=None,line=None):
    if method is not None:
        if method not in methods.get(path,{}):raise ValueError(f'missing replacement {path}:{method}')
        line=methods[path][method]
    return {'path':path,'line':line or 1,**({'method':method} if method else {}),'sha256':sha(STAGE/path)}
def inherited(path,name):
    seen=set();p=path
    while p and p not in seen:
        seen.add(p);base=parents.get(p,'')
        p=base.strip('"\'').removeprefix('res://') if base.startswith(('"res://',"'res://")) else classes.get(base)
        if p and name in methods.get(p,{}):return p
    return None

S='products/meowdoku/gameplay/application/selection/level_selector.gd'
UI='scripts/framework/ui/ui_window_manager.gd'
MASK='scripts/framework/ui/ui_modal_mask.gd'
PUI='products/meowdoku/app/ui/ui_manager.gd'
STORE='scripts/framework/storage/save_store.gd'
CORE='scripts/framework/storage/local_core_store.gd'
ECON='scripts/framework/application/economy_service.gd'
POLICY='products/meowdoku/app/state/meowdoku_award_policy.gd'
PROGRESS='products/meowdoku/app/state/meowdoku_progress_state.gd'
GAMESTATE='products/meowdoku/app/state/game_state.gd'
REPLACEMENTS={}
def replace(source,name,reason,refs,disposition='replaced'):
    REPLACEMENTS[(source,name)]={'disposition':disposition,'reason':reason,'replacement_evidence':[evidence(*ref) for ref in refs]}
replace('scripts/common/unikit_manager.gd','_mark_reward_received','Placement-only inference and earliest-watchdog deletion are retired: the callback must identify an existing show_id, mark exactly that session, remove exactly its watchdog, and deliver once under the current record generation.', [('products/meowdoku/app/platform/unikit_manager.gd','_on_ad_rewarded_for_show'),('products/meowdoku/app/platform/unikit_manager.gd','_has_identified_reward_bridge')])
replace('scripts/module/award/award_manager.gd','_apply_item','Reward item mutations are staged on the same candidate as entitlement consumption and the durable claim.',[(POLICY,'stage_item'),(ECON,'stage_claim')])
replace('scripts/module/award/award_manager.gd','_item_dict_valid','Validate reward shape, supported item kind and business constraints before atomic candidate mutation.',[(POLICY,'validate_award'),(ECON,'_validate_award_items')])
replace('scripts/module/daily_streak/view/streak_revive_flow.gd','_wait_page_hidden','Detached hidden waits were replaced by bounded owner/page-generation frame polling in the actual intent/query waits; hide/destroy returns stale and disconnects temporary listeners without treating cancellation as give-up.',[('products/meowdoku/app/features/daily_streak/view/streak_revive_flow.gd','_await_intent'),('products/meowdoku/app/features/daily_streak/view/streak_revive_flow.gd','_await_ad_query'),('products/meowdoku/app/features/daily_streak/view/streak_revive_flow.gd','_capture_owner')])
replace('scripts/module/game_state/save_store.gd','_load_once','Read and elect valid revisioned slots rather than mutating a single-file cache before semantic validation.',[(STORE,'load_result'),(STORE,'_scan_slots')])
replace('scripts/module/game_state/save_store.gd','_read_config','Candidate reads verify decoding, commit envelope/revision and the supplied schema validator before a slot can be selected.',[(STORE,'_read_candidate'),(CORE,'_validate_config')])
for name in ['capture_file_snapshot','restore_file_snapshot']:
    replace('scripts/module/game_state/save_store.gd',name,'Explicitly retired with parent approval: raw per-file restore would bypass revision and aggregate ownership. Deep candidate snapshots and validated optimistic commits provide rollback by not publishing a failed candidate; original legacy files are imported read-only.',[(CORE,'snapshot'),(CORE,'commit'),(STORE,'commit_config')],'retired_with_transaction_replacement')
for name in ['_apply_level_won','_apply_level_failed','_dispatch_normal_level_settlement','_preserve_returnee_settlement']:
    replace('scripts/module/game_state/game_state.gd',name,'Move the formerly live-mutating settlement chain onto MeowdokuProgressState, an isolated selection candidate. The retained public legacy API delegates through _commit_legacy_progress, stages selection and outcome together, and publishes only after commit_core_candidate succeeds. The sealed LevelSelector.apply_won_settlement entry is not called.',[(PROGRESS,name),(GAMESTATE,'_commit_legacy_progress'),(GAMESTATE,'on_level_won'),(GAMESTATE,'on_level_failed')])
replace('scripts/module/gameplay/selector/level_selector.gd','_get_resolver','Create and bind a resolver for each candidate runtime; do not retain cross-round strategy/cursor state.',[(S,'_resolve_strategy')])
replace('scripts/module/gameplay/selector/level_selector.gd','_finalize','Finalize selection on DokuSelectionState, return an explicit plan/effects and publish only through the round candidate commit.',[(S,'prepare'),(S,'build_plan'),('products/meowdoku/gameplay/application/doku_selection_state.gd','finalize_selected_puzzle'),('products/meowdoku/gameplay/application/level_data.gd','stage_selected')])
replace('scripts/module/gameplay/selector/level_selector.gd','_fail_and_restore','Failed preparation discards its isolated runtime candidate. Conflict or durable-write failure does not mutate live progress, so the old mutate-live-then-restore path is deliberately removed.',[(S,'prepare'),('products/meowdoku/gameplay/application/level_data.gd','stage_selected')])
replace('scripts/module/ui/base/ui_base_window.gd','_attach_button_press_guard','Move the product input guard out of the generic window base; product scene preparation and dynamic widget initialization recursively bind the same held/released behavior.',[(PUI,'_attach_product_button_guard'),(PUI,'_prepare_product_scene'),(PUI,'initialize_dynamic_widget')])
replace('scripts/module/ui/queue/ui_popup_queue.gd','_run','The event-driven queue handles ui_name entries and cancellation while _show_callable preserves the original awaited callable path; flush serializes work and emits drained.',[('products/meowdoku/app/ui/queue/ui_popup_queue.gd','flush'),('products/meowdoku/app/ui/queue/ui_popup_queue.gd','_show_callable'),('products/meowdoku/app/ui/queue/ui_popup_queue.gd','_finish_current')])
for name in ['_assign_z_index','_compact_z_indices','_reorder_window_tree']:
    replace('scripts/module/ui/ui_manager.gd',name,'Assign bounded z-indices from the current ordered stack and synchronize node hit-test order in one pass; no monotonically growing per-layer counter or separate compaction is needed.',[(UI,'_assign_z_indices'),(UI,'show_ui')])
replace('scripts/module/ui/ui_manager.gd','_evict_cached','Registry scene replacement evicts the hidden cached instance through _do_destroy before recreating it; explicit destruction and tree-exit cleanup maintain stack/mask ownership.',[(UI,'_get_or_create'),(UI,'destroy_ui'),(UI,'_on_window_exiting')])
replace('scripts/module/ui/ui_manager.gd','_is_in_stack','Current stack membership is evaluated from _ordered_windows().has(win) inside show/close waits, preserving the closing-window slot during reentry.',[(UI,'show_ui'),(UI,'await_hidden')])
for name,fn in {'_abort_mask_crossfade':'_promote_secondary','_fade_out_mask':'_fade_out','_hide_mask':'finish_close','_kill_mask_secondary_tween':'_stop_secondary_tween','_kill_mask_tween':'_stop_primary_tween','_restack_mask':'restack','_show_mask':'show_for','_start_mask_crossfade':'begin_close'}.items():
    replace('scripts/module/ui/ui_manager.gd',name,'Delegate mask resource/tween ownership to UIModalMask; UIWindowManager selects the actual top modal and releases requests only for the matching completed close.',[(MASK,fn),(UI,'show_ui'),(UI,'hide_ui')])

issues=[];files=[];retargets=[];target_sources=collections.defaultdict(list)
original_evidence_groups=collections.Counter();original_evidence_mismatches=[];original_evidence_identities={}
for source,meta in trees['recovery_122'].items():
    if not source.startswith(('.autoconverted/','docs/recovery/1.22.0/')):continue
    p=STAGE/source;actual=None
    if p.is_file():
        raw=p.read_bytes();actual=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    original_evidence_groups[source.split('/')[0]]+=1
    original_evidence_identities[source]=meta['oid']
    if actual!=meta['oid']:original_evidence_mismatches.append({'path':source,'expected_git_blob':meta['oid'],'actual_git_blob':actual})
original_evidence_integrity={'fixed_ref':REFS['recovery_122'],'groups':dict(original_evidence_groups),'files_checked':len(original_evidence_identities),'mismatches':original_evidence_mismatches,'expected_object_map_sha256':hashlib.sha256(json.dumps(original_evidence_identities,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'ok':not original_evidence_mismatches}
issues.extend({'kind':'original_recovery_evidence_changed',**r} for r in original_evidence_mismatches)
for row in report['files']:
    target_sources[mapped(row['source'],row['target'])].append(row['source'])
for row in report['files']:
    source=row['source'];target=mapped(source,row['target']);path=STAGE/target;h=sha(path)
    owners=[]
    for key in dict.fromkeys([target,row['target']]):owners.extend(index.get(key,[]))
    owners=[{**owner,'recorded_sha256_matches_final':owner['recorded_sha256']==h if owner['recorded_sha256'] else None} for owner in owners]
    supplemental=None
    if target in SUPPLEMENTAL:
        owner,symbol,reason=SUPPLEMENTAL[target]
        # A function can have been renamed during implementation; the file diff is the evidence when no symbol is specified.
        supplemental={'owner':owner,'decision':'audited_post_import_fix','reason':reason,'evidence':evidence(target,symbol if symbol in methods.get(target,{}) else None)}
    original_active=source in trees['recovery_122']
    aliases=[p for p in target_sources[target] if p!=source and p in trees['recovery_122']]
    if not h:
        if original_active:issues.append({'kind':'missing_upstream_target','source':source,'target':target})
        disposition='deleted_upstream_removed'
        reason='1.22 removes this source; no final runtime file remains at its mapped target.'
    elif not original_active and aliases:
        disposition='upstream_relocated_alias'
        reason='The old source is removed but the same final target is supplied by the listed active 1.22 replacement source(s).'
    elif not original_active:
        disposition='preserved_framework_extension'
        reason='The framework retains this file or diagnostic extension despite its absence from the 1.22 tree; owner decision or restored preport evidence records the reason.'
    elif h==row['incoming_sha256']:
        disposition='imported_mapped_upstream'
        reason='Final bytes equal the mapped incoming 1.22 file; resource references were relocated by the recorded map.'
    elif h==row['framework_sha256']:
        disposition='preserved_framework'
        reason='Final bytes retain the framework implementation; where upstream differs, the recorded owner resolution describes its integration or intentional preservation.'
    else:
        disposition='integrated_or_retargeted'
        reason='Final bytes differ from mapped incoming/framework baseline; owner ledger or supplemental reviewed diff records the completed integration.'
        if not owners and not supplemental and target==row['target']:issues.append({'kind':'unexplained_modified_file','source':source,'target':target})
    if (row['action'].startswith('review_') or row['action']=='merge_clean_review_required') and not owners:
        issues.append({'kind':'unresolved_review','source':source,'target':target})
    record={'source':source,'upstream_change':changes.get(source,'unchanged_or_framework_only'),'initial_target':row['target'],'final_target':target,'initial_action':row['action'],'disposition':disposition,'reason':reason,'exists':path.is_file(),'sha256':h,'mapped_baseline_sha256':{'ancestor':row['ancestor_sha256'],'framework':row['framework_sha256'],'incoming':row['incoming_sha256']},'original_git_blobs':{name:tree_.get(source) for name,tree_ in trees.items()},'owner_decisions':owners}
    if supplemental:record['supplemental_decision']=supplemental
    if aliases:record['replacement_sources']=aliases
    if target!=row['target']:
        retargets.append({'source':source,'initial_target':row['target'],'final_target':target,'exists':path.is_file()});record['relocation_evidence']='Final complete map and recovery fixture agree; original asset/source identity is unchanged by directory ownership.'
    files.append(record)
sources={r['source'] for r in report['files']}
for p in sorted(set(changes)-sources):issues.append({'kind':'unlisted_upstream_change','source':p})
map_mismatch=[{'source':s,'mapping':t,'fixture':fixture.get(s)} for s,t in mapping.items() if fixture.get(s)!=t]
issues.extend({'kind':'mapping_fixture_mismatch',**r} for r in map_mismatch)

method_files=[];exceptions=[];method_counts=collections.Counter()
for source in sorted(trees['recovery_122']):
    if not source.endswith('.gd'):continue
    text=original_gd[source];old={m.group(1):text.count('\n',0,m.start())+1 for m in method_re.finditer(text)};target=mapped(source);direct=methods.get(target,{})
    file_record={'source':source,'target':target,'source_git_blob':trees['recovery_122'][source]['oid'],'target_sha256':sha(STAGE/target),'upstream_method_count':len(old),'retained_direct':{n:{'source_line':old[n],'target_line':direct[n]} for n in sorted(old.keys()&direct.keys())},'exceptions':[]}
    method_counts['scripts']+=1;method_counts['methods']+=len(old);method_counts['direct']+=len(file_record['retained_direct'])
    for name in sorted(old.keys()-direct.keys()):
        record={'source':source,'source_line':old[name],'target':target,'method':name}
        parent=inherited(target,name)
        if parent:record.update({'disposition':'inherited','reason':'The product adapter extends the framework class; this method is provided by its ancestor rather than copied into the adapter.','replacement_evidence':[evidence(parent,name)]});method_counts['inherited']+=1
        elif (source,name) in REPLACEMENTS:record.update(REPLACEMENTS[(source,name)]);method_counts[record['disposition']]+=1
        else:record['disposition']='uncovered';issues.append({'kind':'method_uncovered',**record})
        exceptions.append(record);file_record['exceptions'].append(name)
    method_files.append(file_record)
exception_index={(r['source'],r['method']):r for r in exceptions}
pending_resolutions=[];pending_keys=set()
for item in load(INPUTS/'doku122-method-coverage-pending.json'):
    source=item['source'].removeprefix('res://');target=mapped(source)
    for name in item['missing_original_methods']:
        pending_keys.add((source,name))
        if (source,name) in exception_index:
            pending_resolutions.append(exception_index[(source,name)])
        elif name in methods.get(target,{}):
            pending_resolutions.append({'source':source,'target':target,'method':name,'disposition':'directly_present_after_pending_snapshot','reason':'The pending list predates the current implementation. The method is now directly declared in the mapped target; UI input override delegates to the inherited window manager.','replacement_evidence':[evidence(target,name)]})
        else:
            issues.append({'kind':'pending_method_unresolved','source':source,'target':target,'method':name})
new_exceptions=[r for r in exceptions if (r['source'],r['method']) not in pending_keys]

# Search production and validation scripts, including call()/Callable strings, excluding declarations/comments.
checked_names={name for source,name in REPLACEMENTS}|{'add_in_flight_award','remove_in_flight_award','_migrate_legacy_save','apply_won_settlement'}
uses=collections.defaultdict(list)
pattern=re.compile(r'\b('+'|'.join(map(re.escape,sorted(checked_names,key=len,reverse=True)))+r')\b')
valid_replacement_definitions={(r['path'],r.get('method')) for v in REPLACEMENTS.values() for r in v['replacement_evidence']}
for path,text in texts.items():
    for number,line in enumerate(text.splitlines(),1):
        stripped=line.strip()
        if stripped.startswith('#') or re.match(r'^(?:static )?func\s+',stripped):continue
        # These symbols contain no #; trim inline comments to avoid counting documentation as calls.
        code=line.split('#',1)[0]
        for name in set(pattern.findall(code)):
            local_owner=name in methods.get(path,{}) or inherited(path,name)
            qualified_receivers=re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)\.'+re.escape(name)+r'\b',code)
            local_call=all(receiver in {'self','super'} for receiver in qualified_receivers)
            replacement_owner=bool(local_owner) and local_call and (path,name) in valid_replacement_definitions
            unrelated_owner=bool(local_owner) and local_call and name in {'_run','_finalize'}
            allowed=replacement_owner or unrelated_owner
            classification='replacement_owner_method' if replacement_owner else ('unrelated_local_method' if unrelated_owner else 'requires_review')
            uses[name].append({'path':path,'line':number,'text':code.strip(),'classification':classification,'local_declaration':evidence(path,name) if name in methods.get(path,{}) else None})
            if not allowed:issues.append({'kind':'retired_or_replaced_call_remains','method':name,'path':path,'line':number,'text':code.strip()})
resource_hits=[];resource_files_checked=0
for top in ['scripts','products','addons']:
    for path in (STAGE/top).rglob('*'):
        if not path.is_file() or path.suffix not in {'.tscn','.tres','.cfg','.json','.godot'}:continue
        resource_files_checked+=1
        for number,line in enumerate(path.read_text().splitlines(),1):
            for name in set(pattern.findall(line)):
                hit={'kind':'retired_or_replaced_resource_reference','method':name,'path':path.relative_to(STAGE).as_posix(),'line':number,'text':line.strip()}
                resource_hits.append(hit);issues.append(hit)
call_audit={'scope':['scripts/**/*.{gd,tscn,tres,cfg,json,godot}','products/**/*.{gd,tscn,tres,cfg,json,godot}','addons/**/*.{gd,tscn,tres,cfg,json,godot}','tools/**/*.gd'],'includes_dynamic_call_strings':True,'excludes':['declarations','comments'],'resource_files_checked':resource_files_checked,'resource_symbol_hits':resource_hits,'symbols':{name:{'occurrences':uses[name],'unresolved_count':sum(x['classification']=='requires_review' for x in uses[name])} for name in sorted(checked_names)},'sealed_api_replacements':[
    {'path':'products/meowdoku/app/state/game_state.gd','methods':['add_in_flight_award','remove_in_flight_award'],'reason':'Explicitly rejects old pending-award mutation; EconomyService handles entitlement registration/claim in candidate commits.','replacement_evidence':[evidence(ECON,'register_award'),evidence(ECON,'claim_award')]},
    {'path':'products/meowdoku/app/state/game_state.gd','methods':['_migrate_legacy_save'],'reason':'Compatibility no-op has no production callers; legacy import belongs to MeowdokuStore and must not rewrite original files.'},
    {'path':S,'methods':['apply_won_settlement'],'reason':'Sealed legacy live-mutation entry; callers must stage strategy settlement inside a candidate transaction.','replacement_evidence':[evidence(S,'stage_won_settlement')]}]}

previous_extra={}
if (OUT/'1.22-coverage.json').is_file():
    previous_extra={r['path']:r for r in load(OUT/'1.22-coverage.json').get('extra_framework_or_migration_files',[])}
extra=[];known_targets={r['final_target'] for r in files}
for p in sorted(STAGE.rglob('*')):
    if not p.is_file():continue
    rel=p.relative_to(STAGE).as_posix()
    if any(part in {'.git','.godot','__pycache__'} for part in p.relative_to(STAGE).parts) or rel.startswith('docs/migration/evidence/') or rel in {'docs/migration/1.22-coverage.json','docs/migration/1.22-coverage.md'}:continue
    if rel in known_targets:continue
    pre=PREPORT/rel
    before=sha(pre) if pre.is_file() else previous_extra.get(rel,{}).get('preport_sha256')
    extra.append({'path':rel,'sha256':sha(p),'origin':'preport_framework_file' if before else 'migration_added_file','preport_sha256':before,'owner_decisions':index.get(rel,[]),'scope_note':'Inventoried separately; this file has no source row in the upstream delta and is not counted as a recovered 1.22 omission.'})

archives=[]
for path in archive_inputs:
    dst=ARCHIVE/path.name
    if path.resolve()!=dst.resolve():shutil.copyfile(path,dst)
    archives.append({'source_location':str(path),'archived_path':dst.relative_to(STAGE).as_posix(),'sha256':sha(dst)})
def hash_scope(path):
    if path.startswith('docs/') or pathlib.Path(path).suffix=='.md':return 'documentation'
    return 'implementation_tools_assets_and_original_evidence'
corpus={}
for record in files:
    record['hash_scope']=hash_scope(record['final_target'])
    if record['exists']:corpus[record['final_target']]=record['sha256']
for record in extra:
    record['hash_scope']=hash_scope(record['path']);corpus[record['path']]=record['sha256']
fingerprints={}
for scope in ['documentation','implementation_tools_assets_and_original_evidence']:
    pairs={p:h for p,h in sorted(corpus.items()) if hash_scope(p)==scope}
    fingerprints[scope]={'files':len(pairs),'sha256':hashlib.sha256(json.dumps(pairs,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
fingerprints['algorithm']='SHA-256 of UTF-8 compact JSON {relative_path: sha256}, sorted by path; source and documentation scopes are independent.'
fingerprints['excluded_to_prevent_self_reference']=['docs/migration/1.22-coverage.json','docs/migration/1.22-coverage.md','docs/migration/evidence/** (input archives have independent hashes above)','.git/**','.godot/**','**/__pycache__/**']
summary={'upstream_changed_files':len(changes),'upstream_change_counts':dict(collections.Counter(changes.values())),'stage_classification_rows':len(files),'initial_action_counts':dict(collections.Counter(r['initial_action'] for r in files)),'final_disposition_counts':dict(collections.Counter(r['disposition'] for r in files)),'mapped_incoming_missing':sum(x['kind']=='missing_upstream_target' for x in issues),'unlisted_upstream_changes':sum(x['kind']=='unlisted_upstream_change' for x in issues),'review_rows_without_owner':sum(x['kind']=='unresolved_review' for x in issues),'final_relocations':len(retargets),'mapping_entries':len(mapping),'recovery_fixture_entries':len(fixture),'extra_identity_fixture_entries':len(set(fixture)-set(mapping)),'method_counts':dict(method_counts),'extra_framework_or_migration_files':len(extra),'issues':len(issues)}
doc={'schema':1,'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'coverage_complete' if not issues else 'coverage_with_open_findings','baselines':REFS,'stage_snapshot':str(STAGE),'scope':'File disposition coverage and explicit method replacement/inheritance audit, not a claim of semantic equivalence or native release acceptance. Original recovery evidence is never rewritten.','summary':summary,'fingerprints':fingerprints,'original_evidence_integrity':original_evidence_integrity,'limitations':['Method presence is a structural inventory; unchanged names alone do not establish behavior. Semantic contracts are established by the migration tests and owner reviews referenced separately.','Recovery source blobs and original package/bytecode evidence remain anchored at 2af1f49bd; mapped or intentionally edited final bytes have separate SHA-256 identities.','Owner ledgers describe decisions at their recorded snapshots. recorded_sha256_matches_final explicitly shows later edits; the top-level file sha256 is the current snapshot identity.','This snapshot does not run Godot, real saves, external HTTP services or native SDKs. The parent owns the final isolated full-suite checkpoint.','Native Android templates/real SDK identified reward bridge and device acceptance remain outside completed local migration acceptance.'],'input_evidence_archives':archives,'retargets':retargets,'files':files,'method_inventory':method_files,'method_exceptions':exceptions,'pending_method_resolutions':pending_resolutions,'additional_exceptions_found_by_full_scan':new_exceptions,'retired_and_replaced_call_audit':call_audit,'extra_framework_or_migration_files':extra,'open_findings':issues}
(OUT/'1.22-coverage.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
md=f'''# 1.22 文件与方法覆盖审计

该文件是迁移覆盖清单的说明，完整逐项记录见 [1.22-coverage.json](1.22-coverage.json)。生成时间：{doc['generated_utc']}。

- 固定比较：原版 `{REFS['original_181']}` → 1.22 `{REFS['recovery_122']}`；框架基线 `{REFS['framework_181']}`。
- 上游变更 {len(changes):,} 项：新增 {summary['upstream_change_counts'].get('A',0):,}、修改 {summary['upstream_change_counts'].get('M',0):,}、删除 {summary['upstream_change_counts'].get('D',0):,}。每项都在 {len(files):,} 行分类表中，记录最终目标、处置、理由、原始 Git blob 与最终 SHA-256。
- {len(retargets)} 处后续目录调整已按最终映射归档：4 个 shader/UID 迁入框架，MouseSelector 的脚本/UID 迁入领域层。有效上游目标缺失 {summary['mapped_incoming_missing']} 项；映射与恢复校验器清单差异 {len(map_mismatch)} 项。
- {original_evidence_groups['.autoconverted']} 份原始 `.gdc` 与 {original_evidence_groups['docs']} 份 `docs/recovery/1.22.0` 原恢复证据重新计算 Git blob 身份，与固定 1.22 提交的差异为 {len(original_evidence_mismatches)} 项；最终修改文件的身份另行记录。
- 重新扫描全部 {method_counts['scripts']:,} 个上游 `.gd`（包括工具及未由字节码恢复的插件），共 {method_counts['methods']:,} 个顶层方法：{method_counts['direct']:,} 个在目标中直接同名存在，{method_counts['inherited']} 个由基类提供，{method_counts['replaced']} 个明确替代，{method_counts['retired_with_transaction_replacement']} 个以事务接口替代后明确退休。原恢复证据的 853 个字节码来源脚本是另一口径，不与这里的全仓库脚本数混用。
- 原 pending 清单逐项复核；`UIManager._unhandled_input` 已恢复直接实现。完整扫描另补入 `StreakReviveFlow._wait_page_hidden` 的取消语义替代，以及 GameState 的 4 个旧 live 结算私有方法向候选 ProgressState 的迁移；所有退休/替代符号另扫描当前生产调用点，区分合法替代类调用与 Splash/Content/MCP 的无关同名方法。
- 初始导入表之外的 {len(extra)} 个框架/迁移新增文件单独清点，不误算为上游遗漏。输入 ledgers、map 与初始报告的副本保存在 [evidence/1.22](evidence/1.22/)，无需依赖临时目录复核处置依据。

## 当前待处理发现

{json.dumps(issues,ensure_ascii=False,indent=2) if issues else '无未覆盖上游文件、无未解释的方法移除、无退休/替代接口残留调用。'}

## 结论边界

这是文件、路径和接口去向的完整覆盖审计，并不把同名方法存在视为行为等价证明。业务语义由相应真实页面、故障注入、候选事务、题库和发布合同测试证明；最终全套测试由主任务另行冻结并归档。原始 1.22 恢复报告与包/字节码指纹没有重写，最终修改的哈希在本清单独立记录。

真实原生 SDK、Android 定制模板、设备广告/支付/认证与线上服务没有完成验收；详细限制见 [1.22-platform-validation.md](1.22-platform-validation.md)。

## 重新生成

`python3 docs/migration/build_coverage.py --project . --repo /path/to/git/repository`

默认读取已经归档的报告、映射和 ledgers，原方法从上述固定 Git blob 读取，不依赖原源码临时快照。迁移进行期间可增加 `--inputs /tmp` 刷新输入归档。只会写 `docs/migration/`，不会运行产品或改写测试。

`fingerprints.implementation_tools_assets_and_original_evidence` 与 `fingerprints.documentation` 分开计算；后续文档更新不会改变实现指纹。清单自身、此说明及已独立记录哈希的输入副本不参与 corpus 指纹，避免自引用。Owner ledger 的旧哈希可能早于最终小修，逐项 `recorded_sha256_matches_final` 明确区分，最终身份以文件行的 `sha256` 为准。
'''
(OUT/'1.22-coverage.md').write_text(md)
print(json.dumps({'output':str(OUT/'1.22-coverage.json'),'summary':summary,'open_findings':issues},ensure_ascii=False,indent=2))
