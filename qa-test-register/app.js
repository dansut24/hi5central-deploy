"use strict";
const state={tests:[],statuses:[],area:"",search:"",status:"",priority:"",method:"",selected:"",dirty:false};
const el=id=>document.getElementById(id);
function esc(value){return String(value==null?"":value).replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));}
function cls(status){return {"Not run":"notrun","In progress":"progress","Pass":"pass","Fail":"fail","Blocked":"blocked","Smoke checked":"smoke"}[status]||"notrun";}
function count(a,status){return a.filter(x=>x.status===status).length;}
function toast(text){const t=el("toast");t.textContent=text;t.hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>t.hidden=true,4200);}
function areaName(a){return a.replace(/^\d+\s*[·.\-]\s*/,"");}
function allAreas(){return [...new Set(state.tests.map(x=>x.area))];}
function matching(){const q=state.search.toLowerCase();return state.tests.filter(x=>
 (!state.area||x.area===state.area)&&(!state.status||x.status===state.status)&&
 (!state.priority||x.priority===state.priority)&&(!state.method||x.method===state.method)&&
 (!q||[x.id,x.area,x.feature,x.steps,x.expected,x.evidence].join(" ").toLowerCase().includes(q)));}
function totals(){const a=state.tests;return {total:a.length,pass:count(a,"Pass"),fail:count(a,"Fail"),blocked:count(a,"Blocked"),smoke:count(a,"Smoke checked"),progress:count(a,"In progress"),notrun:count(a,"Not run")};}
function renderStats(){
 const t=totals();el("count-total").textContent=t.total;el("count-pass").textContent=t.pass;
 el("count-problem").textContent=t.fail+t.blocked;el("count-open").textContent=t.notrun+t.progress;
 const checked=t.pass+t.fail+t.blocked+t.smoke;
 el("progress-label").textContent=checked+" of "+t.total+" assessed ("+t.smoke+" smoke checks)";
 el("progress-fill").style.width=(t.total?Math.round(100*checked/t.total):0)+"%";
}
function renderAreas(){
 const areas=allAreas();el("area-count").textContent=areas.length;
 const a=state.tests;
 const link=(label,key,items)=>'<button class="area-link '+(state.area===key?"active":"")+'" type="button" data-area="'+esc(key)+'"><span>'+esc(label)+'</span><b>'+count(items,"Pass")+'/'+items.length+'</b></button>';
 el("areas").innerHTML=link("All products","",a)+areas.map(area=>link(areaName(area),area,a.filter(x=>x.area===area))).join("");
}
function renderTests(){
 const items=matching();
 el("list-title").textContent=state.area?areaName(state.area):"All test cases";
 el("list-meta").textContent=items.length+" shown · Choose a test to record its result";
 const html=items.map(t=>'<tr tabindex="0" role="button" aria-label="Open '+esc(t.id)+'" data-id="'+esc(t.id)+'" class="'+(state.selected===t.id?"selected":"")+'">'+
  '<td><strong>'+esc(t.id)+'</strong></td>'+
  '<td><strong>'+esc(t.feature)+'</strong><span class="subtext">'+esc(areaName(t.area))+'</span></td>'+
  '<td><span class="priority '+esc(t.priority.toLowerCase())+'">'+esc(t.priority)+'</span></td>'+
  '<td>'+esc(t.method)+'</td>'+
  '<td><span class="badge '+cls(t.status)+'">'+esc(t.status)+'</span></td><td class="rowarrow">›</td></tr>').join("");
 el("test-list").innerHTML=html;
 el("empty").hidden=items.length>0;
}
function render(){renderStats();renderAreas();renderTests();}
function activeTest(){return state.tests.find(x=>x.id===state.selected);}
function dirtyCheck(){return !state.dirty||window.confirm("You have unsaved changes. Discard them?");}
function closeTest(){if(!dirtyCheck())return;state.selected="";state.dirty=false;el("detail").hidden=true;el("workspace").classList.remove("open");renderTests();}
function selectTest(id){if(id===state.selected)return;if(!dirtyCheck())return;const t=state.tests.find(x=>x.id===id);if(!t)return;state.selected=id;state.dirty=false;el("workspace").classList.add("open");el("detail").hidden=false;renderDetail(t);renderTests();}
function field(label,name,val,kind="input"){
 const tag=kind==="textarea"?'<textarea name="'+name+'" rows="'+(name==="notes"?5:3)+'" maxlength="'+(name==="notes"?"8000":"4000")+'">'+esc(val)+'</textarea>':'<input name="'+name+'" maxlength="'+(name==="environment"?"400":"160")+'" value="'+esc(val)+'">';
 return '<label class="field">'+esc(label)+tag+'</label>';
}
function renderDetail(t){
 const statuses=state.statuses.map(s=>'<option '+(s===t.status?"selected":"")+'>'+esc(s)+'</option>').join("");
 const source=(typeof t.source_url==="string"&&/^https:\/\//.test(t.source_url))?
 '<a class="btn ghost" target="_blank" rel="noopener noreferrer" href="'+esc(t.source_url)+'">Source ↗</a>':"";
 const evidenceLink=(/^https:\/\/[^\s]+$/.test(t.evidence||""))?
 '<p><a target="_blank" rel="noopener noreferrer" style="color:#286ed0;font-size:11px" href="'+esc(t.evidence)+'">Open evidence ↗</a></p>':"";
 el("detail-inner").innerHTML=
  '<div class="detail-top"><button id="close-detail" class="detail-close" type="button" aria-label="Close test">×</button>'+
  '<div class="eyebrow">'+esc(t.id)+' · '+esc(areaName(t.area))+'</div><h2>'+esc(t.feature)+'</h2>'+
  '<div class="detail-meta"><span class="badge '+cls(t.status)+'">'+esc(t.status)+'</span><span class="priority '+esc(t.priority.toLowerCase())+'">'+esc(t.priority)+'</span><span>'+esc(t.method)+'</span></div></div>'+
  '<div class="detail-body"><div class="section-caption">TEST PROCEDURE</div><p class="detail-description">'+esc(t.steps)+'</p>'+
  '<div class="section-caption">EXPECTED RESULT</div><p class="detail-description">'+esc(t.expected)+'</p>'+
  '<form id="test-form" autocomplete="off">'+
  '<label class="field">Test result<select name="status">'+statuses+'</select></label>'+
  field("Tester / owner","owner",t.owner)+field("Environment / device","environment",t.environment)+
  field("Evidence / run link","evidence",t.evidence,"textarea")+evidenceLink+
  field("Findings / notes","notes",t.notes,"textarea")+
  '</form><p class="detail-hint">Saved results remain in the server database, with the date, revision and change history. Use Failed or Blocked for defects that still need work.</p>'+
  '<div class="timeline"><div class="section-caption">TEST HISTORY</div><div id="history-items" class="detail-hint">Loading history…</div></div>'+
  '<div style="margin-top:15px">'+source+'</div></div>'+
  '<div class="detail-actions"><button class="btn primary" id="save-test" type="button">Save result</button><button class="btn" id="next-test" type="button">Next →</button></div>';
 const form=el("test-form");
 form.addEventListener("input",()=>{state.dirty=true;el("save-test").textContent="Save changes";});
 form.addEventListener("change",()=>{state.dirty=true;el("save-test").textContent="Save changes";});
 el("close-detail").addEventListener("click",closeTest);
 el("save-test").addEventListener("click",saveTest);
 el("next-test").addEventListener("click",()=>{
  const items=matching(),current=items.findIndex(x=>x.id===state.selected);
  const next=items[current+1]||items[0];if(next)selectTest(next.id);
 });
 fetchHistory(t.id);
}
async function fetchHistory(id){
 try{const res=await fetch("/api/tests/"+encodeURIComponent(id)+"/history",{cache:"no-store"});if(!res.ok)throw Error("History unavailable");
 const data=await res.json();if(state.selected!==id)return;
 el("history-items").innerHTML=!data.history.length?'<p>No changes recorded since import.</p>':
 data.history.map(h=>'<div class="history-item"><strong>'+esc(h.old_status)+' → '+esc(h.new_status)+'</strong>'+
 '<small>'+esc(h.at)+' · '+esc(h.owner||"Not assigned")+'</small>'+
 (h.notes?'<p>'+esc(h.notes.length>250?h.notes.slice(0,250)+"…":h.notes)+'</p>':"")+'</div>').join("");
 }catch(_){if(state.selected===id)el("history-items").textContent="Could not load history.";}
}
async function saveTest(){
 const t=activeTest();if(!t)return;
 const form=el("test-form"),btn=el("save-test");
 const fields=Object.fromEntries(new FormData(form).entries());
 fields.version=t.version;
 btn.disabled=true;btn.textContent="Saving…";
 try{
  const response=await fetch("/api/tests/"+encodeURIComponent(t.id),{
   method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(fields)
  });
  const body=await response.json();
  if(!response.ok)throw Error(body.error||"Save failed");
  const at=state.tests.findIndex(x=>x.id===t.id);
  state.tests[at]=body.test;state.dirty=false;
  render();renderDetail(body.test);toast(body.saved?"Test result saved":"No changes to save");
 }catch(error){toast(error.message||"Save failed");btn.disabled=false;btn.textContent="Retry save";}
}
async function boot(){
 try{const res=await fetch("/api/tests",{cache:"no-store"});if(!res.ok)throw Error("Cannot load tests (HTTP "+res.status+")");
 const data=await res.json();state.tests=data.tests;state.statuses=data.statuses;
 if(state.tests.length!==218)toast("Register contains "+state.tests.length+" tests; expected 218");
 render();el("sync-status").textContent="Server connected";
 }catch(error){el("sync-status").textContent="Connection error";el("test-list").innerHTML='<tr><td colspan="6">'+esc(error.message)+'</td></tr>';toast(error.message);}
}
el("areas").addEventListener("click",event=>{const b=event.target.closest("[data-area]");if(!b)return;state.area=b.dataset.area;renderAreas();renderTests();});
el("test-list").addEventListener("click",event=>{const r=event.target.closest("[data-id]");if(r)selectTest(r.dataset.id);});
el("test-list").addEventListener("keydown",event=>{if(event.key!=="Enter"&&event.key!==" ")return;const r=event.target.closest("[data-id]");if(r){event.preventDefault();selectTest(r.dataset.id);}});
el("search").addEventListener("input",event=>{state.search=event.target.value;renderTests();});
for(const id of ["status-filter","priority-filter","method-filter"]){el(id).addEventListener("change",event=>{state[id.replace("-filter","").replace("priority","priority").replace("method","method")]=event.target.value;renderTests();});}
el("next-open").addEventListener("click",()=>{const next=matching().find(x=>["Not run","In progress"].includes(x.status));if(next)selectTest(next.id);else toast("No untested items in the current filter");});
window.addEventListener("beforeunload",event=>{if(state.dirty){event.preventDefault();event.returnValue="";}});
window.addEventListener("keydown",event=>{
 if(event.key==="/"&&document.activeElement.tagName!=="INPUT"&&document.activeElement.tagName!=="TEXTAREA"){event.preventDefault();el("search").focus();}
 if((event.metaKey||event.ctrlKey)&&event.key==="Enter"&&state.selected){event.preventDefault();saveTest();}
 if(event.key==="Escape"&&state.selected&&document.activeElement.tagName!=="SELECT")closeTest();
});
boot();
