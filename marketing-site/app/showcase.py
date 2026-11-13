"""Polished Hi5Central Marketing showcases. AI-art is illustrative, not live telemetry."""
from html import escape as _escape

def button(path, label, primary=True):
    return '<a class="button '+("button-primary" if primary else "button-secondary")+'" href="'+path+'">'+label+' <span aria-hidden="true">↗</span></a>'

NOTICE = "AI-enhanced illustrative product visual. Screens and metrics shown are examples, not live customer data."

def image(name,alt,kind="image",priority=False):
    src="/_site/images/hi5central-"+name+".webp"
    return ('<figure class="show-figure '+kind+'">'
            '<img src="'+src+'" width="1024" height="576" alt="'+_escape(alt)+'" '
            +('loading="eager" fetchpriority="high"' if priority else 'loading="lazy"')
            +' decoding="async">'
            '<figcaption>'+NOTICE+'</figcaption></figure>')

def segment(label,text):
    return '<span class="show-segment"><span aria-hidden="true">◆</span>'+label+'<small>'+text+'</small></span>'

def feature_card(num,title,copy,link,label):
    return ('<article class="show-capability"><div class="show-num">'+num+'</div><h3>'+title+'</h3>'
            '<p>'+copy+'</p><a href="'+link+'">'+label+' <span aria-hidden="true">→</span></a></article>')

def product_block(id,kicker,title,text,points,photo,reverse=False):
    facts=''.join('<li>'+item+'</li>' for item in points)
    return ('<section class="show-product '+('show-reverse' if reverse else '')+'" id="'+id+'">'
            '<div class="show-product-copy"><div class="show-kicker">'+kicker+'</div><h2>'+title+'</h2>'
            '<p>'+text+'</p><ul class="show-points">'+facts+'</ul>'
            +button('/products#'+id,'Explore '+('ITSM' if id=='itsm' else 'RMM'))
            +'</div>'+image(photo, 'AI-enhanced illustrative Hi5Central '+('ITSM service desk' if id=='itsm' else 'RMM device monitoring')+' product interface', "show-feature-image")+'</section>')

def home():
    return (
      '<section class="show-hero" aria-labelledby="show-title"><div class="container show-hero-grid">'
      '<div class="show-hero-copy"><div class="show-kicker"><span class="show-live-dot"></span> IT operations, beautifully connected</div>'
      '<h1 id="show-title">Everything IT needs.<br><span class="show-gradient">Working together.</span></h1>'
      '<p class="show-intro">Modern service management meets practical endpoint control. Bring requests, devices and support workflows into one connected Hi5Central experience.</p>'
      '<div class="show-actions">'+button('/signup','Start with Hi5Central')+button('/products','Explore products',False)+'</div>'
      '<div class="show-hero-foot"><span>ITSM</span><i aria-hidden="true"></i><span>RMM</span><i aria-hidden="true"></i><span>Connected workflows</span></div></div>'
      +image('platform','AI-enhanced visual showing an illustrative Hi5Central ITSM service desk and RMM monitoring dashboard side by side',"show-hero-image",True)
      +'</div><div class="show-hero-glow" aria-hidden="true"></div></section>'
      '<section class="show-overview"><div class="container"><div class="show-overview-grid">'
      +segment('ITSM','A service desk built around people and requests.')
      +segment('RMM','Devices, support and software in one workspace.')
      +segment('Together','Context that follows your team across products.')
      +'</div></div></section>'
      '<section class="show-section" aria-labelledby="show-products"><div class="container">'
      '<div class="show-section-top"><div><div class="show-kicker">MADE FOR EVERY PART OF IT</div><h2 id="show-products">The platform behind<br>better support.</h2></div>'
      '<p>Choose ITSM, RMM or both. Each product has its own workspace, with deliberate integrations when you need them together.</p></div>'
      +product_block('itsm','01 / IT SERVICE MANAGEMENT','Turn requests into real progress.',
         'A purpose-built service desk for incidents, approvals, change, knowledge and service delivery.',
         ['Incidents, problems and changes','Service requests, approvals and fulfilment tasks','Service catalogue, knowledge and SLAs'],
         'itsm')
      +product_block('rmm','02 / REMOTE MONITORING & MANAGEMENT','Go from insight to action.',
         'Support and manage endpoints with device context, remote access and software operations in one place.',
         ['Device inventory and endpoint health','Remote support and technician tools','Patching, software catalogue and automation'],
         'rmm',True)
      +'</div></section>'
      '<section class="show-section show-wash" aria-labelledby="show-workflow"><div class="container">'
      '<div class="show-section-top"><div><div class="show-kicker">WHY HI5CENTRAL</div><h2 id="show-workflow">Less jumping between tools.<br>More time solving problems.</h2></div>'
      '<p>Follow an issue from the service desk to the relevant device and back to the record.</p></div>'
      '<div class="show-capabilities">'
      +feature_card('01','Capture the request','Manage incidents, service requests and approvals with a clear record of progress.','/products#itsm','ITSM features')
      +feature_card('02','Connect the device','See managed endpoints and open the appropriate remote support workflow.','/products#rmm','RMM features')
      +feature_card('03','Close the loop','Keep notes, activity and resolution context together for technicians and requesters.','/contact','Talk to us')
      +'</div></div></section>'
      '<section class="show-final"><div class="container"><div class="show-final-inner">'
      '<div class="show-kicker">LET\'S BUILD A BETTER IT WORKFLOW</div><h2>Ready for connected IT operations?</h2>'
      '<p>Explore the products, create your workspace or ask us about the right setup for your organisation.</p>'
      '<div class="show-actions">'+button('/signup','Create a workspace')+button('/contact','Contact Hi5Central',False)+'</div>'
      '</div></div></section>'
    )

