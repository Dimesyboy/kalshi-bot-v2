#!/usr/bin/env python3
import requests, logging, time
from dataclasses import dataclass, field
from typing import Optional
log = logging.getLogger("kalshi_bot.espn")
ESPN_URLS = {
    "NBA":    "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
    "MLB":    "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
    "Tennis_ATP": "http://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard",
    "Tennis_WTA": "http://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard",
}
ESPN_TIMEOUT=8; ESPN_CACHE_TTL=45
STATUS_LIVE="STATUS_IN_PROGRESS"; STATUS_FINAL="STATUS_FINAL"
@dataclass
class TeamState:
    name:str; abbreviation:str; score:int; is_home:bool
    record_wins:int=0; record_loss:int=0; hits:int=0; errors:int=0
@dataclass
class GameContext:
    sport:str; event_id:str; name:str; status:str; status_detail:str
    period:int; clock:str; clock_secs:int; home:TeamState; away:TeamState
    lead:int=0; is_live:bool=False; is_final:bool=False
    is_close:bool=False; blowout:bool=False
    open_spread:Optional[float]=None; open_total:Optional[float]=None
    nba_quarter:int=0
    nba_home_stats:dict=field(default_factory=dict)
    nba_away_stats:dict=field(default_factory=dict)
    mlb_inning_half:str=""; mlb_outs:int=0; mlb_balls:int=0; mlb_strikes:int=0
    mlb_on_base:list=field(default_factory=list)
    mlb_pitcher_home:str=""; mlb_pitcher_away:str=""
    tennis_sets:list=field(default_factory=list)
    tennis_server:str=""; tennis_p1:str=""; tennis_p2:str=""
    def score_str(self): return f"{self.away.name} {self.away.score} - {self.home.score} {self.home.name}"
    def has_name(self,p):
        p=p.lower(); return p in self.home.name.lower() or p in self.away.name.lower() or p in self.name.lower()
    def pct_complete(self):
        if self.is_final: return 1.0
        if self.sport=="NBA":
            e=(self.nba_quarter-1)*720+max(0,720-self.clock_secs); return min(e/2880,0.99)
        if self.sport=="MLB":
            o=(self.period-1)*6+(3 if self.mlb_inning_half=="bottom" else 0)+self.mlb_outs; return min(o/54,0.99)
        if self.sport=="Tennis" and self.tennis_sets:
            return min(sum(1 for s in self.tennis_sets if s[0]+s[1]>0)/5,0.99)
        return 0.0
    def momentum_score(self):
        if not self.is_live: return 0.0
        return self.lead*self.pct_complete()
class ContextCollection:
    def __init__(self,c): self._c=c
    def __iter__(self): return iter(self._c)
    def __len__(self): return len(self._c)
    def live(self): return [x for x in self._c if x.is_live]
    def find_by_name(self,p):
        p=p.lower()
        for c in self._c:
            if c.has_name(p): return c
        return None
def _si(v,d=0):
    try: return int(float(str(v)))
    except: return d
def _sf(v,d=None):
    try: return float(str(v))
    except: return d
def _cts(s):
    try:
        p=s.strip().split(":"); return int(p[0])*60+int(p[1]) if len(p)==2 else int(p[0])
    except: return 0
def _pt(comp):
    t=comp.get("team",{}); s=_si(comp.get("score",0))
    r=comp.get("records",[{}])[0] if comp.get("records") else {}
    sm=r.get("summary","0-0").split("-")
    return TeamState(name=t.get("displayName",t.get("name","?")),abbreviation=t.get("abbreviation","?"),
        score=s,is_home=comp.get("homeAway","")=="home",record_wins=_si(sm[0]),record_loss=_si(sm[1]) if len(sm)>1 else 0)
def _pol(comp):
    ol=comp.get("odds",[]); return (_sf(ol[0].get("spread")),_sf(ol[0].get("overUnder"))) if ol else (None,None)
def _pnba(e):
    try:
        c=e.get("competitions",[{}])[0]; st=e.get("status",{}); stt=st.get("type",{})
        sn=stt.get("name",""); p=_si(st.get("period",1)); cl=st.get("displayClock","")
        comps=c.get("competitors",[{},{}])
        hr=next((x for x in comps if x.get("homeAway")=="home"),comps[0])
        ar=next((x for x in comps if x.get("homeAway")=="away"),comps[1])
        h=_pt(hr); a=_pt(ar); sp,ot=_pol(c)
        def ts(r): return {s.get("name",""):s.get("displayValue","") for s in r.get("statistics",[])}
        return GameContext(sport="NBA",event_id=e.get("id",""),name=e.get("name",""),status=sn,
            status_detail=stt.get("shortDetail",""),period=p,clock=cl,clock_secs=_cts(cl),
            home=h,away=a,lead=h.score-a.score,is_live=sn==STATUS_LIVE,is_final=sn==STATUS_FINAL,
            is_close=abs(h.score-a.score)<=5,blowout=abs(h.score-a.score)>=20,
            open_spread=sp,open_total=ot,nba_quarter=p,nba_home_stats=ts(hr),nba_away_stats=ts(ar))
    except Exception as ex: log.warning(f"[ESPN] NBA:{ex}"); return None
