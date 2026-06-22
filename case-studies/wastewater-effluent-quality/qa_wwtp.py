"""
Wastewater effluent data-quality analysis — Tesseract Academy capability demo.
Dataset: Full-Scale Waste Water Treatment Plant Data (Melbourne), CC BY-SA 4.0,
kaggle.com/datasets/d4rklucif3r/full-scale-waste-water-treatment-plant-data
Applies the same QA methodology Tesseract uses for continuous-monitoring data quality:
completeness, stuck-sensor/flatline, robust outliers (MAD), physical-range checks,
baseline drift, and a domain-aware cross-parameter rule (COD must be >= BOD).
"""
import csv, datetime as dt, json
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt, matplotlib.dates as mdates

rows=list(csv.DictReader(open("/tmp/fecm/wwtp/Data-Melbourne_F.csv")))
def col(name):
    out=[]
    for r in rows:
        v=r.get(name,"")
        try: out.append(float(v))
        except: out.append(np.nan)
    return np.array(out)
dates=[dt.date(int(r["year"]),int(r["month"]),int(r["day"])) for r in rows]

# regulated effluent determinands + flows, with physical plausibility bounds
PARAMS={
 "Am (Ammonia, mg/L)":      ("Am",  0.0, 100.0),
 "BOD (mg/L)":              ("BOD", 0.0, 1000.0),
 "COD (mg/L)":              ("COD", 0.0, 2000.0),
 "TN (Total Nitrogen, mg/L)":("TN", 0.0, 300.0),
 "Avg inflow (ML/d)":       ("avg_inflow", 0.0, 1000.0),
 "Avg outflow (ML/d)":      ("avg_outflow",0.0, 1000.0),
}
def qa(v, lo, hi):
    n=len(v); miss=int(np.isnan(v).sum())
    vv=v[~np.isnan(v)]
    completeness=100*(n-miss)/n
    # flatline: >=5 identical consecutive non-nan values
    stuck=0; run=1
    for i in range(1,len(vv)):
        run=run+1 if vv[i]==vv[i-1] else 1
        if run==5: stuck+=1
    oor=int(((vv<lo)|(vv>hi)).sum())
    zeros=int((vv==0).sum())
    med=np.median(vv); mad=np.median(np.abs(vv-med)) or 1e-9
    z=0.6745*(vv-med)/mad; spikes=int((np.abs(z)>5).sum())
    k=max(1,len(vv)//4); drift=float(np.median(vv[-k:])-np.median(vv[:k]))
    return dict(n=n,miss=miss,completeness=completeness,stuck=stuck,oor=oor,
                zeros=zeros,spikes=spikes,drift=drift)

res={name:qa(col(c),lo,hi) for name,(c,lo,hi) in PARAMS.items()}

# domain-aware cross-parameter rule: COD >= BOD (oxygen demand physics)
bod,cod=col("BOD"),col("COD")
mask=~(np.isnan(bod)|np.isnan(cod))
viol=int(((cod<bod)&mask).sum())
ratio=np.where((cod>0)&mask, bod/np.where(cod==0,np.nan,cod), np.nan)
ratio_bad=int((np.nan_to_num(ratio)>1.0).sum())

# chart: 4 effluent determinands
fig,axes=plt.subplots(4,1,figsize=(11,9),sharex=True)
for ax,name in zip(axes,["Am (Ammonia, mg/L)","BOD (mg/L)","COD (mg/L)","TN (Total Nitrogen, mg/L)"]):
    c,lo,hi=PARAMS[name]; v=col(c); r=res[name]
    ax.plot(dates,v,lw=0.7,color="#1f4e79")
    vv=v.copy()
    med=np.nanmedian(vv); mad=np.nanmedian(np.abs(vv-med)) or 1e-9
    z=0.6745*(vv-med)/mad; idx=np.where(np.abs(z)>5)[0]
    if len(idx): ax.scatter([dates[i] for i in idx],v[idx],s=16,color="#c00000",zorder=5,label=f"{len(idx)} spikes")
    ax.set_ylabel(name,fontsize=8); ax.grid(alpha=.25)
    ax.set_title(f"{name} | completeness {r['completeness']:.0f}% | missing {r['miss']} | stuck-runs {r['stuck']} | spikes {r['spikes']} | drift {r['drift']:+.1f}",fontsize=8,loc="left")
    if len(idx): ax.legend(fontsize=7,loc="upper right")
axes[-1].xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
fig.suptitle("Wastewater effluent data-quality QA: Melbourne full-scale WWTP (open data)",fontsize=11,weight="bold")
fig.tight_layout(rect=[0,0,1,0.98])
fig.savefig("/tmp/fecm/wwtp/wwtp_qa.png",dpi=130)

print(f"rows: {len(rows)}  period: {dates[0]} to {dates[-1]}")
print(f"\n{'Determinand':<28}{'Compl%':>8}{'Miss':>6}{'Stuck':>7}{'OOR':>5}{'Zeros':>7}{'Spikes':>8}{'Drift':>9}")
for name in PARAMS:
    r=res[name]
    print(f"{name:<28}{r['completeness']:>8.0f}{r['miss']:>6}{r['stuck']:>7}{r['oor']:>5}{r['zeros']:>7}{r['spikes']:>8}{r['drift']:>+9.1f}")
print(f"\nCross-parameter rule COD>=BOD: {viol} violations (physically impossible); BOD/COD ratio >1: {ratio_bad}")
json.dump({"n":len(rows),"period":[str(dates[0]),str(dates[-1])],"params":res,
           "cod_lt_bod_violations":viol,"bod_over_cod_ratio_bad":ratio_bad},
          open("/tmp/fecm/wwtp/wwtp_qa_summary.json","w"),indent=2)
print("chart -> wwtp_qa.png ; summary -> wwtp_qa_summary.json")
