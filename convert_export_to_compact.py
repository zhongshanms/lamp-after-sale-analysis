#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将浏览器导出的 JSON 转换为 compact 格式，生成统计数据，用于推送到 GitHub。

用法:
    python convert_export_to_compact.py <导出JSON文件路径>
    python convert_export_to_compact.py "C:/Users/DELL/Desktop/export.json"

可直接拖拽 JSON 文件到 sync.bat 完成转换 + Git 推送。
"""

import json, os, sys
from datetime import datetime
from collections import defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, 'data')
OUTPUT_COMPACT = os.path.join(DATA_DIR, 'after-sale-data-compact.json')
OUTPUT_VERSION = os.path.join(DATA_DIR, 'version.json')

def safe_float(v, default=0.0):
    try: return float(v) if v is not None else default
    except: return default

def safe_int(v, default=1):
    try: return int(float(v)) if v is not None else default
    except: return default

def main(export_file):
    if not os.path.exists(export_file):
        print(f"[错误] 文件不存在: {export_file}")
        sys.exit(1)

    print(f"读取: {export_file}")
    with open(export_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    records = data.get('after_sale_records', [])
    sales = data.get('sales_records', [])
    print(f"  售后工单: {len(records)} 条")
    print(f"  销量记录: {len(sales)} 条")

    # ── 生成售后 compact records ──
    ar = []
    for r in records:
        ar.append({
            'tid': str(r.get('ticket_id', '') or ''),
            't': str(r.get('after_sale_type', '') or ''),
            'p': str(r.get('product_name', '') or ''),
            'sku': str(r.get('sku', '') or ''),
            'r': str(r.get('reason', '') or ''),
            'rs': str(r.get('refund_status', '') or ''),
            'oa': safe_float(r.get('order_amount')),
            'ra': safe_float(r.get('refund_amount')),
            'rq': safe_int(r.get('return_qty')),
            'tg': str(r.get('tag', '') or ''),
            'ct': str(r.get('create_time', '') or str(r.get('create_date', '')) or ''),
            'resp': str(r.get('responsibility', '') or ''),
            'y': safe_int(r.get('year', 0)),
        })

    # ── 生成销量 compact records ──
    sr = []
    for s in sales:
        sr.append({
            'd': str(s.get('date', '') or ''),
            'sku': str(s.get('sku', '') or ''),
            'pn': str(s.get('product_name', '') or ''),
            'sq': safe_int(s.get('sales_qty'), 0),
            'oq': safe_int(s.get('order_qty'), 1),
            'rv': safe_float(s.get('revenue')),
            'pf': str(s.get('platform', '') or ''),
            'y': safe_int(s.get('year', 0)),
        })

    # ── 统计 ──
    # after_sale_types
    type_count = defaultdict(int)
    for r in records:
        type_count[str(r.get('after_sale_type', '') or '')] += 1
    ast = [{'after_sale_type': k, 'count': v, 'pct': round(v/len(records)*100, 1)} for k,v in type_count.items()]
    ast.sort(key=lambda x: -x['count'])

    # reasons
    reason_count = defaultdict(int)
    for r in records:
        reason_count[str(r.get('reason', '') or '')] += 1
    reasons = [{'reason': k, 'count': v, 'pct': round(v/len(records)*100, 1)} for k,v in reason_count.items()]
    reasons.sort(key=lambda x: -x['count'])

    # tags
    tag_count = defaultdict(int)
    for r in records:
        tag_count[str(r.get('tag', '') or '')] += 1
    tags = [{'tag': k, 'count': v, 'pct': round(v/len(records)*100, 1)} for k,v in tag_count.items()]
    tags.sort(key=lambda x: -x['count'])

    # responsibilities
    resp_data = defaultdict(lambda: {'count': 0, 'total_return_qty': 0, 'total_refund': 0.0})
    for r in records:
        k = str(r.get('responsibility', '') or '')
        resp_data[k]['count'] += 1
        resp_data[k]['total_return_qty'] += safe_int(r.get('return_qty'))
        resp_data[k]['total_refund'] += safe_float(r.get('refund_amount'))
    responsibilities = []
    for k, v in resp_data.items():
        responsibilities.append({
            'responsibility': k,
            'count': v['count'],
            'total_return_qty': v['total_return_qty'],
            'total_refund': round(v['total_refund'], 2),
            'pct': round(v['count']/len(records)*100, 1),
            'avg_refund': round(v['total_refund']/v['count'], 2) if v['count'] else 0,
        })
    responsibilities.sort(key=lambda x: -x['count'])

    # sku_top20
    sku_data = defaultdict(lambda: {'product_name': '', 'count': 0, 'total_return_qty': 0, 'total_refund': 0.0})
    for r in records:
        sku = str(r.get('sku', '') or '')
        sku_data[sku]['product_name'] = str(r.get('product_name', '') or '')
        sku_data[sku]['count'] += 1
        sku_data[sku]['total_return_qty'] += safe_int(r.get('return_qty'))
        sku_data[sku]['total_refund'] += safe_float(r.get('refund_amount'))
    sku_top20 = []
    for sku, v in sku_data.items():
        sku_top20.append({
            'sku': sku,
            'product_name': v['product_name'][:80],
            'count': v['count'],
            'total_return_qty': v['total_return_qty'],
            'total_refund': round(v['total_refund'], 2),
        })
    sku_top20.sort(key=lambda x: -x['total_return_qty'])
    sku_top20 = sku_top20[:20]

    # ── 年度 summary ──
    year_summary = {}
    for r in records:
        y = str(safe_int(r.get('year', 0)))
        if y not in year_summary:
            year_summary[y] = {'after_sale_count': 0, 'sales_count': 0, 'total_orders': 0, 'total_return_qty': 0}
        year_summary[y]['after_sale_count'] += 1
        year_summary[y]['total_return_qty'] += safe_int(r.get('return_qty'))
    for s in sales:
        y = str(safe_int(s.get('year', 0)))
        if y not in year_summary:
            year_summary[y] = {'after_sale_count': 0, 'sales_count': 0, 'total_orders': 0, 'total_return_qty': 0}
        year_summary[y]['sales_count'] += 1
        year_summary[y]['total_orders'] += safe_int(s.get('order_qty'), 1)

    years = sorted([int(k) for k in year_summary.keys()])

    # ── 日期范围 ──
    dates_after = []
    for r in records:
        d = r.get('create_date', '') or r.get('create_time', '')
        if d: dates_after.append(str(d)[:10])
    dates_after.sort()

    dates_sales = []
    for s in sales:
        d = s.get('date_date', '') or s.get('date', '')
        if d: dates_sales.append(str(d)[:10])
    dates_sales.sort()

    total_orders = sum(safe_int(s.get('order_qty'), 1) for s in sales)

    now = datetime.now()

    # ── 构建 compact JSON ──
    compact = {
        'm': {
            'generated_at': now.strftime('%Y-%m-%d %H:%M:%S'),
            'total_after_sale': len(records),
            'total_sales': len(sales),
            'total_orders': total_orders,
            'date_range': {
                'after_sale_min': dates_after[0] if dates_after else '',
                'after_sale_max': dates_after[-1] if dates_after else '',
                'sales_min': dates_sales[0] if dates_sales else '',
                'sales_max': dates_sales[-1] if dates_sales else '',
            },
            'years': years,
        },
        'ys': year_summary,
        'st': {
            'after_sale_types': ast,
            'reasons': reasons,
            'tags': tags,
            'responsibilities': responsibilities,
            'sku_top20': sku_top20,
        },
        'ar': ar,
        'sr': sr,
    }

    # ── 写入 compact JSON ──
    print(f"写入: {OUTPUT_COMPACT}")
    with open(OUTPUT_COMPACT, 'w', encoding='utf-8') as f:
        json.dump(compact, f, ensure_ascii=False)
    size_mb = os.path.getsize(OUTPUT_COMPACT) / 1024 / 1024
    print(f"  文件大小: {size_mb:.1f} MB")

    # ── 写入 version.json ──
    version = {
        'version': '1.0.0',
        'updated': now.strftime('%Y-%m-%d %H:%M:%S'),
        'data_checksum': str(os.path.getsize(OUTPUT_COMPACT)),
        'stats': {
            'after_sale_count': len(records),
            'sales_count': len(sales),
        }
    }
    print(f"写入: {OUTPUT_VERSION}")
    with open(OUTPUT_VERSION, 'w', encoding='utf-8') as f:
        json.dump(version, f, ensure_ascii=False, indent=2)

    print("\n✅ 转换完成！")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python convert_export_to_compact.py <导出JSON文件路径>")
        print("示例: python convert_export_to_compact.py export-data-2026-06-13.json")
        sys.exit(1)
    main(sys.argv[1])