def _pmlb(e):
    try:
        c=e.get("competitions",[{}])[0]; st=e.get("status",{}); stt=st.get("type",{})
        sn=stt.get("name",""); p=_si(st.get("period",1))
        comps=c.get("competitors",[{},{}])
        hr=next((x for x in comps if x.get("homeAway")=="home"),comps[0])
        ar=next((x for x in comps if x.get("homeAway")=="away"),comps[1])
        h=_pt(hr); a=_pt(ar)
        h.hits=_si(hr.get("hits",0)); h.errors=_si(hr.get("errors",0))
        a.hits=_si(ar.get("hits",0)); a.errors=_si(ar.get("errors",0))
        sit=c.get("situation",{}); ih="bottom" if sit.get("isBottomInning",False) else "top"
        ob=[x for x,k in [("1B","onFirst"),("2B","onSecond"),("3B","onThird")] if sit.get(k)]
        def pp(r):
            pr=r.get("probables",[]); return pr[0].get("athlete",{}).get("displayName","") if pr else ""
        sp,ot=_pol(c); ld=h.score-a.score
        return GameContext(sport="MLB",event_id=e.get("id",""),name=e.get("name",""),status=sn,
            status_detail=stt.get("shortDetail",""),period=p,clock=f"Inn {p}",clock_secs=0,
            home=h,away=a,lead=ld,is_live=sn==STATUS_LIVE,is_final=sn==STATUS_FINAL,
            is_close=abs(ld)<=1,blowout=abs(ld)>=5,open_spread=sp,open_total=ot,
            mlb_inning_half=ih,mlb_outs=_si(sit.get("outs",0)),mlb_balls=_si(sit.get("balls",0)),
            mlb_strikes=_si(sit.get("strikes",0)),mlb_on_base=ob,
            mlb_pitcher_home=pp(hr),mlb_pitcher_away=pp(ar))
    except Exception as ex: log.warning(f"[ESPN] MLB:{ex}"); return None
def _pten(e):
    try:
        c=e.get("competitions",[{}])[0]; st=e.get("status",{}); stt=st.get("type",{})
        sn=stt.get("name",""); p=_si(st.get("period",1))
        comps=c.get("competitors",[{},{}])
        p1r=comps[0] if comps else {}; p2r=comps[1] if len(comps)>1 else {}
        def pn(r): a=r.get("athlete",r.get("team",{})); return a.get("displayName",a.get("name","?"))
        def sets(r): return [_si(ls.get("value",0)) for ls in r.get("linescores",[])]
        p1n=pn(p1r); p2n=pn(p2r)
        p1s=_si(p1r.get("score",0)); p2s=_si(p2r.get("score",0))
        ts=list(zip(sets(p1r),sets(p2r)))
        sit=c.get("situation",{}); sid=sit.get("serverId","")
        svr=next((pn(x) for x in comps if str(x.get("id",""))==str(sid)),"")
        h=TeamState(name=p1n,abbreviation="P1",score=p1s,is_home=True)
        a=TeamState(name=p2n,abbreviation="P2",score=p2s,is_home=False)
        return GameContext(sport="Tennis",event_id=e.get("id",""),name=e.get("name",""),status=sn,
            status_detail=stt.get("shortDetail",""),period=p,clock="",clock_secs=0,
            home=h,away=a,lead=p1s-p2s,is_live=sn==STATUS_LIVE,is_final=sn==STATUS_FINAL,
            is_close=abs(p1s-p2s)<=1,blowout=abs(p1s-p2s)>=2,
            tennis_sets=ts,tennis_server=svr,tennis_p1=p1n,tennis_p2=p2n)
    except Exception as ex: log.warning(f"[ESPN] Tennis:{ex}"); return None
class ESPNClient:
    _P={"NBA":_pnba,"MLB":_pmlb,"Tennis_ATP":_pten,"Tennis_WTA":_pten}
    def __init__(self,ttl=ESPN_CACHE_TTL): self._cache={}; self._ttl=ttl
    def get_context(self,sport):
        now=time.time()
        if sport in self._cache:
            ts,col=self._cache[sport]
            if now-ts<self._ttl: return col
        url=ESPN_URLS.get(sport); parser=self._P.get(sport)
        if not url or not parser: return ContextCollection([])
        try:
            r=requests.get(url,timeout=ESPN_TIMEOUT); r.raise_for_status()
            ctxs=[c for e in r.json().get("events",[]) if(c:=parser(e))is not None]
            col=ContextCollection(ctxs); self._cache[sport]=(now,col)
            log.info(f"[ESPN] {sport}: {len(ctxs)} events ({len(col.live())} live)"); return col
        except Exception as ex:
            log.warning(f"[ESPN] {sport} failed:{ex}")
            return self._cache[sport][1] if sport in self._cache else ContextCollection([])
    def get_all(self): return {s:self.get_context(s) for s in ESPN_URLS}
