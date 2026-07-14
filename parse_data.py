#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
独立站灯饰售后数据分析系统 - 数据处理脚本
读取售后工单和销量Excel，生成结构化JSON供前端使用
"""

import pandas as pd
import json
import re
import os
from datetime import datetime, timedelta
from collections import defaultdict

# ==================== 配置 ====================
VALID_SKU_PREFIXES = {'DJ', 'CL', 'PL', 'CF', 'WL', 'CD', 'TL', 'FL'}
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')

# 输入文件路径（默认值，可通过命令行参数覆盖）
DEFAULT_AFTER_SALE_FILE = os.path.expanduser("~/Desktop/独立站灯饰售后工单2025-01-01~2026-05-31.xlsx")
DEFAULT_SALES_FILE = os.path.expanduser("~/Desktop/独立站灯饰销量统计2025-01-01~2026-05-31.xlsx")


# ==================== 责任方分类 ====================
def map_responsibility(tag, reason):
    """
    根据标签(tag)和售后原因(reason)判断责任方
    优先级从高到低：
    1. D-采购-越兴相关 → 含"越兴"
    2. B-仓库-发货问题 → 发错货/漏发/发错/错发/少发/多发
    3. F-物流-运输问题 → 物流/运输/快递/破损/丢件/丢失/海关/转运/第三方
    4. A-品控-品质问题 → 品质/质量/灯不亮/不亮/外观/烧坏/烧毁/安全/隐患/故障/损坏/缺陷/不良/开裂/生锈/掉漆/刮花/划痕
    5. C-客户-个人原因 → 不喜欢/不想要/无理由/下错/下单错/尺寸/大小/颜色/买错/拍错/重复/不要了/退货
    6. E-运营-信息问题 → 描述/说明/图物/不符/安装/网页/listing/页面/色差/参数
    默认 → C-客户-个人原因
    """
    text = f"{tag or ''} {reason or ''}"

    # 1. 采购-越兴相关
    if '越兴' in text:
        return 'D-采购-越兴相关'

    # 2. 仓库-发货问题
    warehouse_keywords = ['发错货', '漏发', '发错', '错发', '少发', '多发']
    for kw in warehouse_keywords:
        if kw in text:
            return 'B-仓库-发货问题'

    # 3. 物流-运输问题
    logistics_keywords = ['物流', '运输', '快递', '破损', '丢件', '丢失', '海关', '转运', '第三方']
    for kw in logistics_keywords:
        if kw in text:
            return 'F-物流-运输问题'

    # 4. 品控-品质问题
    quality_keywords = ['品质', '质量', '灯不亮', '不亮', '外观', '烧坏', '烧毁', '安全', '隐患',
                        '故障', '损坏', '缺陷', '不良', '开裂', '生锈', '掉漆', '刮花', '划痕', '工艺']
    for kw in quality_keywords:
        if kw in text:
            return 'A-品控-品质问题'

    # 5. 客户-个人原因
    customer_keywords = ['不喜欢', '不想要', '无理由', '下错', '下单错', '尺寸', '大小', '颜色',
                         '买错', '拍错', '重复', '不要了', '退货', '个人', '不满', '折扣',
                         '不需要', '风格', '色差', '交期']
    for kw in customer_keywords:
        if kw in text:
            return 'C-客户-个人原因'

    # 6. 运营-信息问题
    ops_keywords = ['描述', '说明', '图物', '不符', '安装', '网页', 'listing', '页面', '参数']
    for kw in ops_keywords:
        if kw in text:
            return 'E-运营-信息问题'

    return 'C-客户-个人原因'


# ==================== 日期解析 ====================
def parse_date(val):
    """解析多种日期格式"""
    if pd.isna(val):
        return None
    if isinstance(val, (int, float)):
        # Excel序列号
        if val > 25569:
            try:
                from datetime import timedelta
                base = datetime(1899, 12, 30)
                return base + timedelta(days=int(val))
            except:
                pass
    val_str = str(val).strip()

    # ISO格式: 2026-01-15 10:30:00
    m = re.match(r'(\d{4}-\d{2}-\d{2})', val_str)
    if m:
        try:
            return datetime.strptime(m.group(1), '%Y-%m-%d')
        except:
            pass

    # 中文日期: 2026年1月15日
    m = re.match(r'(\d{4})年(\d{1,2})月(\d{1,2})日', val_str)
    if m:
        try:
            return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except:
            pass

    # 复合列尝试提取ISO日期
    for part in val_str.split('\n'):
        m = re.match(r'(\d{4}-\d{2}-\d{2})', part.strip())
        if m:
            try:
                return datetime.strptime(m.group(1), '%Y-%m-%d')
            except:
                pass

    return None


# ==================== 分组粒度 ====================
def format_period(dt, granularity='month'):
    """按粒度格式化日期"""
    if granularity == 'month':
        return dt.strftime('%Y-%m')
    elif granularity == 'week':
        iso = dt.isocalendar()
        return f"{iso[0]}-W{iso[1]:02d}"
    elif granularity == 'day':
        return dt.strftime('%Y-%m-%d')
    return dt.strftime('%Y-%m')


# ==================== 销售额解析 ====================
def parse_amount(val):
    """解析金额字符串，去掉￥符号"""
    if pd.isna(val):
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    val_str = str(val).replace('￥', '').replace('¥', '').replace(',', '').strip()
    try:
        return float(val_str)
    except:
        return 0.0


# ==================== 主处理流程 ====================
def process_data(after_sale_file, sales_file, output_dir=DATA_DIR):
    os.makedirs(output_dir, exist_ok=True)

    print(f"读取售后工单: {after_sale_file}")
    df_after = pd.read_excel(after_sale_file, sheet_name=0)

    print(f"读取销量数据: {sales_file}")
    df_sales = pd.read_excel(sales_file, sheet_name=0)

    # ---- 列名标准化 ----
    col_map_after = {
        '售后工单单号': 'ticket_id',
        '售后类型': 'after_sale_type',
        '系统单号/平台单号': 'order_id',
        '产品名称': 'product_name',
        'Sku': 'sku',
        '售后原因': 'reason',
        '退款状态': 'refund_status',
        '订单金额': 'order_amount',
        '退款金额': 'refund_amount',
        '退货数量': 'return_qty',
        '标签': 'tag',
        '订购时间': 'order_time',
        '创建时间': 'create_time',
    }
    df_after = df_after.rename(columns=col_map_after)

    col_map_sales = {
        '时间': 'date',
        'SKU': 'sku',
        '品名': 'product_name',
        '标题': 'title',
        '单体属性': 'attribute',
        '店铺': 'shop',
        '平台': 'platform',
        '销量': 'sales_qty',
        '订单量': 'order_qty',
        '销售额': 'revenue',
    }
    df_sales = df_sales.rename(columns=col_map_sales)

    # ---- SKU过滤（仅保留灯饰产品） ----
    print(f"  售后工单原始行数: {len(df_after)}")
    df_after = df_after[df_after['sku'].str[:2].isin(VALID_SKU_PREFIXES)].copy()
    print(f"  SKU过滤后: {len(df_after)}")

    print(f"  销量原始行数: {len(df_sales)}")
    df_sales = df_sales[df_sales['sku'].str[:2].isin(VALID_SKU_PREFIXES)].copy()
    print(f"  SKU过滤后: {len(df_sales)}")

    # ---- 日期解析 ----
    df_after['create_dt'] = df_after['create_time'].apply(parse_date)
    df_after['order_dt'] = df_after['order_time'].apply(parse_date)
    df_after['year'] = df_after['create_dt'].apply(lambda x: x.year if x else None)

    df_sales['date_dt'] = df_sales['date'].apply(parse_date)
    df_sales['year'] = df_sales['date_dt'].apply(lambda x: x.year if x else None)

    # ---- 去重（按工单号） ----
    df_after = df_after.drop_duplicates(subset=['ticket_id', 'sku'], keep='first')

    # ---- 责任方分类 ----
    df_after['responsibility'] = df_after.apply(
        lambda row: map_responsibility(row.get('tag', ''), row.get('reason', '')), axis=1
    )

    # ---- 金额解析（销量表） ----
    df_sales['revenue_num'] = df_sales['revenue'].apply(parse_amount)

    # ---- 填充NaN ----
    df_after['order_amount'] = df_after['order_amount'].fillna(0)
    df_after['refund_amount'] = df_after['refund_amount'].fillna(0)
    df_after['return_qty'] = df_after['return_qty'].fillna(1).astype(int)
    df_after['refund_status'] = df_after['refund_status'].fillna('未知')

    # ---- 按年度分组统计 ----
    years = sorted(set(df_after['year'].dropna()) | set(df_sales['year'].dropna()))
    print(f"  涵盖年度: {years}")

    # ---- 生成年度数据 JSON ----
    year_data = {}
    for y in years:
        after_y = df_after[df_after['year'] == y]
        sales_y = df_sales[df_sales['year'] == y]

        year_data[str(y)] = {
            'after_sale_count': int(len(after_y)),
            'sales_count': int(len(sales_y)),
            'total_orders': int(sales_y['order_qty'].sum()),
            'total_return_qty': int(after_y['return_qty'].sum()),
        }

    # ---- 生成工单明细 ----
    after_sale_records = []
    for _, row in df_after.iterrows():
        record = {
            'ticket_id': str(int(row['ticket_id'])) if pd.notna(row['ticket_id']) else '',
            'after_sale_type': str(row['after_sale_type']) if pd.notna(row['after_sale_type']) else '',
            'order_id': str(row['order_id']).replace('\n', ' | ') if pd.notna(row['order_id']) else '',
            'product_name': str(row['product_name']) if pd.notna(row['product_name']) else '',
            'sku': str(row['sku']) if pd.notna(row['sku']) else '',
            'reason': str(row['reason']) if pd.notna(row['reason']) else '',
            'refund_status': str(row['refund_status']) if pd.notna(row['refund_status']) else '',
            'order_amount': float(row['order_amount']) if pd.notna(row['order_amount']) else 0,
            'refund_amount': float(row['refund_amount']) if pd.notna(row['refund_amount']) else 0,
            'return_qty': int(row['return_qty']) if pd.notna(row['return_qty']) else 1,
            'tag': str(row['tag']) if pd.notna(row['tag']) else '',
            'order_time': str(row['order_time']) if pd.notna(row['order_time']) else '',
            'create_time': str(row['create_time']) if pd.notna(row['create_time']) else '',
            'create_date': row['create_dt'].strftime('%Y-%m-%d') if row['create_dt'] else '',
            'responsibility': str(row['responsibility']) if pd.notna(row['responsibility']) else '',
            'year': int(row['year']) if pd.notna(row['year']) else 0,
        }
        after_sale_records.append(record)

    # ---- 生成销量明细 ----
    sales_records = []
    for _, row in df_sales.iterrows():
        record = {
            'date': str(row['date']) if pd.notna(row['date']) else '',
            'sku': str(row['sku']) if pd.notna(row['sku']) else '',
            'product_name': str(row['product_name']) if pd.notna(row['product_name']) else '',
            'title': str(row['title']) if pd.notna(row['title']) else '',
            'attribute': str(row.get('attribute', '')) if pd.notna(row.get('attribute', '')) else '',
            'shop': str(row['shop']) if pd.notna(row['shop']) else '',
            'platform': str(row['platform']) if pd.notna(row['platform']) else '',
            'sales_qty': int(row['sales_qty']) if pd.notna(row['sales_qty']) else 0,
            'order_qty': int(row['order_qty']) if pd.notna(row['order_qty']) else 1,
            'revenue': float(row['revenue_num']) if pd.notna(row['revenue_num']) else 0,
            'formatted_revenue': str(row['revenue']) if pd.notna(row['revenue']) else '',
            'date_date': row['date_dt'].strftime('%Y-%m-%d') if row['date_dt'] else '',
            'year': int(row['year']) if pd.notna(row['year']) else 0,
        }
        sales_records.append(record)

    # ---- 生成售后服务类型统计 ----
    after_sale_type_stats = (
        df_after.groupby('after_sale_type').size()
        .reset_index(name='count')
        .assign(pct=lambda x: (x['count'] / x['count'].sum() * 100).round(1))
        .sort_values('count', ascending=False)
        .to_dict('records')
    )

    # ---- 生成售后原因统计 ----
    reason_stats = (
        df_after.groupby('reason').size()
        .reset_index(name='count')
        .assign(pct=lambda x: (x['count'] / x['count'].sum() * 100).round(1))
        .sort_values('count', ascending=False)
        .to_dict('records')
    )

    # ---- 生成标签统计 ----
    tag_stats = (
        df_after.groupby('tag').size()
        .reset_index(name='count')
        .assign(pct=lambda x: (x['count'] / x['count'].sum() * 100).round(1))
        .sort_values('count', ascending=False)
        .to_dict('records')
    )

    # ---- 生成责任方统计 ----
    resp_stats = (
        df_after.groupby('responsibility').agg(
        count=('ticket_id', 'size'),
        total_return_qty=('return_qty', 'sum'),
        total_refund=('refund_amount', 'sum')
    ).reset_index()
    )
    resp_stats['pct'] = (resp_stats['count'] / resp_stats['count'].sum() * 100).round(1)
    resp_stats['avg_refund'] = (resp_stats['total_refund'] / resp_stats['count']).round(2)
    resp_stats = resp_stats.sort_values('count', ascending=False).to_dict('records')

    # ---- 生成退货数量TOP20 SKU ----
    sku_top = (
        df_after.groupby('sku').agg(
        product_name=('product_name', 'first'),
        count=('ticket_id', 'size'),
        total_return_qty=('return_qty', 'sum'),
        total_refund=('refund_amount', 'sum')
    ).reset_index()
    .sort_values('total_return_qty', ascending=False)
    .head(20)
    .to_dict('records')
    )

    # ---- 构建完整输出JSON ----
    output = {
        'meta': {
            'generated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'total_after_sale': int(len(df_after)),
            'total_sales': int(len(df_sales)),
            'total_orders': int(df_sales['order_qty'].sum()),
            'date_range': {
                'after_sale_min': df_after['create_dt'].min().strftime('%Y-%m-%d') if df_after['create_dt'].min() else '',
                'after_sale_max': df_after['create_dt'].max().strftime('%Y-%m-%d') if df_after['create_dt'].max() else '',
                'sales_min': df_sales['date_dt'].min().strftime('%Y-%m-%d') if df_sales['date_dt'].min() else '',
                'sales_max': df_sales['date_dt'].max().strftime('%Y-%m-%d') if df_sales['date_dt'].max() else '',
            },
            'years': [int(y) for y in years],
        },
        'year_summary': year_data,
        'after_sale_records': after_sale_records,
        'sales_records': sales_records,
        'statistics': {
            'after_sale_types': after_sale_type_stats,
            'reasons': reason_stats,
            'tags': tag_stats,
            'responsibilities': resp_stats,
            'sku_top20': sku_top,
        },
    }

    # ---- 写入JSON ----
    output_path = os.path.join(output_dir, 'after-sale-data.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    file_size = os.path.getsize(output_path)
    print(f"\n数据已生成: {output_path}")
    print(f"  文件大小: {file_size:,} bytes ({file_size/1024/1024:.1f} MB)")
    print(f"  工单记录数: {len(after_sale_records)}")
    print(f"  销量记录数: {len(sales_records)}")

    # ---- 生成version.json ----
    version = {
        'version': '1.0.0',
        'updated': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'data_checksum': str(file_size),  # 简易校验
        'stats': {
            'after_sale_count': len(after_sale_records),
            'sales_count': len(sales_records),
        }
    }
    version_path = os.path.join(output_dir, 'version.json')
    with open(version_path, 'w', encoding='utf-8') as f:
        json.dump(version, f, ensure_ascii=False, indent=2)
    print(f"  版本文件: {version_path}")

    return output


def main():
    import sys
    after_sale_file = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_AFTER_SALE_FILE
    sales_file = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_SALES_FILE

    if not os.path.exists(after_sale_file):
        print(f"错误: 售后工单文件不存在: {after_sale_file}")
        sys.exit(1)
    if not os.path.exists(sales_file):
        print(f"错误: 销量文件不存在: {sales_file}")
        sys.exit(1)

    process_data(after_sale_file, sales_file)


if __name__ == '__main__':
    main()
