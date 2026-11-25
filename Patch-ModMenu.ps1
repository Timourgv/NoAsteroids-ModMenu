# ============================================================================
#  No Asteroids - Mod Menu Patch (v2.2.0)
#  - Installs an in-game MOD MENU (HOME key): price multiplier x2/x4/x6/x8/x16/OFF,
#    infinite credits toggle, settings remembered between sessions.
#  - v2.1.0: hotkey moved from F8 (game uses it) to HOME; fixed menu clicks
#    (capture-phase bug); panel now forced on top; live sale-payout readout.
#  - v2.2.0: NEW menu rows: tool upgrade level cap x1/x2/x4 (lifts the four tool
#    upgrade rows HIT POWER / TEMPO / SWEEP / LUCK past level 20) and a
#    Lance+Slicer fire-rate 10/s toggle, plus a live tool stats readout.
#  - Rebuilds resources\app.asar from the untouched app.asar.bak by injecting
#    a small payload + two hooks into the game bundle. Steam assets and the
#  vanilla backup are preserved.
#  - Windows PowerShell 5.1 compatible. Run from the game root, game CLOSED.
#
#  Parameters:
#    -DefaultMultiplier 0|2|4|6|8|16   0 = auto (read money-multiplier.txt,
#                                      fallback x4). Sets the menu's saved
#                                      startup setting only; change any time in-game.
#    -RestoreVanilla                  copy app.asar.bak back over app.asar.
# ============================================================================
param(
  [int]$DefaultMultiplier = 0,
  [switch]$RestoreVanilla
)
$ErrorActionPreference = 'Stop'
$script:Log = @()
function Log([string]$m) { $script:Log += $m; Write-Host $m }

$GameDir = $PSScriptRoot
$LogPath = Join-Path $GameDir 'modmenu-patch-log.txt'
$ResDir  = Join-Path $GameDir 'resources'
$Asar    = Join-Path $ResDir  'app.asar'
$Bak     = $Asar + '.bak'

