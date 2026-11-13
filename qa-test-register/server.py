#!/usr/bin/env python3
"""Single-team Hi5Central QA register. Use behind HTTPS + Caddy Basic Auth."""
import csv, io, json, os, sqlite3
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urlsplit, unquote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP=Path(__file__).resolve().parent
DATABASE=Path(os.getenv("QA_TRACKER_DB","/data/tests.sqlite3"))
ORIGIN=os.getenv("QA_TRACKER_ORIGIN","https://tests.hi5central.com")
STATUSES=["Not run","In progress","Pass","Fail","Blocked","Smoke checked"]
EDITABLE=("status","environment","evidence","owner","notes")
FIELDS=("id","area","feature","steps","expected","method","priority","status","environment","evidence","owner","last_run","notes","source_url","sort_index","version","updated_at")
HEADERS=["Test ID","Product / area","Feature or scenario","Test steps","Expected result","Test method","Priority","Status","Environment / device","Evidence / run / ticket","Owner","Last run","Prerequisites / notes","Source URL"]

def now(): return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
def db():
    c=sqlite3.connect(str(DATABASE),timeout=10)
    c.row_factory=sqlite3.Row
    c.execute("PRAGMA busy_timeout=10000")
    return c
def output(row): return {k:row[k] for k in FIELDS}
def initialise():
    DATABASE.parent.mkdir(parents=True,exist_ok=True)
    with db() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("""CREATE TABLE IF NOT EXISTS tests (
          id TEXT PRIMARY KEY,area TEXT,feature TEXT,steps TEXT,expected TEXT,
          method TEXT,priority TEXT,status TEXT,environment TEXT,evidence TEXT,
          owner TEXT,last_run TEXT,notes TEXT,source_url TEXT,sort_index INTEGER,
          version INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL DEFAULT '')""")
        c.execute("""CREATE TABLE IF NOT EXISTS history (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,test_id TEXT NOT NULL,at TEXT NOT NULL,
          old_status TEXT NOT NULL,new_status TEXT NOT NULL,owner TEXT NOT NULL,
          environment TEXT NOT NULL,evidence TEXT NOT NULL,notes TEXT NOT NULL)""")
        with (APP/"seed.csv").open(newline="",encoding="utf-8-sig") as f:
            for i,row in enumerate(csv.DictReader(f)):
                c.execute("""INSERT OR IGNORE INTO tests
                 (id,area,feature,steps,expected,method,priority,status,environment,evidence,owner,last_run,notes,source_url,sort_index)
                 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",(
                   row["Test ID"],row["Product / area"],row["Feature or scenario"],
                   row["Test steps"],row["Expected result"],row["Test method"],row["Priority"],
                   row["Status"],row["Environment / device"],row["Evidence / run / ticket"],
                   row["Owner"],row["Last run"],row["Prerequisites / notes"],row["Source URL"],i))
        n=c.execute("SELECT COUNT(*) FROM tests").fetchone()[0]
        if n < 218: raise RuntimeError("Expected 218 tests, found "+str(n))
    print("QA_TRACKER_READY tests="+str(n),flush=True)

class AppHandler(BaseHTTPRequestHandler):
    server_version="Hi5CentralQA/1.0"
    def log_message(self,format,*args):
        print(self.command,urlsplit(self.path).path,args[1] if len(args)>1 else "",flush=True)
    def send_data(self,status,body,typ="application/json; charset=utf-8",filename=None):
        if isinstance(body,str): body=body.encode("utf-8")
        self.send_response(status)
        for k,v in {
          "Content-Type":typ,"Content-Length":str(len(body)),"Cache-Control":"no-store",
          "X-Content-Type-Options":"nosniff","X-Frame-Options":"DENY",
          "Referrer-Policy":"no-referrer",
          "Content-Security-Policy":"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
        }.items(): self.send_header(k,v)
        if filename:self.send_header("Content-Disposition",'attachment; filename="'+filename+'"')
        self.end_headers();self.wfile.write(body)
    def fail(self,status,message): self.send_data(status,json.dumps({"error":message}))
    def do_GET(self):
        p=unquote(urlsplit(self.path).path)
        if p=="/api/health":return self.send_data(200,'{"ok":true}')
        if p=="/api/tests":
            with db() as c: rows=c.execute("SELECT * FROM tests ORDER BY sort_index,id").fetchall()
            return self.send_data(200,json.dumps({"tests":[output(r) for r in rows],"statuses":STATUSES},ensure_ascii=False))
        if p.startswith("/api/tests/") and p.endswith("/history"):
            key=p[len("/api/tests/"):-len("/history")].strip("/")
            with db() as c: rows=c.execute("SELECT * FROM history WHERE test_id=? ORDER BY seq DESC LIMIT 40",(key,)).fetchall()
            return self.send_data(200,json.dumps({"history":[dict(r) for r in rows]}))
        if p=="/api/export.json":
            with db() as c: rows=c.execute("SELECT * FROM tests ORDER BY sort_index,id").fetchall()
            return self.send_data(200,json.dumps({"tests":[output(r) for r in rows],"exportedAt":now()},ensure_ascii=False,indent=2),filename="hi5central-qa-tests.json")
        if p=="/api/export.csv":
            buf=io.StringIO();w=csv.writer(buf);w.writerow(HEADERS+["Updated at","Revision"])
            with db() as c:
                for r in c.execute("SELECT * FROM tests ORDER BY sort_index,id"):
                    w.writerow([r[x] for x in ("id","area","feature","steps","expected","method","priority","status","environment","evidence","owner","last_run","notes","source_url","updated_at","version")])
            return self.send_data(200,buf.getvalue(),"text/csv; charset=utf-8","hi5central-qa-tests.csv")
        static={"/":("index.html","text/html; charset=utf-8"),
                "/index.html":("index.html","text/html; charset=utf-8"),
                "/app.js":("app.js","application/javascript; charset=utf-8"),
                "/styles.css":("styles.css","text/css; charset=utf-8")}
        if p in static:
            name,typ=static[p]
            return self.send_data(200,(APP/name).read_bytes(),typ)
        self.fail(404,"Not found")
    def do_POST(self):
        p=unquote(urlsplit(self.path).path)
        if not p.startswith("/api/tests/") or "/" in p[len("/api/tests/"):]:return self.fail(404,"Not found")
        if self.headers.get("Origin")!=ORIGIN:return self.fail(403,"Untrusted Origin")
        if not self.headers.get("Content-Type","").lower().startswith("application/json"):
            return self.fail(415,"JSON required")
        try:
            size=int(self.headers.get("Content-Length","0"))
            if not 2<=size<=32768:return self.fail(413,"Invalid size")
            req=json.loads(self.rfile.read(size))
            if not isinstance(req,dict):return self.fail(400,"Expected object")
            tid=p[len("/api/tests/"):]
            if len(tid)>80:return self.fail(400,"Test ID too long")
            version=int(req["version"])
            if version<0:return self.fail(400,"Invalid revision")
            values={x:req.get(x,"") for x in EDITABLE}
            if not all(isinstance(v,str) for v in values.values()):return self.fail(400,"All fields must be text")
            limits={"status":40,"environment":400,"evidence":4000,"owner":160,"notes":8000}
            if values["status"] not in STATUSES:return self.fail(400,"Invalid status")
            if any(len(v)>limits[k] for k,v in values.items()):return self.fail(413,"Field too long")
            with db() as c:
                c.execute("BEGIN IMMEDIATE")
                old=c.execute("SELECT * FROM tests WHERE id=?",(tid,)).fetchone()
                if old is None:return self.fail(404,"Unknown test")
                if old["version"]!=version:
                    return self.send_data(409,json.dumps({"error":"This test changed in another session. Reload before saving.","latest":output(old)}))
                changed=any(old[k]!=values[k] for k in EDITABLE)
                if changed:
                    stamp=now()
                    last=stamp[:10] if values["status"]!="Not run" else old["last_run"]
                    c.execute("""UPDATE tests SET status=?,environment=?,evidence=?,owner=?,notes=?,last_run=?,updated_at=?,version=version+1 WHERE id=?""",(
                     values["status"],values["environment"],values["evidence"],values["owner"],values["notes"],last,stamp,tid))
                    c.execute("""INSERT INTO history (test_id,at,old_status,new_status,owner,environment,evidence,notes)
                      VALUES (?,?,?,?,?,?,?,?)""",(tid,stamp,old["status"],values["status"],values["owner"],values["environment"],values["evidence"],values["notes"]))
                current=c.execute("SELECT * FROM tests WHERE id=?",(tid,)).fetchone()
            self.send_data(200,json.dumps({"test":output(current),"saved":changed},ensure_ascii=False))
        except (ValueError,TypeError,KeyError,json.JSONDecodeError):
            self.fail(400,"Invalid payload")
        except sqlite3.Error:
            self.fail(503,"Unable to save")
if __name__=="__main__":
    initialise()
    ThreadingHTTPServer(("0.0.0.0",8080),AppHandler).serve_forever()
