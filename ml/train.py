#!/usr/bin/env python3
"""Download real hourly history, train PyTorch, and evaluate chronological holdouts."""
import argparse
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import numpy as np
import torch
from data import FIELDS, ROOT, SITES, SOURCES, history, parse_time, utcnow
from model import ForecastNet, LOOKBACK, HORIZON, features

def split_examples(sites,cut1,cut2):
    groups=[[],[],[]]
    for site in sites:
        rows=site['rows']
        times=[parse_time(r['time']) for r in rows]
        for i in range(LOOKBACK-1,len(rows)-1):
            window=rows[i-LOOKBACK+1:i+1]
            if times[i]-times[i-LOOKBACK+1] != dt.timedelta(hours=LOOKBACK-1): continue
            for horizon in range(1,HORIZON+1):
                j=i+horizon
                if j>=len(rows) or times[j]-times[i] != dt.timedelta(hours=horizon): continue
                # Partition by issue time AND target time. No labels straddle a split.
                split=0 if times[j]<cut1 else 1 if times[i]>=cut1 and times[j]<cut2 else 2 if times[i]>=cut2 else None
                if split is None: continue
                groups[split].append((features([r['values'] for r in window],*site['point'],times[j],horizon),
                                      rows[j]['values'],rows[i]['values']))
    return groups

def metrics(pred,true,base,prob):
    return {'mae':dict(zip(FIELDS,np.abs(pred-true).mean(0).tolist())),
            'persistence_mae':dict(zip(FIELDS,np.abs(base-true).mean(0).tolist())),
            'rain_brier':float(((prob-(true[:,1]>=0.1))**2).mean())}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--days',type=int,default=60)
    parser.add_argument('--epochs',type=int,default=100)
    parser.add_argument('--reuse-data',action='store_true')
    args=parser.parse_args()
    if not 30<=args.days<=92 or not 1<=args.epochs<=500: parser.error('Use 30–92 days and 1–500 epochs')
    torch.set_num_threads(2);torch.manual_seed(42);np.random.seed(42)
    data_path=ROOT/'data/history.json';data_path.parent.mkdir(parents=True,exist_ok=True)
    if args.reuse_data:
        dataset=json.loads(data_path.read_text())
    else:
        dataset={'fetched_at':utcnow().isoformat(),'sources':SOURCES,'sites':[]}
        for point in SITES:
            print(f'Downloading hourly history at {point}',flush=True)
            rows=history(*point,days=args.days,cache_dir=ROOT/'data/raw')
            if len(rows)<24*25: raise ValueError('Insufficient usable history')
            dataset['sites'].append({'point':point,'rows':rows})
        data_path.write_text(json.dumps(dataset))
    last=min(parse_time(s['rows'][-1]['time']) for s in dataset['sites'])
    cut2=last-dt.timedelta(days=7);cut1=cut2-dt.timedelta(days=7)
    groups=split_examples(dataset['sites'],cut1,cut2)
    if any(len(g)<100 for g in groups): raise ValueError('Insufficient chronological train/validation/test rows')
    arrays=[]
    for g in groups:
        x,y,base=map(lambda values:np.asarray(values,dtype=np.float32),zip(*g))
        arrays.append((x,y,base))
    xmean=arrays[0][0].mean(0);xstd=np.maximum(arrays[0][0].std(0),0.1)
    def transformed(y,base):
        z=y.copy();z[:,[0,2,3]]-=base[:,[0,2,3]];z[:,1]=np.log1p(y[:,1]);return z
    ytrain=transformed(arrays[0][1],arrays[0][2]);ymean=ytrain.mean(0);ystd=np.maximum(ytrain.std(0),0.1)
    tensors=[(torch.tensor((x-xmean)/xstd),torch.tensor((transformed(y,b)-ymean)/ystd),
              torch.tensor((y[:,1]>=0.1).astype(np.float32))) for x,y,b in arrays]
    net=ForecastNet();optimizer=torch.optim.AdamW(net.parameters(),lr=0.001,weight_decay=0.01)
    best_loss=float('inf');best=None;best_epoch=0
    tx,ty,wet=tensors[0]
    for epoch in range(args.epochs):
        net.train()
        for indices in torch.randperm(len(tx)).split(512):
            out=net(tx[indices]);loss=torch.nn.functional.smooth_l1_loss(out[:,:4],ty[indices])+0.3*torch.nn.functional.binary_cross_entropy_with_logits(out[:,4],wet[indices])
            optimizer.zero_grad();loss.backward();torch.nn.utils.clip_grad_norm_(net.parameters(),1.0);optimizer.step()
        net.eval()
        with torch.inference_mode():
            out=net(tensors[1][0]);vloss=float(torch.nn.functional.smooth_l1_loss(out[:,:4],tensors[1][1])+0.3*torch.nn.functional.binary_cross_entropy_with_logits(out[:,4],tensors[1][2]))
        if vloss<best_loss:best_loss=vloss;best=copy.deepcopy(net.state_dict());best_epoch=epoch+1
        if (epoch+1)%10==0: print(f'Epoch {epoch+1}: validation loss {vloss:.4f}',flush=True)
        if epoch+1-best_epoch>=15: break
    net.load_state_dict(best);net.eval()
    reports={}
    for label,index in [('validation',1),('test',2)]:
        with torch.inference_mode():out=net(tensors[index][0]).numpy()
        pred=out[:,:4]*ystd+ymean
        pred[:,[0,2,3]]+=arrays[index][2][:,[0,2,3]]
        pred[:,1]=np.expm1(np.clip(pred[:,1],0,6));pred[:,2:]=np.maximum(pred[:,2:],0)
        reports[label]=metrics(pred,arrays[index][1],arrays[index][2],1/(1+np.exp(-np.clip(out[:,4],-50,50))))
        if label=='validation':error90=np.quantile(np.abs(pred-arrays[index][1]),0.9,axis=0).tolist()
    trained_at=utcnow().isoformat()
    card={'model_id':'supra-hourly-'+trained_at[:19].replace(':','').replace('-',''),
          'framework':'PyTorch','torch_version':str(torch.__version__),'architecture':'MLP 103→96→48→5, direct horizons 1–12h',
          'trained_at':trained_at,'training_end':cut1.isoformat(),'validation_end':cut2.isoformat(),'data_through':last.isoformat(),
          'dataset_sha256':hashlib.sha256(data_path.read_bytes()).hexdigest(),'sites':SITES,'sources':SOURCES,
          'samples':dict(zip(['train','validation','test'],map(len,groups))), 'best_epoch':best_epoch,
          'metrics':reports,'validation_absolute_error_90':dict(zip(FIELDS,error90)),
          'status':'experimental','traffic_status':'unavailable: no validated historical traffic training set',
          'limitations':['Targets are weather/CAMS model history, not independent station observations.',
                         'Spatial coverage is regional; results are not street-level measurements.',
                         'Validation error ranges are empirical, not calibrated safety guarantees.',
                         'Rain probability is a learned wet-hour classifier (>=0.1 mm), not an official warning.']}
    artifacts=ROOT/'artifacts';artifacts.mkdir(exist_ok=True)
    checkpoint={'state_dict':best,'xmean':torch.tensor(xmean),'xstd':torch.tensor(xstd),'ymean':torch.tensor(ymean),'ystd':torch.tensor(ystd),'card':card}
    temporary=artifacts/'forecast.pt.new';torch.save(checkpoint,temporary);temporary.replace(artifacts/'forecast.pt')
    (artifacts/'model_card.json').write_text(json.dumps(card,indent=2)+'\n')
    print(json.dumps(card,indent=2))
if __name__=='__main__':main()