try {
  Log ('No Asteroids ModMenu patch ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Log ('GameDir: ' + $GameDir)

  # --------------------------------------------------------------------------
  # 0. basic checks
  # --------------------------------------------------------------------------
  if (-not (Test-Path $Bak)) { throw "Vanilla backup not found: $Bak. Do not run this from inside an archive; extract to the real game folder." }

  $proc = Get-Process -Name 'No Asteroids*' -ErrorAction SilentlyContinue
  if ($proc) { throw 'The game appears to be running. Close it first (RESULT=GAME_RUNNING).' }

  $qual = $null
  try { $qual = (Split-Path -Path $GameDir -Qualifier -ErrorAction Stop) } catch { }
  if ($qual) {
    $drive = $qual.TrimEnd(':')
    $free = (Get-PSDrive -Name $drive -ErrorAction SilentlyContinue).Free
    if ($free -and $free -lt 2GB) { throw ('Not enough free space on drive ' + $qual + ' (need ~2 GB, have ' + [math]::Round($free / 1MB) + ' MB free). RESULT=NO_SPACE') }
  }

  # --------------------------------------------------------------------------
  # 1. restore mode
  # --------------------------------------------------------------------------
  if ($RestoreVanilla) {
    Copy-Item -LiteralPath $Bak -Destination $Asar -Force
    $state = Join-Path $GameDir 'modmenu-state.txt'
    if (Test-Path $state) { Remove-Item -LiteralPath $state -Force }
    Log 'Restored vanilla app.asar from backup.'
    Log 'RESULT=RESTORED'
    Set-Content -LiteralPath $LogPath -Value $script:Log -Encoding UTF8
    Write-Host 'Log written.'
    return
  }

  # --------------------------------------------------------------------------
  # 2. default multiplier (menu startup setting only)
  # --------------------------------------------------------------------------
  $defMult = 4
  if ($DefaultMultiplier -in 2, 4, 6, 8, 16) {
    $defMult = $DefaultMultiplier
  }
  elseif ($DefaultMultiplier -eq 0) {
    $mmFile = Join-Path $GameDir 'money-multiplier.txt'
    if (Test-Path $mmFile) {
      $mmRaw = [System.IO.File]::ReadAllText($mmFile)
      Log ('Read money-multiplier.txt: ' + $mmRaw.Trim())
      if ($mmRaw -match '(?i)\b(off|vanilla|none|0)\b') { $defMult = 0 }
      elseif ($mmRaw -match '(\d+)') {
        $p = [int]$Matches[1]
        if ($p -in 2, 4, 6, 8, 16) { $defMult = $p }
        else { Log ('Unrecognized multiplier value ' + $p + ', using x4.') }
      }
    }
  }
  else {
    Log ('Unrecognized -DefaultMultiplier ' + $DefaultMultiplier + ', using x4.')
  }
  Log ('Menu startup multiplier: ' + $defMult)

  # --------------------------------------------------------------------------
  # 3. read asar header from the untouched backup
  # --------------------------------------------------------------------------
  Log 'Reading asar header from app.asar.bak ...'
  $fs = [System.IO.File]::OpenRead($Bak)
  $prefix = New-Object byte[] 16
  $read = 0
  while ($read -lt 16) {
    $n = $fs.Read($prefix, $read, 16 - $read)
    if ($n -le 0) { throw 'Unexpected end of file while reading asar prefix.' }
    $read += $n
  }
  $p0 = [BitConverter]::ToUInt32($prefix, 0)
  $pL = [BitConverter]::ToUInt32($prefix, 4)
  $pP = [BitConverter]::ToUInt32($prefix, 8)
  $pJ = [BitConverter]::ToUInt32($prefix, 12)
  Log ('prefix: p0=' + $p0 + ' L=' + $pL + ' P=' + $pP + ' J=' + $pJ)
  if ($p0 -ne 4) { throw 'Unexpected asar pickle prefix (p0=' + $p0 + '). Not the expected Electron asar layout. RESULT=LAYOUT_MISMATCH' }
  $padN = (4 - ((16 + $pJ) % 4)) % 4
  $D = 16 + $pJ + $padN
  if ($pP -ne (4 + $pJ + $padN)) { throw 'asar prefix fields inconsistent (P). RESULT=LAYOUT_MISMATCH' }
  if ($pL -ne ($pP + 4)) { throw 'asar prefix fields inconsistent (L). RESULT=LAYOUT_MISMATCH' }
  Log ('jsonLen=' + $pJ + ' pad=' + $padN + ' dataBase=' + $D)

  $jsonBytes = New-Object byte[] $pJ
  $read = 0
  while ($read -lt $pJ) {
    $n = $fs.Read($jsonBytes, $read, $pJ - $read)
    if ($n -le 0) { throw 'Unexpected EOF while reading header JSON.' }
    $read += $n
  }
  $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
  if ($json.Length -lt 100) { throw 'Header JSON implausibly short. RESULT=LAYOUT_MISMATCH' }

  # --------------------------------------------------------------------------
  # 4. locate the game bundle entry (identified by known vanilla size + hash)
  # --------------------------------------------------------------------------
  $entryRe = New-Object System.Text.RegularExpressions.Regex ('"size":(6437795),"offset":"(\d+)","integrity":\{"algorithm":"(\w+)","hash":"([0-9a-f]{64})","blockSize":(\d+),"blocks":\[([^\]]*)\]\}')
  $em = $entryRe.Match($json)
  if (-not $em.Success) { throw 'Could not find vanilla bundle entry in asar header (size 6437795). The game version differs from the supported one. RESULT=BUNDLE_NOT_FOUND' }
  $bundleRel  = [long]$em.Groups[2].Value
  $oldSize    = [long]$em.Groups[1].Value
  $vanillaSha = $em.Groups[4].Value
  $blockSize  = [long]$em.Groups[5].Value
  $S_abs = $D + $bundleRel
  Log ('bundle rel=' + $bundleRel + ' size=' + $oldSize + ' blockSize=' + $blockSize + ' abs=' + $S_abs)

  # --------------------------------------------------------------------------
  # 5. extract the vanilla bundle from the backup
  # --------------------------------------------------------------------------
  Log 'Extracting vanilla bundle ...'
  $fs.Position = $S_abs
  $oldBundle = New-Object byte[] $oldSize
  $read = 0
  while ($read -lt $oldSize) {
    $n = $fs.Read($oldBundle, $read, [int]($oldSize - $read))
    if ($n -le 0) { throw 'Unexpected EOF while reading bundle.' }
    $read += $n
  }
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  $oldHex = ([BitConverter]::ToString($sha256.ComputeHash($oldBundle)) -replace '-', '').ToLower()
  if ($oldHex -ne $vanillaSha) {
    $fs.Close()
    throw ('Bundle content does not match expected vanilla hash (expected ' + $vanillaSha + ', got ' + $oldHex + '). RESULT=NOT_VANILLA')
  }
  Log ('Vanilla bundle verified (' + $oldHex + ').')

  # --------------------------------------------------------------------------
  # 6. patch the bundle text
  # --------------------------------------------------------------------------
  $bundle = [System.Text.Encoding]::UTF8.GetString($oldBundle)

  $payloadTemplate = @'
;(function(){
'use strict';
var MKEY='NoAsteroidsModMenu';
var DEF={mult:__NA_DEF_MULT__,money:false,capMult:1,toolRate:false};
function loadCfg(){var c={mult:DEF.mult,money:DEF.money,capMult:DEF.capMult,toolRate:DEF.toolRate};try{var s=localStorage.getItem(MKEY);if(s){var p=JSON.parse(s);if(p){if(typeof p.mult==='number')c.mult=p.mult;if(typeof p.money==='boolean')c.money=p.money;if(p.capMult===1||p.capMult===2||p.capMult===4)c.capMult=p.capMult;if(typeof p.toolRate==='boolean')c.toolRate=p.toolRate}}}catch(e){}return c}
function saveCfg(c){try{localStorage.setItem(MKEY,JSON.stringify({mult:c.mult,money:c.money,capMult:c.capMult,toolRate:c.toolRate}))}catch(e){}}
var cfg=loadCfg();
var NA=window.__NA||(window.__NA={});
NA.money=cfg.money;
NA.floor=99999999;
NA.version='2.2.0';
var MULTS={0:[.75,.6],2:[1.5,1.2],4:[3,2.4],6:[4.5,3.6],8:[6,4.8],16:[12,9.6]};
function applyMult(){var t=MULTS[cfg.mult]||MULTS[4];wo.lo=t[0];wo.span=t[1]}
NA.setMult=function(m){if(m===0||m===2||m===4||m===6||m===8||m===16){cfg.mult=m;saveCfg(cfg);applyMult();updateUI()}};
NA.setMoney=function(on){cfg.money=!!on;NA.money=cfg.money;saveCfg(cfg);updateUI()};
function toolById(id){for(var i=0;i<ui.length;i++){if(ui[i]&&ui[i].id===id)return ui[i]}return null}
function trackById(id){for(var i=0;i<Oi.length;i++){if(Oi[i]&&Oi[i].id===id)return Oi[i]}return null}
function luckTrack(){for(var i=0;i<Xa.length;i++){if(Xa[i]&&Xa[i].id==='luck')return Xa[i]}return null}
function upsRate(){var s=NA.state;return(s&&s.toolUps&&typeof s.toolUps.rate==='number')?s.toolUps.rate:0}
function ratePer(){var t=trackById('rate');return(t&&typeof t.per==='number')?t.per:.02}
function applyCaps(){try{var cap=20*((cfg.capMult===2||cfg.capMult===4)?cfg.capMult:1),ids=['power','rate','radius'],i;for(i=0;i<ids.length;i++){var t=trackById(ids[i]);if(t)t.max=cap}var lk=luckTrack();if(lk)lk.max=cap}catch(e){}}
NA.setCaps=function(cm){if(cm===1||cm===2||cm===4){cfg.capMult=cm;saveCfg(cfg);applyCaps();updateUI()}};
function applyToolRate(){try{var ln=toolById('lance'),sl=toolById('slicer');if(cfg.toolRate){var want=10/(1+ratePer()*upsRate());if(ln)ln.rate=want;if(sl)sl.rate=want;if(typeof hi==='object'&&hi)hi.min=.05}else{if(ln)ln.rate=.7;if(sl)sl.rate=.5;if(typeof hi==='object'&&hi)hi.min=.18}if(NA.app&&NA.app.state&&typeof NA.app.shiftStats==='function'){try{NA.app.stats=NA.app.shiftStats()}catch(e){}}}catch(e){}}
NA.setToolRate=function(on){cfg.toolRate=!!on;saveCfg(cfg);applyToolRate();updateUI()};
function maintain(){if(!cfg.toolRate)return;var want=10/(1+ratePer()*upsRate()),ln=toolById('lance');if(!ln)return;if(Math.abs(ln.rate-want)>1e-9)applyToolRate()}
NA.applyMoney=function(state){if(state)NA.state=state;if(NA.money&&state&&typeof state.credits==='number'&&state.credits<NA.floor){state.credits=NA.floor}try{maintain()}catch(e){}};
NA.hook=function(app,state){NA.app=app;NA.applyMoney(state)};
function rateNum(t){if(!t)return 0;return Math.round(t.rate*(1+ratePer()*upsRate())*10)/10}
try{applyMult()}catch(e){}
try{applyCaps()}catch(e){}
if(cfg.toolRate){try{applyToolRate()}catch(e){}}
var panel=null;
function el(tag,text,cls){var e=document.createElement(tag);if(text!==null)e.textContent=text;if(cls)e.setAttribute('class',cls);return e}
function btn(label,cls,onclick){var b=el('button',label,cls);b.setAttribute('type','button');b.addEventListener('click',function(ev){ev.stopPropagation();onclick()});return b}
function stop(ev){ev.stopPropagation()}
function buildUI(){
  if(panel)return;
  var root=el('div',null,'namenu-root');
  root.addEventListener('mousedown',stop);
  root.addEventListener('mouseup',stop);
  root.addEventListener('click',stop);
  root.addEventListener('wheel',stop);
  root.addEventListener('contextmenu',stop);
  root.addEventListener('dblclick',stop);
  var head=el('div',null,'namenu-head');
  head.appendChild(el('span','MOD MENU','namenu-title'));
  var closeB=btn('x','namenu-x',function(){toggleUI(false)});
  head.appendChild(closeB);
  root.appendChild(head);
  var body=el('div',null,'namenu-body');
  var rowL=el('div',null,'namenu-row');rowL.appendChild(el('div','Price multiplier','namenu-label'));
  var rowLB=el('div',null,'namenu-opts');rowLB.id='namenu-mult';
  [0,2,4,6,8,16].forEach(function(m){rowLB.appendChild(btn(m===0?'OFF':'x'+m,'namenu-btn',function(){NA.setMult(m)}))});
  rowL.appendChild(rowLB);body.appendChild(rowL);
  var rowM=el('div',null,'namenu-row');rowM.appendChild(el('div','Infinite credits','namenu-label'));
  var mOff=btn('OFF','namenu-btn',function(){NA.setMoney(false)});mOff.id='namenu-money-off';
  var mOn=btn('ON','namenu-btn',function(){NA.setMoney(true)});mOn.id='namenu-money-on';
  rowM.appendChild(mOff);rowM.appendChild(mOn);
  body.appendChild(rowM);
  var rowC=el('div',null,'namenu-row');rowC.appendChild(el('div','Tool upgrade level cap','namenu-label'));
  var rowCB=el('div',null,'namenu-opts');rowCB.id='namenu-cap';
  [1,2,4].forEach(function(cm){rowCB.appendChild(btn('x'+cm,'namenu-btn',function(){NA.setCaps(cm)}))});
  rowC.appendChild(rowCB);body.appendChild(rowC);
  var rowT=el('div',null,'namenu-row');rowT.appendChild(el('div','Lance+Slicer fire rate 10/s','namenu-label'));
  var tOff=btn('OFF','namenu-btn',function(){NA.setToolRate(false)});tOff.id='namenu-tr-off';
  var tOn=btn('ON','namenu-btn',function(){NA.setToolRate(true)});tOn.id='namenu-tr-on';
  rowT.appendChild(tOff);rowT.appendChild(tOn);
  body.appendChild(rowT);
  var rowX=el('div',null,'namenu-row');rowX.appendChild(el('div','Tool stats','namenu-label'));
  var xs=el('div',null,'namenu-readout');xs.id='namenu-tools';rowX.appendChild(xs);
  body.appendChild(rowX);
  var rowP=el('div',null,'namenu-row');rowP.appendChild(el('div','Today sale payout / unit','namenu-label'));
  var pr=el('div',null,'namenu-prices');pr.id='namenu-prices';rowP.appendChild(pr);
  body.appendChild(rowP);
  body.appendChild(el('div','Home: show/hide  -  drag title to move','namenu-hint'));
  root.appendChild(body);
  var style=el('style');
  style.textContent='.namenu-root{position:fixed;top:12px;right:12px;z-index:2147483647;background:rgba(12,14,18,.92);color:#e8e6e0;font:12px/1.45 monospace;border:1px solid #3c4552;border-radius:6px;min-width:210px;user-select:none;pointer-events:auto;box-shadow:0 8px 30px rgba(0,0,0,.5)}'+
  '.namenu-head{display:flex;justify-content:space-between;align-items:center;padding:6px 8px;cursor:move;background:rgba(35,42,52,.9);border-bottom:1px solid #3c4552;border-radius:6px 6px 0 0}'+
  '.namenu-title{font-weight:700;letter-spacing:1px}'+
  '.namenu-x{background:none;border:0;color:#9aa4b0;font:inherit;cursor:pointer}.namenu-x:hover{color:#fff}'+
  '.namenu-body{padding:8px}'+
  '.namenu-row{margin:6px 0}.namenu-label{margin-bottom:4px;color:#9aa4b0}'+
  '.namenu-opts{display:flex;gap:4px}'+
  '.namenu-btn{background:#232a34;border:1px solid #3c4552;color:#e8e6e0;font:11px monospace;padding:3px 8px;border-radius:4px;cursor:pointer}'+
  '.namenu-btn:hover{border-color:#7a8a9a}'+
  '.namenu-btn.na-on{background:#2f6f4f;border-color:#4fae7d;color:#fff}'+
  '.namenu-hint{margin-top:8px;color:#6d7683;font-size:10px}'+
  '.namenu-prices{color:#7ec98f}'+
  '.namenu-readout{color:#9fb3c8;white-space:pre-line}';
  root.appendChild(style);
  document.body.appendChild(root);panel=root;
  var dragging=null;
  head.addEventListener('mousedown',function(ev){dragging={dx:ev.clientX-root.offsetLeft,dy:ev.clientY-root.offsetTop};ev.preventDefault()});
  window.addEventListener('mousemove',function(ev){if(dragging){root.style.left=Math.max(0,Math.min(window.innerWidth-root.offsetWidth,ev.clientX-dragging.dx))+'px';root.style.top=Math.max(0,Math.min(window.innerHeight-root.offsetHeight,ev.clientY-dragging.dy))+'px';root.style.right='auto'}});
  window.addEventListener('mouseup',function(){dragging=null});
  updateUI();
}
function updateUI(){
  if(!panel)return;
  var multWrap=document.getElementById('namenu-mult');
  if(multWrap){Array.prototype.forEach.call(multWrap.children,function(b,i){var m=[0,2,4,6,8,16][i];if(cfg.mult===m)b.setAttribute('class','namenu-btn na-on');else b.setAttribute('class','namenu-btn')})}
  var offB=document.getElementById('namenu-money-off'),onB=document.getElementById('namenu-money-on');
  if(offB&&onB){offB.setAttribute('class','namenu-btn'+(cfg.money?'':' na-on'));onB.setAttribute('class','namenu-btn'+(cfg.money?' na-on':''))}
  var capWrap=document.getElementById('namenu-cap');
  if(capWrap){Array.prototype.forEach.call(capWrap.children,function(b,i){var cm=[1,2,4][i];if(cfg.capMult===cm)b.setAttribute('class','namenu-btn na-on');else b.setAttribute('class','namenu-btn')})}
  var trOff=document.getElementById('namenu-tr-off'),trOn=document.getElementById('namenu-tr-on');
  if(trOff&&trOn){trOff.setAttribute('class','namenu-btn'+(cfg.toolRate?'':' na-on'));trOn.setAttribute('class','namenu-btn'+(cfg.toolRate?' na-on':''))}
  var tl=document.getElementById('namenu-tools');
  if(tl){var txt='(enter the hub to load the save)';
    if(NA.state&&NA.state.toolUps){
      var s=NA.state,tu=s.toolUps||{},lk=(s.skills&&typeof s.skills.luck==='number')?s.skills.luck:0;
      var pT=trackById('power'),rT=trackById('rate'),sT=trackById('radius');
      var capNow=(pT&&typeof pT.max==='number')?pT.max:20;
      var pp=(pT&&typeof pT.per==='number')?pT.per*100:5,tp=(rT&&typeof rT.per==='number')?rT.per*100:2,sp=(sT&&typeof sT.per==='number')?sT.per*100:1;
      var lp=(typeof Va!=='undefined'&&Va&&typeof Va.luck==='number')?Va.luck*100:1.25;
      var lv='levels '+(tu.power||0)+'/'+(tu.rate||0)+'/'+(tu.radius||0)+'/'+lk+'  cap '+capNow;
      var fx='HIT +'+Math.round(pp*(tu.power||0))+'%  TEMPO +'+Math.round(tp*(tu.rate||0))+'%  SWEEP +'+Math.round(sp*(tu.radius||0))+'%  LUCK +'+Math.round(lp*lk)+'%';
      var lm=rateNum(toolById('lance')),sm=rateNum(toolById('slicer'));
      var rt='Lance '+lm+'/s  Slicer '+sm+'/s';
      txt=lv+'\n'+fx+'\n'+rt}
    tl.textContent=txt}
  var pr=document.getElementById('namenu-prices');
  if(pr){var ptxt='(open a station screen to load the day)';
    if(NA.state&&typeof NA.state.day==='number'){var d=NA.state.day;
      ptxt='day '+d+': ice '+To(d,l.ice)+' / gold '+To(d,l.gold)+' credits (base '+So[l.ice]+' / '+So[l.gold]+')'}
    pr.textContent=ptxt}
}
function toggleUI(force){
  var show=(typeof force==='boolean')?force:!(panel&&panel.style.display!=='none');
  if(show){buildUI();document.body.appendChild(panel);panel.style.display='';try{if(document.pointerLockElement)document.exitPointerLock()}catch(e){}}
  else if(panel){panel.style.display='none'}
}
setInterval(function(){if(panel&&panel.style.display!=='none'&&panel.parentNode===document.body&&document.body.lastElementChild!==panel){document.body.appendChild(panel)}},1500);
window.addEventListener('keydown',function(ev){var open=panel&&panel.style.display!=='none';if(ev.code==='Home'&&!ev.ctrlKey&&!ev.altKey&&!ev.shiftKey&&!ev.metaKey){ev.preventDefault();ev.stopPropagation();toggleUI()}else if(ev.key==='Escape'&&open){ev.preventDefault();ev.stopPropagation();toggleUI(false)}},true);
})();
'@
  $payload = $payloadTemplate.Replace('__NA_DEF_MULT__', [string]$defMult)

  $A = 'function Eo(e,t){return So[t]?To(e,t)/So[t]-1:0}'
  $B = 'refreshHub(){let e=this.state;'
  $Bn = 'refreshHub(){let e=this.state;window.__NA&&window.__NA.hook(this,e);'
  $C = 'let u=Math.floor(this.data.state.credits);u!==this.cash&&(this.cash=u,this.cashEl.innerHTML=this.money(u))'
  $Cn = 'let u=(window.__NA&&window.__NA.applyMoney(this.data.state),Math.floor(this.data.state.credits));u!==this.cash&&(this.cash=u,this.cashEl.innerHTML=this.money(u))'

  foreach ($anchor in @($A, $B, $C)) {
    $cnt = [regex]::Matches($bundle, [regex]::Escape($anchor)).Count
    if ($cnt -ne 1) { throw ('Anchor expected once, found ' + $cnt + ': ' + $anchor.Substring(0, [Math]::Min(40, $anchor.Length)) + ' RESULT=ANCHOR_MISMATCH') }
  }
  if ($bundle.Contains('__NA_DEF_MULT__')) { throw 'Internal placeholder error. RESULT=INTERNAL' }

  $bundle = $bundle.Replace($A, $A + $payload)
  $bundle = $bundle.Replace($B, $Bn)
  $bundle = $bundle.Replace($C, $Cn)

  $newBundle = [System.Text.Encoding]::UTF8.GetBytes($bundle)
  $newSize = $newBundle.Length
  $delta = $newSize - $oldSize
  Log ('Patched bundle: ' + $oldSize + ' -> ' + $newSize + ' bytes (delta ' + $delta + ').')

  # --------------------------------------------------------------------------
  # 7. compute new bundle integrity
  # --------------------------------------------------------------------------
  $newHex = ([BitConverter]::ToString($sha256.ComputeHash($newBundle)) -replace '-', '').ToLower()
  $blocks = New-Object System.Collections.Generic.List[string]
  $pos = [long]0
  while ($pos -lt $newSize) {
    $len = [int][Math]::Min($blockSize, $newSize - $pos)
    $chunk = New-Object byte[] $len
    [Array]::Copy($newBundle, $pos, $chunk, 0, $len)
    $blocks.Add((([BitConverter]::ToString($sha256.ComputeHash($chunk)) -replace '-', '').ToLower()))
    $pos += $len
  }
  $blocksJson = ($blocks | ForEach-Object { '"' + $_ + '"' }) -join ','

  # --------------------------------------------------------------------------
  # 8. rebuild the asar header
  # --------------------------------------------------------------------------
  # Offsets are RELATIVE to the data base, and the physical rebuild below writes
  # [new prefix+json+pad][pre-region][new bundle][tail]: every file keeps its
  # RELATIVE offset; only files AFTER the bundle shift by delta. J may change
  # when offset digit counts change - that moves the data base, but entry
  # offsets are unaffected by it, so one pass suffices.
  Log 'Rebuilding asar header ...'
  $offsetRe = New-Object System.Text.RegularExpressions.Regex ('"offset":"(\d+)"')
  # 8a. shift offsets of entries that live after the bundle
  $ev = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $r = [long]$m.Groups[1].Value
    if ($r -gt $bundleRel) { return '"offset":"' + ($r + $delta) + '"' }
    return $m.Value
  }
  $h = $offsetRe.Replace($json, $ev)

  # 8b. replace the bundle entry (size, hash, blocks; offset unchanged)
  $em2 = $entryRe.Match($h)
  if (-not $em2.Success) { throw 'Lost bundle entry while rewriting header. RESULT=INTERNAL' }
  $newEntry = '"size":' + $newSize + ',"offset":"' + $bundleRel + '","integrity":{"algorithm":"SHA256","hash":"' + $newHex + '","blockSize":' + $blockSize + ',"blocks":[' + $blocksJson + ']}'
  $h = $h.Substring(0, $em2.Index) + $newEntry + $h.Substring($em2.Index + $em2.Length)

  $Jnew = [System.Text.Encoding]::UTF8.GetByteCount($h)
  $padN2 = (4 - ((16 + $Jnew) % 4)) % 4
  $Dnew = 16 + $Jnew + $padN2
  Log ('Header rebuilt: J ' + $pJ + ' -> ' + $Jnew + ', dataBase ' + $D + ' -> ' + $Dnew + '.')
  if ($h -eq $null) { throw 'Internal error. RESULT=INTERNAL' }
  $Lnew = 8 + $Jnew + $padN2
  $Pnew = 4 + $Jnew + $padN2

  # --------------------------------------------------------------------------
  # 9. write the new asar (streams; ~500 MB copy, takes a few minutes)
  # --------------------------------------------------------------------------
  Log ('Writing new app.asar (this copies ~' + [math]::Round(($fs.Length - $S_abs) / 1MB) + ' MB, please wait) ...')
  $Tmp = $Asar + '.newmenu'
  if (Test-Path $Tmp) { Remove-Item -LiteralPath $Tmp -Force }

  $prefixNew = New-Object byte[] 16
  [Array]::Copy([BitConverter]::GetBytes([UInt32]4), 0, $prefixNew, 0, 4)
  [Array]::Copy([BitConverter]::GetBytes([UInt32]$Lnew), 0, $prefixNew, 4, 4)
  [Array]::Copy([BitConverter]::GetBytes([UInt32]$Pnew), 0, $prefixNew, 8, 4)
  [Array]::Copy([BitConverter]::GetBytes([UInt32]$Jnew), 0, $prefixNew, 12, 4)

  $out = [System.IO.File]::Create($Tmp)
  $out.Write($prefixNew, 0, 16)
  $jsonNew = [System.Text.Encoding]::UTF8.GetBytes($h)
  $out.Write($jsonNew, 0, $jsonNew.Length)
  if ($padN2 -gt 0) { $out.Write((New-Object byte[] $padN2), 0, $padN2) }

  $bufSize = 4MB
  $buf = New-Object byte[] $bufSize
  function CopyRange($src, $dst, [long]$start, [long]$count, $buf, [int]$bufSize) {
    $src.Position = $start
    $left = $count
    while ($left -gt 0) {
      $take = [int][Math]::Min($bufSize, $left)
      $n = $src.Read($buf, 0, $take)
      if ($n -le 0) { throw 'Unexpected EOF while copying asar data.' }
      $dst.Write($buf, 0, $n)
      $left -= $n
    }
  }
  CopyRange $fs $out $D ($S_abs - $D) $buf $bufSize
  $out.Write($newBundle, 0, $newSize)
  CopyRange $fs $out ($S_abs + $oldSize) ($fs.Length - ($S_abs + $oldSize)) $buf $bufSize
  $out.Flush()
  $out.Close()
  $expectedLen = 16 + $Jnew + $padN2 + ($S_abs - $D) + $newSize + ($fs.Length - ($S_abs + $oldSize))
  $actualLen = (Get-Item -LiteralPath $Tmp).Length
  if ($actualLen -ne $expectedLen) {
    $fs.Close()
    Remove-Item -LiteralPath $Tmp -Force
    throw ('New asar has wrong length: ' + $actualLen + ' expected ' + $expectedLen + '. RESULT=VERIFY_FAILED')
  }

  # --------------------------------------------------------------------------
  # 10. verify the new archive before touching app.asar
  # --------------------------------------------------------------------------
  Log 'Verifying new archive ...'
  $vf = [System.IO.File]::OpenRead($Tmp)
  $vp = New-Object byte[] 16
  $vr = $vf.Read($vp, 0, 16)
  $vJ = [BitConverter]::ToUInt32($vp, 12)
  $vjBytes = New-Object byte[] $vJ
  $vr = 0
  while ($vr -lt $vJ) {
    $n = $vf.Read($vjBytes, $vr, $vJ - $vr)
    if ($n -le 0) { throw 'Unexpected EOF in verification. RESULT=VERIFY_FAILED' }
    $vr += $n
  }
  $vj = [System.Text.Encoding]::UTF8.GetString($vjBytes)
  if ($vj -ne $h) { $vf.Close(); $fs.Close(); throw 'Verification: header mismatch. RESULT=VERIFY_FAILED' }
  if ($vj -match '"offset":"-') { $vf.Close(); $fs.Close(); throw 'Verification: negative offset in header. RESULT=VERIFY_FAILED' }
  $entryReV = New-Object System.Text.RegularExpressions.Regex ('"size":' + $newSize + ',"offset":"(\d+)","integrity":\{"algorithm":"(\w+)","hash":"([0-9a-f]{64})","blockSize":(\d+),"blocks":\[([^\]]*)\]\}')
  $ev2 = $entryReV.Match($vj)
  if (-not $ev2.Success) { $vf.Close(); $fs.Close(); throw 'Verification: patched bundle entry missing. RESULT=VERIFY_FAILED' }
  $vRel = [long]$ev2.Groups[1].Value
  $vHash = $ev2.Groups[3].Value
  $vBundle = New-Object byte[] $newSize
  $vf.Position = $Dnew + $vRel
  $vr = 0
  while ($vr -lt $newSize) {
    $n = $vf.Read($vBundle, $vr, [int]($newSize - $vr))
    if ($n -le 0) { throw 'Unexpected EOF in verification. RESULT=VERIFY_FAILED' }
    $vr += $n
  }
  $vHex = ([BitConverter]::ToString($sha256.ComputeHash($vBundle)) -replace '-', '').ToLower()
  if ($vHex -ne $newHex) { $vf.Close(); $fs.Close(); throw 'Verification: patched bundle hash mismatch. RESULT=VERIFY_FAILED' }
  # pre-bundle region must be byte-identical to the backup (same absolute span)
  $preLen = [int][Math]::Min(1048576, $S_abs - $D)
  $preOld = New-Object byte[] $preLen
  $fs.Position = $D
  $rr = 0
  while ($rr -lt $preLen) { $n = $fs.Read($preOld, $rr, $preLen - $rr); $rr += $n }
  $preNew = New-Object byte[] $preLen
  $vf.Position = $Dnew
  $rr = 0
  while ($rr -lt $preLen) { $n = $vf.Read($preNew, $rr, $preLen - $rr); $rr += $n }
  $oldPreHex = ([BitConverter]::ToString($sha256.ComputeHash($preOld)) -replace '-', '').ToLower()
  $newPreHex = ([BitConverter]::ToString($sha256.ComputeHash($preNew)) -replace '-', '').ToLower()
  if ($oldPreHex -ne $newPreHex) { $vf.Close(); $fs.Close(); throw 'Verification: pre-bundle region differs. RESULT=VERIFY_FAILED' }
  # verify every block hash of the new bundle
  $pos = [long]0
  $bi = 0
  while ($pos -lt $newSize) {
    $len = [int][Math]::Min($blockSize, $newSize - $pos)
    $chunk = New-Object byte[] $len
    [Array]::Copy($vBundle, $pos, $chunk, 0, $len)
    $bh = ([BitConverter]::ToString($sha256.ComputeHash($chunk)) -replace '-', '').ToLower()
    if ($bh -ne $blocks[$bi]) { $vf.Close(); $fs.Close(); throw ('Verification: block ' + $bi + ' hash mismatch. RESULT=VERIFY_FAILED') }
    $pos += $len
    $bi++
  }
  $vf.Close()
  $fs.Close()
  Log 'Verification OK (header, bundle, block hashes, pre-region).'

  # --------------------------------------------------------------------------
  # 11. swap in the new asar
  # --------------------------------------------------------------------------
  if (Test-Path $Asar) { Remove-Item -LiteralPath $Asar -Force }
  Move-Item -LiteralPath $Tmp -Destination $Asar
  Log 'app.asar replaced (vanilla backup untouched).'

  # --------------------------------------------------------------------------
  # 12. state file for NMM/Vortex tooling
  # --------------------------------------------------------------------------
  $stateTxt = "installd=" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n" +
              "version=2.2.0`r`n" +
              "result=MENU_OK`r`n" +
              "bundlesha=" + $newHex + "`r`n" +
              "defmult=" + $defMult + "`r`n"
  Set-Content -LiteralPath (Join-Path $GameDir 'modmenu-state.txt') -Value $stateTxt -Encoding ASCII

  if (Test-Path (Join-Path $GameDir 'money4x-patch-log.txt')) {
    Log 'Note: modmenu-patch-log.txt replaces the old money4x log; Patch-Money-Multiplier.ps1 is superseded and can be deleted.'
  }
  Log 'RESULT=MENU_OK'
  Write-Host 'Mod menu installed. Launch the game and press HOME.'
}
catch {
  Log ('ERROR: ' + $_.Exception.Message)
  Log ('RESULT=FAILED')
  Write-Warning $_.Exception.Message
}
finally {
  if ($fs) { try { $fs.Close() } catch {} }
  if ($out -and $out.GetType().Name -eq 'FileStream') { try { $out.Close() } catch {} }
  Set-Content -LiteralPath $LogPath -Value $script:Log -Encoding UTF8
  Write-Host 'Log written.'
}
