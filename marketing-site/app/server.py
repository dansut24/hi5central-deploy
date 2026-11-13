#!/usr/bin/env python3
"""Hi5Central product marketing pages; signup/API continue via existing ITSM route."""
import html
import os
import re
import sqlite3
import time
import hashlib
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

APP=Path(__file__).resolve().parent
DATABASE=Path(os.getenv("MARKETING_CONTACT_DB","/data/contact.sqlite3"))
ORIGINS={"https://hi5central.com","https://www.hi5central.com"}
PAGES={"":("Hi5Central | Connected ITSM and RMM","IT service management and remote monitoring together, or separately.","Home"),
       "products":("Products | Hi5Central","Explore Hi5Central ITSM, RMM, Connect, software deployment and self-service.","Products"),
       "pricing":("Pricing | Hi5Central","Choose ITSM, RMM or both. Contact Hi5Central for current product pricing.","Pricing"),
       "about":("About | Hi5Central","Why we're building Hi5Central: clear service workflows and dependable endpoint operations.","About"),
       "contact":("Contact | Hi5Central","Contact the Hi5Central team with product, pricing and implementation enquiries.","Contact"),
       "privacy":("Contact privacy | Hi5Central","How website contact enquiries are used and retained.","Privacy")}

def esc(v):return html.escape(str(v),quote=True)
def utc():return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
def connect():
    c=sqlite3.connect(str(DATABASE),timeout=8)
    c.execute("PRAGMA busy_timeout=8000")
    return c
def setup():
    DATABASE.parent.mkdir(parents=True,exist_ok=True)
    with connect() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("""CREATE TABLE IF NOT EXISTS enquiries(
          id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL,
          name TEXT NOT NULL, company TEXT NOT NULL, email TEXT NOT NULL,
          product TEXT NOT NULL, message TEXT NOT NULL, sender_hash TEXT NOT NULL)""")
        c.execute("CREATE INDEX IF NOT EXISTS enquiries_created_idx ON enquiries(created_at)")
        c.execute("DELETE FROM enquiries WHERE created_at < ?",((datetime.now(timezone.utc)-timedelta(days=90)).isoformat(timespec="seconds").replace("+00:00","Z"),))
    print("MARKETING_READY",flush=True)

def link(href,text,current=None):
    active=' aria-current="page"' if (current==href) else ""
    return '<a href="'+esc(href)+'"'+active+'>'+esc(text)+'</a>'
def header(current):
    nav=(
      link("/","Home",current)+link("/products","Products",current)+
      link("/pricing","Pricing",current)+link("/about","About",current)+
      link("/contact","Contact",current)+
      '<a href="https://status.hi5central.com/" rel="noopener noreferrer">Status <span aria-hidden="true">↗</span></a>'
    )
    return (
     '<a class="skip" href="#main">Skip to content</a>'
     '<header class="site-header"><div class="container nav-bar">'
     '<a class="brand" href="/" aria-label="Hi5Central homepage"><img src="/hi5central-logo.png" alt="" width="37" height="37"><span>Hi5<span class="brand-accent">Central</span></span></a>'
     '<nav id="primary-nav" class="primary-nav" aria-label="Primary navigation">'+nav+'</nav>'
     '<div class="nav-actions"><button class="theme-toggle" type="button" aria-label="Switch colour theme" aria-pressed="false" title="Switch colour theme" data-theme-toggle><span data-theme-icon aria-hidden="true">◐</span> <span class="theme-label">Theme</span></button>'
     '<a href="/signup" class="button button-primary nav-signup">Start free <span aria-hidden="true">↗</span></a>'
     '<button class="menu-toggle" type="button" aria-controls="primary-nav" aria-expanded="false" data-menu-toggle aria-label="Open menu"><span aria-hidden="true">☰</span></button>'
     '</div></div></header>'
    )