def product():
    return (
      '<section class="show-product-hero"><div class="container show-product-head">'
      '<div><div class="show-kicker">THE HI5CENTRAL PLATFORM</div>'
      '<h1>Two products.<br><span class="show-gradient">One connected experience.</span></h1>'
      '<p>Make service operations and endpoint support easier to manage. Discover what ITSM, RMM and their integrations bring to your team.</p>'
      '<div class="show-actions">'+button('/signup','Start free')+button('/pricing','View options',False)+'</div></div>'
      +image('platform','Illustrative combined Hi5Central service management and endpoint monitoring dashboard',"show-product-hero-image",True)
      +'</div></section>'
      '<div class="container show-product-directory"><a href="#itsm">01 <strong>ITSM</strong><span aria-hidden="true">↘</span></a>'
      '<a href="#rmm">02 <strong>RMM</strong><span aria-hidden="true">↘</span></a>'
      '<a href="#connected">03 <strong>Connected workflows</strong><span aria-hidden="true">↘</span></a></div>'
      '<section class="show-section show-directory"><div class="container">'
      +product_block('itsm','HI5CENTRAL / ITSM','IT Service Management that keeps work moving.',
        'Bring your service desk, catalogue and organisation into one structured workspace. From first contact through approvals, tasks and resolution.',
        ['Incident, Problem and Change management','Service Requests and fulfilment workflows','SLA, knowledge and task workspaces','Self-service requester portal'],
        'itsm')
      +product_block('rmm','HI5CENTRAL / RMM','Remote operations with real device context.',
        'Manage device inventory, monitoring and everyday endpoint support through a dedicated RMM workspace.',
        ['Endpoint inventory, groups and policies','WebRTC remote access and remote tools','Software inventory, patching and automation','Software qualification and App Portal integration'],
        'rmm',True)
      +'</div></section>'
      '<section class="show-section show-wash" id="connected"><div class="container">'
      '<div class="show-section-top"><div><div class="show-kicker">ONE CONNECTED APPROACH</div><h2>Work together,<br>without losing context.</h2></div>'
      '<p>ITSM and RMM remain individually selectable, with integrations designed to preserve the device and support context technicians need.</p></div>'
      '<div class="show-capabilities">'
      +feature_card('A','Hi5Central Connect','Temporary, customer-consented remote assistance without full device enrolment.','/contact','Ask about Connect')
      +feature_card('B','Software self-service','Approved applications presented in a Windows App Portal for eligible users.','/contact','Explore self-service')
      +feature_card('C','Mobile technician tools','Combined iOS and Android experiences under active development, with native viewing components.','/contact','Learn more')
      +'</div></div></section>'
      '<section class="show-final"><div class="container"><div class="show-final-inner">'
      '<div class="show-kicker">CHOOSING HI5CENTRAL</div><h2>Find the product fit for your team.</h2>'
      '<p>Explore current subscription options or tell us what you need.</p>'
      '<div class="show-actions">'+button('/pricing','Pricing options')+button('/contact','Get in touch',False)+'</div>'
      '</div></div></section>'
    )

def insert_pricing(pricing_html):
    # Reinforces the three choices visually without claiming prices that are not confirmed.
    return (pricing_html + '<section class="show-pricing-preview"><div class="container"><div class="show-section-top">'
       '<div><div class="show-kicker">A PREVIEW OF THE PLATFORM</div><h2>See what your team<br>could work with.</h2></div>'
       '<p>Choose one product or pair both — no invented pricing or simulated customer claims.</p></div>'
       '<div class="show-pricing-visuals">'+image('itsm','Illustrative ITSM service desk layout', 'show-preview-image')
       +image('rmm','Illustrative RMM endpoint dashboard layout', 'show-preview-image')+'</div></div></section>')

def insert_about(about_html):
    return (about_html + '<section class="show-about-visual"><div class="container">'
       '<div class="show-section-top"><div><div class="show-kicker">THE HI5CENTRAL VISION</div><h2>Modern tools.<br>Less friction.</h2></div>'
       '<p>ITSM and RMM working together, illustrated in one connected workspace.</p></div>'
       +image('platform','AI-enhanced illustration of connected Hi5Central ITSM and RMM product interfaces','show-about-image')
       +'</div></section>')
