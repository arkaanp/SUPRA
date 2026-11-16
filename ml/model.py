"""Direct multi-horizon PyTorch regressor plus a learned wet-hour classifier."""
import datetime as dt
import math
import numpy as np
import torch
from torch import nn
from data import parse_time

LOOKBACK=24
HORIZON=12
INPUT_SIZE=LOOKBACK*4+7

class ForecastNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.layers=nn.Sequential(nn.Linear(INPUT_SIZE,96),nn.SiLU(),nn.Linear(96,48),nn.SiLU(),nn.Linear(48,5))
    def forward(self,x):
        return self.layers(x)

def features(window,latitude,longitude,target,horizon):
    local=target+dt.timedelta(hours=7)
    hour=local.hour/24*2*math.pi
    week=local.weekday()/7*2*math.pi
    return np.concatenate([np.asarray(window,dtype=np.float32).reshape(-1),
        [math.sin(hour),math.cos(hour),math.sin(week),math.cos(week),
         (latitude+6.3)/0.5,(longitude-106.8)/0.5,horizon/HORIZON]])