def footer():
    return ('<footer class="site-footer"><div class="container footer-inner">'
            '<div><a class="footer-brand" href="/">Hi5Central</a><p>Service management and endpoint operations, connected.</p></div>'
            '<nav aria-label="Footer navigation"><a href="/products">Products</a><a href="/pricing">Pricing</a><a href="/about">About</a><a href="/contact">Contact</a><a href="/privacy">Contact privacy</a><a href="https://status.hi5central.com/">System status</a></nav>'
            '</div><div class="container fineprint">© Hi5Central. Product features and availability may vary by subscription and deployment.</div></footer>')
def button(href,title,primary=True):
    return '<a class="button '+('button-primary' if primary else 'button-secondary')+'" href="'+esc(href)+'">'+esc(title)+' <span aria-hidden="true">↗</span></a>'
def features():
    return (
      '<div class="feature-grid">'
      '<article class="feature-card"><div class="feature-icon">▣</div><h3>IT Service Management</h3><p>Incidents, requests, problems, changes, knowledge, SLA, task workflows and the requester portal.</p><a href="/products#itsm">Explore ITSM →</a></article>'
      '<article class="feature-card"><div class="feature-icon">▤</div><h3>Remote Monitoring &amp; Management</h3><p>Device inventory, remote support, patching, software operations, monitoring policies and automation.</p><a href="/products#rmm">Explore RMM →</a></article>'
      '<article class="feature-card"><div class="feature-icon">↗</div><h3>A connected workflow</h3><p>Link service records to devices and remote-support actions without losing context between products.</p><a href="/products#connected">Explore the platform →</a></article>'
      '</div>'
    )
def homepage():
    return (
     '<section class="hero"><div class="container hero-grid"><div class="hero-copy">'
     '<div class="eyebrow"><span class="signal"></span> One platform. Two powerful products.</div>'
     '<h1>IT support that<br><span class="gradient-text">works together.</span></h1>'
     '<p>Hi5Central brings IT service management and remote monitoring into a connected workspace. Choose ITSM, RMM or both — and bring the right tools to your team.</p>'
     '<div class="button-row">'+button("/signup","Create your workspace")+button("/products","Explore the products",False)+'</div>'
     '<div class="hero-facts"><span>✓ Choose your products</span><span>✓ Tenant-aware workspaces</span><span>✓ Web &amp; mobile development</span></div>'
     '</div><div class="hero-visual" aria-label="Illustrative Hi5Central workflow">'
     '<div class="visual-top"><div class="visual-dot"></div><span>HI5CENTRAL WORKSPACE</span><span class="visual-live">Connected operations</span></div>'
     '<div class="visual-content"><div class="visual-item"><div class="visual-symbol blue">01</div><div><strong>Service Desk</strong><span>Incident · Request · Change</span></div><span class="visual-arrow">↗</span></div>'
     '<div class="visual-link"><span></span> Linked service context</div>'
     '<div class="visual-item"><div class="visual-symbol aqua">02</div><div><strong>Device management</strong><span>Inventory · Remote access</span></div><span class="visual-arrow">↗</span></div>'
     '<div class="visual-line"></div><div class="visual-bottom"><span class="pulse"></span> Tenant-scoped workflow <strong>ITSM + RMM</strong></div></div></div>'
     '</div></section>'
     '<section class="section"><div class="container"><div class="section-head"><div class="eyebrow">PRODUCTS</div><h2>Everything your team needs,<br>without disconnected tools.</h2><p>Start with the product you need today and connect your service and endpoint workflows as your team grows.</p></div>'+features()+'</div></section>'
     '<section class="section section-tint"><div class="container split"><div><div class="eyebrow">BUILT FOR REAL OPERATIONS</div><h2>From first request to final resolution.</h2><p>Give technicians a clear view of work, help requesters find services, and tie endpoint actions back to the right record.</p><ul class="checklist"><li>Dedicated ITSM and RMM workspaces</li><li>Shared identity and tenant-scoped access</li><li>Self-service experiences and native app development</li><li>Managed and Custom update models for ITSM</li></ul></div>'
     '<div class="steps-card"><div><span>01</span><strong>Request and triage</strong><p>Capture incidents and service requests.</p></div><div><span>02</span><strong>Investigate and act</strong><p>Work with the related endpoint context.</p></div><div><span>03</span><strong>Resolve and learn</strong><p>Track work, notes, tasks and outcomes.</p></div></div></div></section>'
     '<section class="section"><div class="container cta-band"><div><div class="eyebrow">GET STARTED</div><h2>Build a more connected IT operation.</h2><p>Explore the platform or talk to us about your organisation.</p></div><div class="button-row">'+button("/signup","Start free")+button("/contact","Contact us",False)+'</div></div></section>'
    )
