(function(){
"use strict";
const root=document.documentElement;
const key="hi5central.marketing.theme";
let choice=null;
try{choice=localStorage.getItem(key);}catch(_){}
if(choice==="dark"||choice==="light")root.dataset.theme=choice;
const toggle=document.querySelector("[data-theme-toggle]");
function updateTheme(){
 const dark=root.dataset.theme==="dark"||(root.dataset.theme!=="light"&&window.matchMedia("(prefers-color-scheme: dark)").matches);
 if(toggle){
  toggle.setAttribute("aria-pressed",dark?"true":"false");
  toggle.setAttribute("aria-label",dark?"Switch to light mode":"Switch to dark mode");
  const icon=toggle.querySelector("[data-theme-icon]");if(icon)icon.textContent=dark?"☀":"☾";
 }
}
if(toggle){toggle.addEventListener("click",function(){
 const dark=root.dataset.theme==="dark"||(root.dataset.theme!=="light"&&window.matchMedia("(prefers-color-scheme: dark)").matches);
 root.dataset.theme=dark?"light":"dark";
 try{localStorage.setItem(key,root.dataset.theme);}catch(_){}
 updateTheme();
});}
const media=window.matchMedia("(prefers-color-scheme: dark)");
if(media.addEventListener)media.addEventListener("change",updateTheme);
updateTheme();
const menu=document.querySelector("[data-menu-toggle]");
const nav=document.querySelector("#primary-nav");
if(menu&&nav){
 function setOpen(open){nav.classList.toggle("open",open);menu.setAttribute("aria-expanded",String(open));menu.setAttribute("aria-label",open?"Close menu":"Open menu");}
 menu.addEventListener("click",()=>setOpen(!nav.classList.contains("open")));
 nav.addEventListener("click",e=>{if(e.target.closest("a"))setOpen(false);});
 document.addEventListener("keydown",e=>{if(e.key==="Escape")setOpen(false);});
}
})();