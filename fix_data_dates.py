import json
import os
from datetime import datetime, timedelta

path = r'C:\Users\DELL\WorkBuddy\独立站灯饰售后分析系统\data\after-sale-data-compact.json'
with open(path, 'r', encoding='utf-8') as f:
    d = json.load(f)

fixed = 0
base = datetime(1899, 12, 30)
for r in d.get('ar', []):
    ct = r.get('ct', '')
    if not ct:
        continue
    # 检查是否为 Excel 序列号（纯数字）
    if ct.replace('.', '').replace('-', '').isdigit() and '-' not in ct:
        try:
            n = float(ct)
            if n > 25569 and n < 100000:
                dt = base + timedelta(days=n)
                r['ct'] = dt.strftime('%Y-%m-%d %H:%M:%S')
                fixed += 1
        except:
            pass

print(f'Fixed {fixed} records')

# 写回
with open(path, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, separators=(',', ':'))

# 更新 version.json
import time
vp = r'C:\Users\DELL\WorkBuddy\独立站灯饰售后分析系统\data\version.json'
with open(vp, 'r', encoding='utf-8') as f:
    v = json.load(f)
v['updated'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
with open(vp, 'w', encoding='utf-8') as f:
    json.dump(v, f, ensure_ascii=False, indent=2)

print(f'File size: {os.path.getsize(path) / 1024 / 1024:.1f} MB')