def product_page():
    def detail(id,kicker,title,description,items):
        return ('<section class="product-detail" id="'+id+'"><div><div class="eyebrow">'+kicker+'</div><h2>'+title+'</h2><p>'+description+'</p>'
          +button("/signup","Start with Hi5Central")+'</div><ul class="checklist">'+''.join('<li>'+x+'</li>' for x in items)+'</ul></section>')
    return (
      '<section class="page-hero container"><div class="eyebrow">HI5CENTRAL PRODUCTS</div><h1>Two products.<br><span class="gradient-text">Better together.</span></h1><p>Pick the service management tools, endpoint tools, or the connected experience your organisation needs.</p></section>'
      '<div class="container">'+detail("itsm","IT SERVICE MANAGEMENT","Keep every service request moving.","A home for IT operations, people, requests and structured work.",[
       "Incidents, Service Requests, Problems and Changes","Approval steps, fulfilment tasks and SLA tracking","Knowledge, People, Projects and CMDB workspaces","Requester self-service portal and service catalogue"
      ])+detail("rmm","REMOTE MONITORING & MANAGEMENT","Stay close to every endpoint.","Inventory, remote control and endpoint operations through a dedicated RMM workspace.",[
       "Managed devices, sites and groups","WebRTC remote access and technician tools","Software inventory, deployment and patching","Monitoring policies, scripts and automation"
      ])+detail("connected","CONNECTED WORKFLOWS","Join the ticket to the device.","Hi5Central can connect ITSM records with RMM actions while keeping the two products distinct.",[
       "Open related RMM devices from ITSM work","Consistent identity and tenant controls","Separate product permissions and lifecycle","A combined iOS application in active development"
      ])+'</div>'
      '<section class="section section-tint"><div class="container"><div class="section-head"><div class="eyebrow">ADDITIONAL TOOLS</div><h2>Practical support for the whole workflow.</h2></div>'
      '<div class="feature-grid"><article class="feature-card"><div class="feature-icon">↗</div><h3>Hi5Central Connect</h3><p>Customer-consented, one-time remote assistance without a permanently installed management Agent.</p></article>'
      '<article class="feature-card"><div class="feature-icon">↓</div><h3>Software Self-Service</h3><p>A Windows App Portal to request and install applications published to eligible users through RMM.</p></article>'
      '<article class="feature-card"><div class="feature-icon">▥</div><h3>Mobile apps</h3><p>Native technician experiences are in development for iOS and Android, including remote viewing.</p></article></div></div></section>'
      '<section class="section"><div class="container cta-band"><div><div class="eyebrow">NEXT STEP</div><h2>Find the right fit for your team.</h2><p>Explore product options and how the platform can be introduced to your business.</p></div><div class="button-row">'+button("/pricing","View pricing options")+button("/contact","Contact us",False)+'</div></div></section>'
    )
