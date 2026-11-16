"""Timestamped publisher RSS, with explicit text-matched area precision."""
import concurrent.futures
import datetime as dt
from email.utils import parsedate_to_datetime
import hashlib
import html
import re
from urllib.parse import urlparse
import xml.etree.ElementTree as ET
from data import fetch, utcnow

FEEDS=['https://www.antaranews.com/rss/metro.xml',
       'https://www.antaranews.com/rss/terkini.xml',
       'https://www.antaranews.com/rss/metro-lintas-kota.xml',
       'https://megapolitan.antaranews.com/rss/terkini.xml']
# Place names determine approximate AREA relevance, never an incident's exact location.
PLACES=[('sudirman',-6.217,106.818,3),('thamrin',-6.194,106.823,3),
        ('monas',-6.1754,106.8272,3),('manggarai',-6.210,106.850,3),
        ('kuningan',-6.230,106.830,3),('cawang',-6.244,106.873,3),
        ('margonda',-6.380,106.830,4),('depok',-6.40,106.82,10),
        ('bogor',-6.59,106.80,15),('bekasi',-6.24,107.00,12),
        ('tangerang',-6.18,106.63,15),('jakarta selatan',-6.26,106.81,9),
        ('jakarta pusat',-6.18,106.83,7),('jakarta timur',-6.23,106.90,10),
        ('jakarta barat',-6.17,106.75,9),('jakarta utara',-6.12,106.88,10),
        ('jakarta',-6.21,106.84,25),('jabodetabek',-6.30,106.83,45)]
TOPICS=('banjir','genangan','hujan','cuaca','kemacetan','lalu lintas','rekayasa','penutupan',
        'jalan ditutup','transjakarta','commuter','krl','mrt','lrt','angkutan','transportasi',
        'polusi','kualitas udara','pm2.5','longsor','pohon tumbang')

def classify_severity(title,summary):
    """Classifies reported disruption, not a live danger level. RSS never infers critical."""
    text=(title+' '+summary).lower()
    if re.search(r'\b(tidak ada|tak ada|bebas|nihil)\s+(banjir|genangan|gangguan|kecelakaan)',text):
        return 'low'
    high=('banjir parah','banjir bandang','jembatan ambruk','jalan putus',
          'kecelakaan fatal','tabrakan beruntun','ditutup total','layanan dihentikan','operasi dihentikan','evakuasi warga')
    medium=('kecelakaan','luka-luka','terendam','genangan','banjir melanda','rekayasa lalu lintas','pengalihan arus',
            'gangguan layanan','gangguan perjalanan','pemadaman listrik','listrik mati','stasiun bocor',
            'hujan lebat','kepadatan lalu lintas','kemacetan parah')
    if any(k in text for k in high):return 'high'
    if any(k in text for k in medium):return 'medium'
    return 'low'

def safe_article(url):
    p=urlparse(url)
    return (p.scheme=='https' and p.hostname is not None and
            (p.hostname=='antaranews.com' or p.hostname.endswith('.antaranews.com')) and
            not p.username and not p.password and len(url)<=2000)

def parse_rss(raw,now=None):
    now=now or utcnow()
    if len(raw)>1_000_000 or b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():
        raise ValueError('Unsupported RSS document')
    root=ET.fromstring(raw);out=[]
    for item in root.findall('./channel/item')[:100]:
        title=html.unescape(re.sub('<[^>]*>','',item.findtext('title') or '')).strip()
        url=(item.findtext('link') or '').strip()
        # Classify from a short feed summary; do not redistribute article bodies.
        summary=html.unescape(re.sub('<[^>]*>','',item.findtext('description') or ''))[:1000]
        summary=re.sub(r'(?i)\b(?:Jakarta|Bogor|Depok|Bekasi|Tangerang)\s*\(ANTARA\)\s*[-–—]?', '', summary)
        text=(title+' '+summary).lower()
        try:
            published=parsedate_to_datetime(item.findtext('pubDate') or '')
            if published.tzinfo is None:continue
            published=published.astimezone(dt.timezone.utc)
        except (TypeError,ValueError,OverflowError):continue
        if not safe_article(url) or not title or len(title)>240:continue
        if not now-dt.timedelta(hours=48)<=published<=now+dt.timedelta(minutes=5):continue
        if not any(topic in text for topic in TOPICS):continue
        locations=[(label,lat,lon,radius) for label,lat,lon,radius in PLACES if label in text]
        if not locations:continue
        label,lat,lon,radius=locations[0]
        out.append({'id':'antara-'+hashlib.sha256(url.encode()).hexdigest()[:32],
                    'title':title,'source_url':url,'source_name':'ANTARA',
                    'latitude':lat,'longitude':lon,'location_label':label.title(),
                    'location_radius_km':radius,'location_basis':'publisher_text_area_match',
                    'published_at':published.isoformat(),'starts_at':published.isoformat(),
                    'expires_at':(published+dt.timedelta(hours=48)).isoformat(),
                    'verified':False,'severity':classify_severity(title,summary),
                    'severity_basis':'reported_disruption_keywords_v1'})
    return out

def latest_news():
    items={};failures=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs=[pool.submit(lambda url=url: parse_rss(fetch(url,1_000_000,timeout=5,attempts=1))) for url in FEEDS]
        for job in jobs:
            try:
                for item in job.result():items[item['id']]=item
            except (OSError,ValueError,ET.ParseError):failures+=1
    if failures==len(FEEDS):raise OSError('Publisher feeds unavailable')
    return sorted(items.values(),key=lambda i:i['published_at'],reverse=True)[:50]
