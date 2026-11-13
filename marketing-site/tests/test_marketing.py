import importlib.util
import sys
import json
import sqlite3
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

root=Path(__file__).resolve().parents[1]/"app"
sys.path.insert(0,str(root))
spec=importlib.util.spec_from_file_location("marketing_app",root/"server.py")
marketing=importlib.util.module_from_spec(spec)
spec.loader.exec_module(marketing)

class MarketingPagesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        marketing.DATABASE=Path(cls.temp.name)/"contact.sqlite3"
        marketing.setup()
        cls.server=ThreadingHTTPServer(("127.0.0.1",0),marketing.App)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True)
        cls.thread.start()
        cls.base="http://127.0.0.1:"+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.temp.cleanup()
    def request(self,path,body=None,origin="https://hi5central.com"):
        headers={}
        if body is not None:
            headers={"Content-Type":"application/x-www-form-urlencoded","Origin":origin}
        req=urllib.request.Request(self.base+path,data=body,headers=headers,method="POST" if body is not None else "GET")
        return urllib.request.urlopen(req,timeout=5)
    def test_all_pages_are_real_html_with_accurate_canonicals(self):
        for path in ("/","/products","/pricing","/about","/contact","/privacy"):
            with self.subTest(path=path),self.request(path) as response:
                page=response.read().decode()
                self.assertEqual(response.status,200)
                self.assertIn('<link rel="canonical" href="https://hi5central.com'+path+'">',page)
                self.assertIn("Skip to content",page)
                for link in ("/products","/pricing","/about","/contact","/signup","https://status.hi5central.com/"):
                    self.assertIn('href="'+link+'"',page)
    def test_dark_and_mobile_assets(self):
        with self.request("/_site/styles.css") as response: css=response.read().decode()
        with self.request("/_site/app.js") as response: js=response.read().decode()
        self.assertIn("@media(prefers-color-scheme:dark)",css)
        self.assertIn("[data-theme=dark]",css)
        self.assertIn("[data-theme=light]",css)
        self.assertIn("@media(max-width:760px)",css)
        self.assertIn("aria-expanded",js)
        self.assertIn("localStorage",js)
    def test_contact_form_persists_and_rejects_bad_origin(self):
        fields={"name":"QA User","email":"qa@example.invalid","company":"Test",
                "product":"ITSM","message":"Internal automated QA enquiry test."}
        data=urllib.parse.urlencode(fields).encode()
        with self.assertRaises(urllib.error.HTTPError) as failed:
            self.request("/contact/submit",body=data,origin="https://invalid.example")
        self.assertEqual(failed.exception.code,403)
        with self.assertRaises(urllib.error.HTTPError) as failed:
            self.request("/contact/submit",body=urllib.parse.urlencode({**fields,"email":"invalid"}).encode())
        self.assertEqual(failed.exception.code,400)
        with self.request("/contact/submit",body=data) as resp:
            self.assertEqual(resp.status,200)
            self.assertIn("/contact?sent=1",resp.url)
        with sqlite3.connect(marketing.DATABASE) as c:
            rows=c.execute("SELECT email,product FROM enquiries").fetchall()
        self.assertEqual(rows,[("qa@example.invalid","ITSM")])
        with self.request("/contact-inbox") as resp:
            # Production Caddy, not this internal server, is the auth boundary.
            self.assertIn("qa@example.invalid",resp.read().decode())
    def test_sitemap_and_unknown_route(self):
        with self.request("/sitemap.xml") as response:
            self.assertIn("https://hi5central.com/products",response.read().decode())
        with self.assertRaises(urllib.error.HTTPError) as failed:
            self.request("/does-not-exist")
        self.assertEqual(failed.exception.code,404)

if __name__=="__main__":
    unittest.main()