def pricing_page():
    cards=[
     ("ITSM","Service Desk","For teams managing support tickets, requests, changes and knowledge.","Service catalogue","Approval & SLA workflows","People and organisation workspaces"),
     ("RMM","Endpoint Management","For teams managing devices, remote assistance, patching and software.","Device and software inventory","Remote access & automation","Monitoring and patching"),
     ("ITSM + RMM","Connected Platform","For teams that want service requests and endpoint operations to work together.","Everything in ITSM and RMM","Connected record-to-device workflow","Unified product experience")
    ]
    rows=""
    for tag,title,sub,*points in cards:
        rows+=('<article class="pricing-card"><div class="eyebrow">'+tag+'</div><h2>'+title+'</h2><p>'+sub+'</p><strong class="quote">Request current pricing</strong>'
         +'<ul class="checklist">'+''.join('<li>'+x+'</li>' for x in points)+'</ul>'+button("/contact","Discuss this option",False)+'</article>')
    return ('<section class="page-hero container"><div class="eyebrow">PRODUCT PRICING</div><h1>Choose the right<br><span class="gradient-text">Hi5Central setup.</span></h1>'
      '<p>ITSM, RMM and combined product options. Prices are provided for your requirements rather than displaying unconfirmed public rates.</p></section>'
      '<section class="section compact"><div class="container pricing-grid">'+rows+'</div></section>'
      '<section class="section section-tint"><div class="container split"><div><div class="eyebrow">TRANSPARENT NEXT STEPS</div><h2>Not ready to choose?</h2><p>Tell us whether you need service management, device management or both. We can discuss the best product setup and current commercial options.</p></div><div class="steps-card"><h3>No unverified pricing claims.</h3><p>The website deliberately does not display subscription figures until plans and rates are confirmed.</p>'+button("/contact","Ask about pricing")+'</div></div></section>'
    )
def about_page():
    return (
      '<section class="page-hero container"><div class="eyebrow">ABOUT HI5CENTRAL</div><h1>Technology should<br><span class="gradient-text">make support simpler.</span></h1><p>Hi5Central is being developed to connect structured IT service management with dependable endpoint operations.</p></section>'
      '<section class="section compact"><div class="container split"><div><div class="eyebrow">WHY WE EXIST</div><h2>Support people and systems in one connected workflow.</h2><p>IT work often spans separate ticketing, remote-support, device and software tools. Hi5Central aims to reduce context switching while giving teams a clear record of what happened and why.</p><p>Both products remain independently selectable, with deliberate integration points for organisations that need them together.</p></div>'
      '<div class="steps-card"><div><span>01</span><strong>Clarity</strong><p>Readable records, responsibilities and outcomes.</p></div><div><span>02</span><strong>Control</strong><p>Approvals, access boundaries and change tracking.</p></div><div><span>03</span><strong>Dependability</strong><p>Remote assistance and operational visibility.</p></div></div></div></section>'
      '<section class="section section-tint"><div class="container cta-band"><div><div class="eyebrow">STAY CONNECTED</div><h2>Explore Hi5Central.</h2><p>See the products, check service status or get in touch.</p></div><div class="button-row">'+button("/products","View products")+button("/contact","Contact us",False)+'</div></div></section>'
    )
def contact_page(sent):
    notice='<div class="notice success" role="status">Your enquiry has been received and saved. Our team can review it securely.</div>' if sent else ""
    return (
      '<section class="page-hero container"><div class="eyebrow">GET IN TOUCH</div><h1>Let’s talk about<br><span class="gradient-text">your IT operation.</span></h1><p>Have a question about ITSM, RMM, product pricing or getting started? Send an enquiry below.</p></section>'
      '<section class="section compact"><div class="container contact-grid"><div class="contact-copy"><div class="eyebrow">CONTACT HI5CENTRAL</div><h2>Tell us what you need.</h2><p>For sales and product questions, use the enquiry form. Existing customers can continue to use their organisation’s support processes.</p>'
      '<div class="contact-fact"><strong>Product information</strong><span>ITSM · RMM · Combined platform</span></div>'
      '<div class="contact-fact"><strong>Current service health</strong><a href="https://status.hi5central.com/">View our public status page ↗</a></div>'
      '<div class="contact-fact"><strong>Create a workspace</strong><a href="/signup">Go to signup ↗</a></div>'
      '</div><div class="contact-card"><h2>Send an enquiry</h2><p>We’ll record your message for follow-up.</p>'+notice+
      '<form method="post" action="/contact/submit" class="contact-form">'
      '<label>Your name <input autocomplete="name" type="text" name="name" minlength="2" maxlength="120" required></label>'
      '<label>Work email <input autocomplete="email" type="email" name="email" maxlength="240" required></label>'
      '<label>Company <input autocomplete="organization" type="text" name="company" maxlength="160"></label>'
      '<label>Interested in <select name="product"><option>ITSM</option><option>RMM</option><option>ITSM + RMM</option><option>Other enquiry</option></select></label>'
      '<label>How can we help? <textarea name="message" minlength="12" maxlength="4000" rows="5" required></textarea></label>'
      '<div class="honeypot" aria-hidden="true"><label>Website <input type="text" name="website" tabindex="-1" autocomplete="off"></label></div>'
      '<p class="form-note">We use these details to review and respond to your enquiry. See <a href="/privacy">contact privacy</a>. Do not include passwords or sensitive account information.</p>'
      '<button type="submit" class="button button-primary">Send enquiry <span aria-hidden="true">↗</span></button></form></div></div></section>'
    )
