# 🔦 独立站灯饰售后工单分析系统

独立站灯饰售后数据分析看板，支持售后工单与销量数据的导入、统计分析和可视化展示。

## 技术栈

- **前端**：纯 HTML + CSS + JavaScript（无框架）
- **图表**：Chart.js 4.4.0
- **数据处理**：Python 3 + pandas
- **部署**：GitHub Pages

## 功能模块

| Tab | 功能 |
|-----|------|
| 📤 上传管理 | Excel 文件上传，年度数据管理 |
| 📋 概况 | 统计卡片、订单 vs 售后趋势图、类型分布 |
| 📈 可视化图表 | 6 张图表（趋势、分布、TOP10 等） |
| 🔍 售后分析 | 5 张分析表（类型、原因、标签、责任方、SKU） |
| 📝 明细数据 | 工单明细查询，支持排序和筛选 |

## 本地开发

```bash
# 用任意 HTTP 服务器启动
python3 -m http.server 8080

# 数据处理
python3 parse_data.py <售后工单.xlsx> <销量数据.xlsx>
```

## 部署

推送到 main 分支后，GitHub Pages 自动部署。

仓库地址：https://github.com/zhongshanms/lamp-after-sale-analysis
