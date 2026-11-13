import importlib.util
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]/"app"
sys.path.insert(0,str(ROOT))
from showcase import home,product,insert_about,insert_pricing,NOTICE

class VisualShowcaseTests(unittest.TestCase):
    def test_home_has_combined_visual_and_both_product_spotlights(self):
        page=home()
        self.assertIn("/_site/images/hi5central-platform.png",page)
        self.assertIn("/_site/images/hi5central-itsm.png",page)
        self.assertIn("/_site/images/hi5central-rmm.png",page)
        self.assertIn('id="itsm"',page)
        self.assertIn('id="rmm"',page)
        self.assertIn("Working together",page)
        self.assertIn("AI-enhanced illustrative product visual",page)
        self.assertIn("not live customer data",page)
        self.assertIn('fetchpriority="high"',page)
        self.assertIn('loading="lazy"',page)
    def test_product_pages_have_real_navigation_targets_and_image_alts(self):
        page=product()
        for target in ('id="itsm"','id="rmm"','id="connected"','href="#itsm"','href="#rmm"','href="#connected"'):
            self.assertIn(target,page)
        for image in ("platform","itsm","rmm"):
            self.assertIn("/_site/images/hi5central-"+image+".png",page)
        self.assertEqual(page.count(NOTICE),3)
        self.assertNotIn("1,248",page)
        self.assertNotIn("98.6%",page)
    def test_pricing_and_about_showcase_is_product_appropriate(self):
        p=insert_pricing("<section>existing prices</section>")
        a=insert_about("<section>company story</section>")
        self.assertIn("existing prices",p)
        self.assertIn("company story",a)
        self.assertIn("hi5central-itsm.png",p)
        self.assertIn("hi5central-rmm.png",p)
        self.assertIn("hi5central-platform.png",a)
    def test_responsive_and_dark_mode_css(self):
        css=(ROOT/"showcase.css").read_text()
        self.assertIn("@media(max-width:760px)",css)
        self.assertIn("prefers-reduced-motion",css)
        self.assertIn("var(--card)",css)
    def test_source_logo_is_preserved_in_server(self):
        source=(ROOT/"server.py").read_text()
        self.assertIn("hi5central-logo.png",source)
        self.assertIn("/signup",source)
        self.assertIn("AppHandler",source) if "AppHandler" in source else self.assertIn("class App(",source)
        self.assertIn('"/_site/showcase.css"',source)
        self.assertIn('"hi5central-platform.png"',source)

if __name__=="__main__":
    unittest.main()
