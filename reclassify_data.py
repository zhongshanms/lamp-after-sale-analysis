"""重新对现有 compact JSON 中的所有记录执行责任方分类（使用更新后的关键词表）"""
import json, os
from collections import Counter

path = r'C:\Users\DELL\WorkBuddy\独立站灯饰售后分析系统\data\after-sale-data-compact.json'
with open(path, 'r', encoding='utf-8') as f:
    d = json.load(f)

# 更新后的关键词分类表（与 convert_lamp_to_compact.py 同步）
def classify(tag, reason):
    text = f"{tag or ''} {reason or ''}"
    if "越兴" in text:
        return "D-采购-越兴相关"
    for kw in ["停产", "晚发货", "下架不可售", "漏采"]:
        if kw in text:
            return "D-采购-越兴相关"
    for kw in ["发错货", "漏发", "发错", "错发", "少发", "多发"]:
        if kw in text:
            return "B-仓库-发货问题"
    for kw in ["物流", "运输", "快递", "破损", "丢件", "丢失", "海关", "转运", "第三方"]:
        if kw in text:
            return "F-物流-运输问题"
    for kw in ["品质", "质量", "灯不亮", "不亮", "外观", "烧坏", "烧毁", "安全", "隐患",
               "故障", "损坏", "缺陷", "不良", "开裂", "生锈", "掉漆", "刮花", "划痕", "工艺", "尺寸", "颜色"]:
        if kw in text:
            return "A-品控-品质问题"
    for kw in ["不喜欢", "不想要", "无理由", "下错", "下单错", "大小",
               "买错", "拍错", "重复", "不要了", "退货", "个人", "不满", "折扣",
               "不需要", "风格", "色差", "交期"]:
        if kw in text:
            return "C-客户-个人原因"
    for kw in ["描述", "说明", "图物", "不符", "安装", "网页", "listing", "页面", "参数"]:
        if kw in text:
            return "E-运营-信息问题"
    return "C-客户-个人原因"

changed = 0
resp_counter = Counter()

for r in d.get('ar', []):
    old = r.get('resp', '')
    new = classify(r.get('tg', ''), r.get('r', ''))
    if old != new:
        changed += 1
        r['resp'] = new
    resp_counter[new] += 1

# 更新统计
if d.get('st', {}).get('responsibilities'):
    new_resp = []
    for item in d['st']['responsibilities']:
        name = item.get('responsibility', '')
        new_resp.append({**item, 'count': resp_counter.get(name, item.get('count', 0))})
    d['st']['responsibilities'] = new_resp

print(f'Changed: {changed} records')
print(f'New distribution:')
for k, v in resp_counter.most_common():
    pct = round(v / len(d['ar']) * 100, 1)
    print(f'  {k}: {v} ({pct}%)')

# Write
with open(path, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, separators=(',', ':'))
print(f'\nWritten: {os.path.getsize(path) / 1024 / 1024:.1f} MB')
