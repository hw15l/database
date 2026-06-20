"""
生成27种图表测试Excel + 逐一渲染验证
运行: python generate_test_data.py
"""
import os, sys, traceback
import pandas as pd
import numpy as np

np.random.seed(42)

OUTPUT_EXCEL_DIR = os.path.join(os.path.dirname(__file__), 'test_data')
os.makedirs(OUTPUT_EXCEL_DIR, exist_ok=True)

CHART_CONFIGS = [
    ('bar', '柱状图测试', lambda: pd.DataFrame({
        '产品': ['手机', '电脑', '平板', '耳机', '手表', '音箱', '键盘', '鼠标'],
        '销量': [1520, 980, 760, 1340, 890, 450, 670, 1100]
    })),
    ('grouped_bar', '分组柱状图测试', lambda: pd.DataFrame({
        '季度': ['Q1', 'Q2', 'Q3', 'Q4'],
        '线上销售': [320, 450, 510, 680],
        '线下销售': [280, 350, 390, 420],
        '批发销售': [150, 200, 180, 260]
    })),
    ('stacked_bar', '堆叠柱状图测试', lambda: pd.DataFrame({
        '月份': ['1月', '2月', '3月', '4月', '5月', '6月'],
        '食品': [120, 135, 145, 130, 160, 155],
        '服装': [80, 95, 110, 100, 120, 105],
        '电子': [200, 180, 220, 250, 230, 270]
    })),
    ('line', '折线图测试', lambda: pd.DataFrame({
        '日期': [f'Day{i}' for i in range(1, 21)],
        '温度': [15 + 10*np.sin(i/3) + np.random.normal(0,1) for i in range(20)]
    })),
    ('multi_line', '多折线图测试', lambda: pd.DataFrame({
        '周次': [f'W{i}' for i in range(1, 13)],
        '北京': np.cumsum(np.random.randint(5, 20, 12)),
        '上海': np.cumsum(np.random.randint(8, 25, 12)),
        '广州': np.cumsum(np.random.randint(3, 18, 12)),
        '深圳': np.cumsum(np.random.randint(6, 22, 12))
    })),
    ('scatter', '散点图测试', lambda: pd.DataFrame({
        '类别': np.random.choice(['A组', 'B组', 'C组'], 60),
        '身高cm': np.random.normal(170, 8, 60).round(1),
        '体重kg': np.random.normal(65, 10, 60).round(1)
    })),
    ('bubble', '气泡图测试', lambda: pd.DataFrame({
        '城市': ['北京','上海','广州','深圳','杭州','成都','武汉','南京','重庆','西安'],
        'GDP万亿': [4.16, 4.72, 2.88, 3.24, 1.92, 2.08, 1.89, 1.68, 2.94, 1.15],
        '人口万': [2189, 2487, 1874, 1768, 1237, 2119, 1373, 942, 3212, 1295],
        '面积km2': [16410, 6340, 7434, 1997, 16853, 14335, 8569, 6587, 82400, 10752]
    })),
    ('pie', '饼图测试', lambda: pd.DataFrame({
        '浏览器': ['Chrome', 'Safari', 'Edge', 'Firefox', 'Opera', 'Others'],
        '市场份额': [64.5, 18.7, 5.2, 3.1, 2.8, 5.7]
    })),
    ('donut', '环形图测试', lambda: pd.DataFrame({
        '支出类别': ['房租', '餐饮', '交通', '娱乐', '教育', '医疗', '储蓄'],
        '金额': [3500, 2200, 800, 600, 1500, 400, 2000]
    })),
    ('heatmap', '热力图测试', lambda: pd.DataFrame({
        '数学': np.random.randint(60, 100, 30),
        '语文': np.random.randint(65, 98, 30),
        '英语': np.random.randint(55, 100, 30),
        '物理': np.random.randint(50, 95, 30),
        '化学': np.random.randint(58, 97, 30),
        '生物': np.random.randint(62, 99, 30)
    })),
    ('boxplot', '箱线图测试', lambda: pd.DataFrame({
        '班级': np.repeat(['一班','二班','三班','四班'], 25),
        '成绩': np.concatenate([
            np.random.normal(78, 8, 25), np.random.normal(82, 6, 25),
            np.random.normal(75, 10, 25), np.random.normal(85, 5, 25)
        ]).round(1)
    })),
    ('violin', '小提琴图测试', lambda: pd.DataFrame({
        '实验组': np.repeat(['对照组','实验A','实验B'], 40),
        '反应时间ms': np.concatenate([
            np.random.normal(350, 50, 40), np.random.normal(280, 40, 40),
            np.random.normal(310, 60, 40)
        ]).round(0)
    })),
    ('radar', '雷达图测试', lambda: pd.DataFrame({
        '选手': ['张三', '李四', '王五', '赵六'],
        '力量': [85, 72, 90, 68],
        '速度': [78, 88, 65, 92],
        '技术': [90, 80, 75, 85],
        '耐力': [70, 85, 88, 76],
        '防守': [82, 76, 92, 80]
    })),
    ('gantt', '甘特图测试', lambda: pd.DataFrame({
        '任务': ['需求分析','系统设计','前端开发','后端开发','测试','部署','验收','培训'],
        '开始周': [1, 3, 5, 5, 9, 11, 12, 13],
        '持续周数': [2, 2, 4, 4, 2, 1, 1, 1]
    })),
    ('sankey', '桑基图测试', lambda: pd.DataFrame({
        '来源': ['搜索引擎','搜索引擎','社交媒体','社交媒体','直接访问','直接访问','邮件营销','邮件营销'],
        '目标': ['首页','产品页','首页','注册页','首页','产品页','首页','注册页'],
        '流量': [5000, 3000, 2000, 1500, 1800, 1200, 800, 600]
    })),
    ('treemap', '矩形树图测试', lambda: pd.DataFrame({
        '部门': ['研发部','市场部','销售部','人力部','财务部','运维部','法务部','行政部','产品部','设计部'],
        '人数': [120, 45, 80, 25, 18, 35, 12, 20, 30, 22]
    })),
    ('parallel', '平行坐标图测试', lambda: pd.DataFrame({
        '型号': [f'Model-{chr(65+i)}' for i in range(15)],
        '价格': np.random.randint(2000, 8000, 15),
        '性能': np.random.randint(60, 100, 15),
        '续航h': np.random.uniform(4, 12, 15).round(1),
        '重量g': np.random.randint(150, 400, 15),
        '评分': np.random.uniform(3.5, 5.0, 15).round(1)
    })),
    ('wordcloud', '词云测试', lambda: pd.DataFrame({
        '关键词': ['人工智能','机器学习','深度学习','自然语言处理','计算机视觉',
                  '数据挖掘','神经网络','大数据','云计算','物联网',
                  '区块链','量子计算','边缘计算','数据科学','算法',
                  'Python','TensorFlow','PyTorch','Transformer','GPT',
                  '卷积网络','循环网络','注意力机制','强化学习','迁移学习',
                  '特征工程','模型优化','超参数','梯度下降','反向传播'],
        '热度': [98,92,88,85,82,78,75,90,72,68,65,55,58,80,88,95,76,79,86,94,70,62,83,71,67,73,69,60,77,74]
    })),
    ('surface3d', '3D曲面图测试', lambda: (lambda x,y: pd.DataFrame({
        'X': x.ravel(), 'Y': y.ravel(),
        'Z': (np.sin(np.sqrt(x**2 + y**2))).ravel().round(4)
    }))(
        *np.meshgrid(np.linspace(-3, 3, 15), np.linspace(-3, 3, 15))
    )),
    ('pareto', '帕累托图测试', lambda: pd.DataFrame({
        '缺陷类型': ['界面错误','功能异常','性能问题','兼容性','安全漏洞','文档缺失','数据错误','其他'],
        '出现次数': [45, 38, 25, 18, 12, 8, 6, 3]
    })),
    ('candlestick', 'K线图测试', lambda: (lambda prices: pd.DataFrame({
        '开盘': prices[:-1],
        '最高': prices[:-1] + np.random.uniform(0.5, 3, 19),
        '最低': prices[:-1] - np.random.uniform(0.5, 3, 19),
        '收盘': prices[1:]
    }))(np.cumsum(np.random.normal(0.1, 1.5, 20)) + 100)),
    ('area', '面积图测试', lambda: pd.DataFrame({
        '月份': [f'{i}月' for i in range(1, 13)],
        'CPU使用率': [45, 52, 48, 65, 72, 68, 55, 80, 75, 60, 50, 45],
        '内存使用率': [60, 58, 62, 70, 75, 78, 72, 85, 80, 68, 65, 60],
        '磁盘IO': [30, 35, 32, 40, 55, 50, 38, 65, 58, 42, 35, 30]
    })),
    ('venn', '韦恩图测试', lambda: pd.DataFrame({
        '数学社团': ['张三','李四','王五','赵六','钱七','孙八','周九','吴十','郑一','冯二'] + [None]*5,
        '编程社团': ['张三','李四','陈十一','林十二','黄十三','王五','何十四','曹十五'] + [None]*7,
        '物理社团': ['赵六','王五','张三','胡十六','袁十七','许十八','朱十九'] + [None]*8
    })),
    ('network', '网络关系图测试', lambda: pd.DataFrame({
        '人物A': ['Alice','Alice','Bob','Bob','Charlie','David','Eve','Eve','Frank','Grace'],
        '人物B': ['Bob','Charlie','David','Eve','David','Eve','Frank','Grace','Grace','Alice']
    })),
    ('plotly_scatter', 'Plotly交互散点图测试', lambda: pd.DataFrame({
        '分组': np.random.choice(['甲组','乙组','丙组'], 50),
        'X指标': np.random.normal(50, 15, 50).round(1),
        'Y指标': np.random.normal(60, 12, 50).round(1),
        'Z指标': np.random.uniform(10, 100, 50).round(1)
    })),
    ('bokeh_bar', 'Bokeh交互柱状图测试', lambda: pd.DataFrame({
        '编程语言': ['Python','JavaScript','Java','C++','Go','Rust','TypeScript','Kotlin','Swift','PHP'],
        '使用率': [31.5, 17.8, 12.4, 9.6, 8.2, 5.4, 4.8, 3.2, 2.8, 4.3]
    })),
    ('altair', 'Altair声明式图表测试', lambda: pd.DataFrame({
        '国家': ['中国','美国','日本','德国','英国','法国','印度','巴西','韩国','加拿大'],
        'GDP万亿美元': [17.96, 25.46, 4.23, 4.46, 3.07, 2.78, 3.39, 1.92, 1.67, 2.14]
    })),
]


