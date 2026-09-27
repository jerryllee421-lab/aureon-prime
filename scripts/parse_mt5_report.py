#!/usr/bin/env python3
import argparse, html, json, pathlib, re

def clean(s):
    s=re.sub(r"<[^>]+>"," ",s)
    s=html.unescape(s).replace("\xa0"," ")
    return re.sub(r"\s+"," ",s).strip()

def number(s):
    s=s.replace(" ","").replace("%","").replace(",","")
    m=re.search(r"-?\d+(?:\.\d+)?",s)
    return float(m.group(0)) if m else None

def parse_report(path):
    raw=pathlib.Path(path).read_text(encoding="utf-8-sig",errors="ignore")
    rows=re.findall(r"<tr[^>]*>(.*?)</tr>",raw,re.I|re.S)
    metrics={}
    for row in rows:
        cells=[clean(x) for x in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>",row,re.I|re.S)]
        for i,cell in enumerate(cells[:-1]):
            key=cell.rstrip(":")
            if key in {
                "Initial Deposit","Total Net Profit","Gross Profit","Gross Loss",
                "Profit Factor","Expected Payoff","Total Trades","History Quality",
                "Equity Drawdown Relative","Balance Drawdown Relative",
                "Profit Trades (% of total)","Short Trades (won %)","Long Trades (won %)"
            }:
                metrics[key]=cells[i+1]
    out={
        "initial_deposit":number(metrics.get("Initial Deposit","")),
        "net_profit":number(metrics.get("Total Net Profit","")),
        "gross_profit":number(metrics.get("Gross Profit","")),
        "gross_loss":number(metrics.get("Gross Loss","")),
        "profit_factor":number(metrics.get("Profit Factor","")),
        "expected_payoff":number(metrics.get("Expected Payoff","")),
        "total_trades":int(number(metrics.get("Total Trades","")) or 0),
        "history_quality_pct":number(metrics.get("History Quality","")),
        "equity_drawdown_relative_pct":number(metrics.get("Equity Drawdown Relative","")),
        "balance_drawdown_relative_pct":number(metrics.get("Balance Drawdown Relative",""))
    }
    p=metrics.get("Profit Trades (% of total)","")
    m=re.search(r"\(([-\d.]+)%\)",p)
    out["win_rate_pct"]=float(m.group(1)) if m else None
    for src,prefix in [("Short Trades (won %)","short"),("Long Trades (won %)","long")]:
        v=metrics.get(src,"")
        m=re.search(r"(\d+)\s*\(([-\d.]+)%\)",v)
        if m:
            out[prefix+"_trades"]=int(m.group(1))
            out[prefix+"_win_rate_pct"]=float(m.group(2))
    if out["initial_deposit"] is not None and out["net_profit"] is not None:
        out["ending_balance"]=out["initial_deposit"]+out["net_profit"]
    return out

ap=argparse.ArgumentParser()
ap.add_argument("reports",nargs="+")
ap.add_argument("--benchmark")
ap.add_argument("--out",default="comparison.json")
args=ap.parse_args()
parsed={p:parse_report(p) for p in args.reports}
result={"reports":parsed}
if args.benchmark:
    b=json.loads(pathlib.Path(args.benchmark).read_text())
    for p,m in parsed.items():
        score=0.0
        for key,weight in [("net_profit",0.35),("profit_factor",0.20),("total_trades",0.20),("win_rate_pct",0.15),("equity_drawdown_relative_pct",0.10)]:
            bv=b.get(key)
            mv=m.get(key)
            if bv in (None,0) or mv is None: continue
            rel=abs(float(mv)-float(bv))/abs(float(bv))
            score += weight*rel
        m["control_distance_score"]=score
    result["benchmark"]=b
pathlib.Path(args.out).write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result,indent=2))