def privacy_page():
    return ('<section class="page-hero container"><div class="eyebrow">CONTACT PRIVACY</div><h1>Information you share<br><span class="gradient-text">with Hi5Central.</span></h1><p>This page describes how enquiries submitted through the website contact form are handled.</p></section>'
      '<section class="section compact"><div class="container prose-card"><h2>Contact enquiries</h2><p>We collect the name, company (if provided), email address, product interest and message you submit. They are used to respond to your enquiry and evaluate the information requested.</p>'
      '<h2>Retention and access</h2><p>Enquiries are stored in an access-restricted system on our original server and are automatically deleted after 90 days from the live enquiry database. A small internal team can review them. Separately retained backups may remain longer according to backup schedules.</p>'
      '<h2>Important information</h2><p>Do not send passwords, authentication codes or highly sensitive customer information through this form. You can ask about your message through the contact page.</p></div></section>')
def page_content(key,sent=False):
    return {"":homepage,"products":product_page,"pricing":pricing_page,"about":about_page,
            "contact":lambda:contact_page(sent),"privacy":privacy_page}[key]()
def render(key,sent=False):
    title,desc,_=PAGES[key]
    path="/"+key
    canonical="https://hi5central.com"+(path if key else "/")
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
     '<meta name="viewport" content="width=device-width, initial-scale=1">'
     '<meta name="color-scheme" content="light dark">'
     '<meta name="theme-color" content="#111e33">'
     '<title>'+esc(title)+'</title><meta name="description" content="'+esc(desc)+'">'
     '<link rel="canonical" href="'+esc(canonical)+'">'
     '<meta property="og:type" content="website"><meta property="og:title" content="'+esc(title)+'">'
     '<meta property="og:description" content="'+esc(desc)+'">'
     '<meta property="og:url" content="'+esc(canonical)+'">'
     '<link rel="icon" href="/favicon.svg" type="image/svg+xml">'
     '<link rel="stylesheet" href="/_site/styles.css">'
     '<script defer src="/_site/app.js"></script></head><body>'
     +header(path)+'<main id="main">'+page_content(key,sent)+'</main>'+footer()+'</body></html>')