def generate_all_excel():
    """生成全部27个测试Excel文件"""
    paths = {}
    for chart_type, name, gen_fn in CHART_CONFIGS:
        df = gen_fn()
        fpath = os.path.join(OUTPUT_EXCEL_DIR, f'{name}.xlsx')
        df.to_excel(fpath, index=False, engine='openpyxl')
        paths[chart_type] = fpath
        print(f'  [OK] {name}.xlsx  ({len(df)}行 x {len(df.columns)}列)')
    return paths


def test_all_charts(paths):
    """逐一调用 render_chart 测试渲染"""
    from chart_service import render_chart

    results = []
    for chart_type, name, _ in CHART_CONFIGS:
        fpath = paths[chart_type]
        try:
            params = {'dpi': 150, 'colorScheme': 'Set2'}
            img_path, b64 = render_chart(chart_type, fpath, params)
            fsize = os.path.getsize(img_path) if os.path.exists(img_path) else 0
            is_html = img_path.endswith('.html')
            fmt = 'HTML' if is_html else 'PNG'
            results.append((chart_type, name, 'SUCCESS', fmt, fsize))
            print(f'  [PASS] {name:<20s} -> {fmt} ({fsize//1024}KB)')
        except Exception as e:
            results.append((chart_type, name, 'FAIL', '', 0))
            print(f'  [FAIL] {name:<20s} -> {e}')
            traceback.print_exc()

    return results


def main():
    print('=' * 60)
    print('步骤1: 生成27个测试Excel文件')
    print('=' * 60)
    paths = generate_all_excel()
    print(f'\n共生成 {len(paths)} 个文件 -> {OUTPUT_EXCEL_DIR}\n')

    print('=' * 60)
    print('步骤2: 逐一渲染测试')
    print('=' * 60)
    results = test_all_charts(paths)

    print('\n' + '=' * 60)
    print('测试结果汇总')
    print('=' * 60)
    passed = sum(1 for r in results if r[2] == 'SUCCESS')
    failed = sum(1 for r in results if r[2] == 'FAIL')
    print(f'  通过: {passed}/27')
    print(f'  失败: {failed}/27')

    if failed > 0:
        print('\n失败项:')
        for r in results:
            if r[2] == 'FAIL':
                print(f'  - {r[1]} ({r[0]})')

    return failed == 0


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