class App(BaseHTTPRequestHandler):
    server_version="Hi5CentralMarketing/1.0"
    def log_message(self,fmt,*args):
        print(self.command,urlsplit(self.path).path,args[1] if len(args)>1 else "",flush=True)
    def send(self,status,body,mime="text/html; charset=utf-8",extra=None):
        if isinstance(body,str):body=body.encode("utf-8")
        self.send_response(status)
        for k,v in {
          "Content-Type":mime,"Content-Length":str(len(body)),
          "X-Content-Type-Options":"nosniff","X-Frame-Options":"DENY",
          "Referrer-Policy":"strict-origin-when-cross-origin",
          "Content-Security-Policy":"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
          "Cache-Control":"no-store"
        }.items():self.send_header(k,v)
        if extra:
            for k,v in extra.items():self.send_header(k,v)
        self.end_headers();self.wfile.write(body)
    def do_GET(self):
        s=urlsplit(self.path);path=s.path
        if path=="/healthz":return self.send(200,"ok","text/plain")
        if path=="/_site/styles.css":return self.send(200,(APP/"styles.css").read_bytes(),"text/css; charset=utf-8")
        if path=="/_site/app.js":return self.send(200,(APP/"app.js").read_bytes(),"application/javascript; charset=utf-8")
        if path=="/robots.txt":return self.send(200,"User-agent: *\nAllow: /\nSitemap: https://hi5central.com/sitemap.xml\n","text/plain")
        if path=="/sitemap.xml":
            return self.send(200,'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join('<url><loc>https://hi5central.com/'+k+'</loc></url>' for k in PAGES)+'</urlset>',"application/xml")
        if path=="/contact-inbox":
            with connect() as c:
                rows=c.execute("SELECT id,created_at,name,company,email,product,message FROM enquiries ORDER BY id DESC LIMIT 200").fetchall()
            items=''.join('<article><h2>#'+str(r[0])+' · '+esc(r[3])+' · '+esc(r[5])+'</h2><p>'+esc(r[1])+' · '+esc(r[2])+' · '+esc(r[4])+'</p><pre>'+esc(r[6])+'</pre></article>' for r in rows)
            body='<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hi5Central enquiries (private)</title><style>body{font:16px system-ui;background:#f6f8fc;color:#152944;max-width:900px;margin:40px auto;padding:20px}article{background:#fff;border-radius:12px;padding:16px;margin:15px 0}pre{white-space:pre-wrap;font:inherit}a{color:#145cc6}</style></head><body><h1>Hi5Central website enquiries</h1><p>Staff access only. Most recent 200 enquiries. Do not copy customer details into public issues.</p>'+items+'</body></html>'
            return self.send(200,body)
        key=path.strip("/")
        if key in PAGES and path in ("/","/"+key):
            return self.send(200,render(key,s.query=="sent=1"))
        return self.send(404,"Page not found","text/plain")
    def do_POST(self):
        if urlsplit(self.path).path!="/contact/submit":return self.send(404,"Page not found","text/plain")
        origin=self.headers.get("Origin","")
        if origin not in ORIGINS:return self.send(403,"Invalid origin","text/plain")
        if not self.headers.get("Content-Type","").lower().startswith("application/x-www-form-urlencoded"):
            return self.send(415,"Unsupported form type","text/plain")
        try:
            size=int(self.headers.get("Content-Length","0"))
            if not 10<=size<=10000:return self.send(413,"Message too large","text/plain")
            form=parse_qs(self.rfile.read(size).decode("utf-8"),keep_blank_values=True)
            val=lambda k:form.get(k,[""])[0].strip()
            if val("website"):return self.redirect("/contact?sent=1")
            name,email,company,product,message=[val(k) for k in ("name","email","company","product","message")]
            if not 2<=len(name)<=120 or len(email)>240 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+",email) or len(company)>160 or product not in ("ITSM","RMM","ITSM + RMM","Other enquiry") or not 12<=len(message)<=4000:
                return self.send(400,"Please check your contact details and message.","text/plain")
            forwarded=self.headers.get("X-Forwarded-For","").split(",")[0].strip()
            if not forwarded:forwarded="proxy"
            sender=hashlib.sha256((email.casefold()+"|"+forwarded).encode()).hexdigest()
            stamp=utc()
            limit=(datetime.now(timezone.utc)-timedelta(hours=1)).isoformat(timespec="seconds").replace("+00:00","Z")
            with connect() as c:
                n=c.execute("SELECT COUNT(*) FROM enquiries WHERE sender_hash=? AND created_at>?",(sender,limit)).fetchone()[0]
                if n>=3:return self.send(429,"Too many recent messages. Please try again later.","text/plain")
                c.execute("INSERT INTO enquiries(created_at,name,company,email,product,message,sender_hash) VALUES(?,?,?,?,?,?,?)",(stamp,name,company,email,product,message,sender))
            return self.redirect("/contact?sent=1")
        except (UnicodeDecodeError,ValueError,TypeError,IndexError,sqlite3.Error):
            return self.send(400,"Unable to accept your enquiry.","text/plain")
    def redirect(self,where):
        self.send_response(303)
        self.send_header("Location",where)
        self.send_header("Cache-Control","no-store")
        self.send_header("Content-Length","0")
        self.end_headers()
if __name__=="__main__":
    setup()
    ThreadingHTTPServer(("0.0.0.0",8080),App).serve_forever()
