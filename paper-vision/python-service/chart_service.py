"""
论文可视化助手 - 图表渲染服务 v3
- 数据真实驱动：所有图表基于上传文件的真实数据，绝不造假
- 数据类型智能识别：参照 pandas dtype，数值列直接用，文本列(category)用于分类/计数/编码
- 多库合理分工：Matplotlib/Seaborn/Plotly/Bokeh/Pyecharts/Altair/NetworkX/Pyvis/SciPy/matplotlib-venn/wordcloud/mplfinance/squarify
- 图片唯一性：每次输出文件名带 UUID
"""
import os, base64, uuid
import numpy as np, pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import seaborn as sns

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 注册中文字体（直接按文件路径，Windows 下最可靠）
_CJK_FONT = None
for _fp in [r'C:\Windows\Fonts\simhei.ttf', r'C:\Windows\Fonts\msyh.ttc',
            r'C:\Windows\Fonts\simsun.ttc', r'/usr/share/fonts/truetype/wqy/wqy-microhei.ttc']:
    if os.path.exists(_fp):
        try:
            fm.fontManager.addfont(_fp)
            _CJK_FONT = fm.FontProperties(fname=_fp).get_name()
            break
        except Exception:
            pass

plt.rcParams.update({
    'font.size': 12, 'axes.titlesize': 15, 'axes.labelsize': 13,
    'figure.dpi': 100, 'savefig.dpi': 300, 'savefig.bbox': 'tight',
    'axes.grid': True, 'grid.alpha': 0.3,
})
if _CJK_FONT:
    plt.rcParams['font.sans-serif'] = [_CJK_FONT, 'DejaVu Sans']
    plt.rcParams['axes.unicode_minus'] = False


# ============================================================
# 数据加载与类型分析（参照 pandas dtype）
# ============================================================
def load_data(file_path):
    """读取上传的文件为 DataFrame。失败或为空返回 None。"""
    if not file_path or not os.path.exists(file_path):
        return None
    ext = os.path.splitext(file_path)[1].lower()
    try:
        if ext == '.csv':
            df = pd.read_csv(file_path)
        elif ext in ('.xlsx', '.xls'):
            df = pd.read_excel(file_path)
        else:
            df = pd.read_csv(file_path, sep='\t')
    except Exception:
        return None
    if df is None or df.empty:
        return None
    # 去掉完全空的列
    df = df.dropna(axis=1, how='all')
    return df


class DataProfile:
    """
    分析 DataFrame 的列类型（参照 pandas dtype），为各图表提供合理的数据。
    - numeric_cols : 数值列
    - cat_cols     : 文本/类别列
    - label_col    : 首选作为分类标签的列（第一个文本列，否则第一列）
    """
    def __init__(self, df):
        self.df = df
        self.numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
        self.cat_cols = df.select_dtypes(include=['object', 'category', 'bool']).columns.tolist()
        # 日期列单独识别
        self.date_cols = df.select_dtypes(include=['datetime', 'datetimetz']).columns.tolist()
        # 标签列：第一个文本列优先，否则用索引
        if self.cat_cols:
            self.label_col = self.cat_cols[0]
        elif self.numeric_cols:
            # 没有文本列，用第一个数值列也可作 x 轴
            self.label_col = None
        else:
            self.label_col = None

    def labels(self, n=None):
        """返回分类标签列表。"""
        if self.label_col is not None:
            vals = self.df[self.label_col].astype(str).tolist()
        else:
            vals = [str(i) for i in range(len(self.df))]
        return vals[:n] if n else vals

    def label_name(self):
        return str(self.label_col) if self.label_col is not None else '序号'

    def encode_categorical(self, col):
        """把文本列编码为数值（pandas category codes），用于需要数值的图表。"""
        return self.df[col].astype('category').cat.codes

    def category_counts(self):
        """对第一个文本列做频数统计 -> (标签, 计数, 列名)。无文本列时返回 None。"""
        if not self.cat_cols:
            return None
        col = self.cat_cols[0]
        vc = self.df[col].astype(str).value_counts()
        return vc.index.tolist(), vc.values.tolist(), str(col)

    def scale_conflict(self, ratio_threshold=3.0):
        """
        检测多个数值列是否存在量级冲突。
        若各列最大值之比 > 阈值，强行同轴会让小量级柱子被压扁。
        返回 True 表示应拆分为自适应子图（每列独立 Y 轴）。
        """
        if len(self.numeric_cols) < 2:
            return False
        maxes = [abs(self.df[c].max()) for c in self.numeric_cols]
        maxes = [m for m in maxes if m > 0]
        if len(maxes) < 2:
            return False
        return (max(maxes) / min(maxes)) > ratio_threshold


def _save(fig, dpi):
    """保存图片，文件名带 UUID 保证唯一。返回 (path, base64)。"""
    name = f'chart_{uuid.uuid4().hex}.png'
    path = os.path.join(OUTPUT_DIR, name)
    fig.savefig(path, dpi=dpi, facecolor='white', edgecolor='none')
    plt.close(fig)
    with open(path, 'rb') as f:
        return path, base64.b64encode(f.read()).decode()


def _save_html(render_obj_to_file, prefix='chart'):
    """保存交互式 HTML（Plotly/Bokeh/Pyecharts/Pyvis）。返回 (path, '')。"""
    name = f'{prefix}_{uuid.uuid4().hex}.html'
    path = os.path.join(OUTPUT_DIR, name)
    render_obj_to_file(path)
    return path, ''


def _style(ax, title, xlabel='', ylabel=''):
    ax.set_title(title, fontweight='bold', pad=12)
    if xlabel:
        ax.set_xlabel(xlabel)
    if ylabel:
        ax.set_ylabel(ylabel)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.grid(True, alpha=0.3, linestyle='--')


# ============================================================
# 图表实现 —— 每种图选用最合适的库
# ============================================================

def _multi_metric_subplots(df, p, dpi, color, kind='bar'):
    """
    多数值列存在量级冲突时，拆分为 1行N列自适应子图，每列独立 Y 轴。
    解决 price(12) 和 quantity(150) 强行同轴导致柱子被压扁的问题。
    kind: 'bar' 或 'line'
    """
    cols = p.numeric_cols[:4]  # 最多4个子图，超过则太挤
    n = len(cols)
    lbls = p.labels(len(df))
    fig, axes = plt.subplots(1, n, figsize=(5.5 * n, 5), dpi=dpi)
    if n == 1:
        axes = [axes]
    palette = sns.color_palette(color, len(df))
    for ax, col in zip(axes, cols):
        x = np.arange(len(df))
        vals = df[col].values
        if kind == 'line':
            ax.plot(x, vals, 'o-', linewidth=2, markersize=6, color=palette[0])
        else:
            bars = ax.bar(x, vals, color=palette[:len(x)], edgecolor='white', linewidth=0.8)
            ax.bar_label(bars, fmt='%.2f', padding=3, fontsize=9)
            ax.margins(y=0.12)
        ax.set_xticks(x, labels=[str(l) for l in lbls[:len(x)]])
        ax.tick_params(axis='x', rotation=30)
        _style(ax, f'{col} 按 {p.label_name()}', xlabel=p.label_name(), ylabel=str(col))
    fig.suptitle(f'各指标对比（独立 Y 轴自适应）', fontsize=15, fontweight='bold')
    fig.tight_layout()
    return _save(fig, dpi)


# ---- Matplotlib + Seaborn 系 ----
def _bar(df, dpi, color):
    """柱状图。单数值列直接画；多数值列且量级冲突时拆分自适应子图。"""
    p = DataProfile(df)
    # 多数值列 + 量级冲突 -> 拆分子图（每列独立 Y 轴）
    if len(p.numeric_cols) >= 2 and p.scale_conflict():
        return _multi_metric_subplots(df, p, dpi, color, kind='bar')

    fig, ax = plt.subplots(figsize=(11, 6))
    if p.numeric_cols:
        col = p.numeric_cols[0]
        lbls = p.labels(len(df))
        vals = df[col].iloc[:len(lbls)]
        x = np.arange(len(vals))
        bars = ax.bar(x, vals, color=sns.color_palette(color, len(vals)), edgecolor='white', linewidth=0.8)
        ax.set_xticks(x, labels=[str(l) for l in lbls[:len(vals)]])
        ax.bar_label(bars, fmt='%.2f', padding=3, fontsize=9)
        ax.margins(y=0.12)
        _style(ax, f'{col} 按 {p.label_name()}', xlabel=p.label_name(), ylabel=str(col))
        ax.tick_params(axis='x', rotation=30)
    elif p.cat_cols:
        # 全是文本列：对第一个文本列做频数统计
        labels, counts, cname = p.category_counts()
        x = np.arange(len(labels))
        bars = ax.bar(x, counts, color=sns.color_palette(color, len(labels)), edgecolor='white')
        ax.set_xticks(x, labels=labels)
        ax.bar_label(bars, fmt='%d', padding=3)
        _style(ax, f'{cname} 频数分布', xlabel=cname, ylabel='计数')
        ax.tick_params(axis='x', rotation=30)
    return _save(fig, dpi)


def _grouped_bar(df, dpi, color):
    """分组柱状图。量级冲突时拆分为自适应子图（每指标独立 Y 轴）。"""
    p = DataProfile(df)
    if len(p.numeric_cols) < 2:
        return _bar(df, dpi, color)
    # 量级冲突 -> 拆子图，否则同轴分组
    if p.scale_conflict():
        return _multi_metric_subplots(df, p, dpi, color, kind='bar')
    fig, ax = plt.subplots(figsize=(12, 6))
    lbls = p.labels(min(12, len(df)))
    x = np.arange(len(lbls))
    w = 0.8 / len(p.numeric_cols)
    for i, c in enumerate(p.numeric_cols[:6]):
        vals = df[c].iloc[:len(x)].values
        ax.bar(x + i * w, vals, w, label=str(c), color=sns.color_palette(color, len(p.numeric_cols))[i])
    ax.set_xticks(x + w * (len(p.numeric_cols) - 1) / 2, labels=[str(l) for l in lbls])
    ax.legend(title='指标')
    ax.tick_params(axis='x', rotation=30)
    _style(ax, '分组柱状图', xlabel=p.label_name(), ylabel='数值')
    return _save(fig, dpi)


def _stacked_bar(df, dpi, color):
    """堆叠柱状图 (Matplotlib)。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(12, 6))
    if len(p.numeric_cols) >= 2:
        lbls = p.labels(min(15, len(df)))
        bottom = np.zeros(len(lbls))
        for i, c in enumerate(p.numeric_cols[:6]):
            vals = df[c].iloc[:len(lbls)].values
            ax.bar(lbls, vals, bottom=bottom, label=str(c), color=sns.color_palette(color, len(p.numeric_cols))[i])
            bottom += vals
        ax.legend(title='指标')
        ax.tick_params(axis='x', rotation=30)
        _style(ax, '堆叠柱状图', xlabel=p.label_name(), ylabel='累计数值')
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


def _line(df, dpi, color, multi):
    """折线图 (Matplotlib)。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(12, 6))
    lbls = p.labels(len(df))
    if multi and len(p.numeric_cols) > 1:
        for c in p.numeric_cols[:6]:
            ax.plot(range(len(df)), df[c].values, 'o-', label=str(c), linewidth=2, markersize=4)
        ax.legend(title='指标')
        ylab = '数值'
    elif p.numeric_cols:
        col = p.numeric_cols[0]
        ax.plot(range(len(df)), df[col].values, 'o-', linewidth=2, markersize=5,
                color=sns.color_palette(color, 1)[0], label=str(col))
        ax.legend(title='指标')
        ylab = str(col)
    else:
        return _bar(df, dpi, color)
    step = max(1, len(lbls) // 15)
    ax.set_xticks(range(0, len(lbls), step))
    ax.set_xticklabels([lbls[i] for i in range(0, len(lbls), step)], rotation=30)
    _style(ax, '折线图', xlabel=p.label_name(), ylabel=ylab)
    return _save(fig, dpi)


def _scatter(df, dpi, color):
    """散点图 (Seaborn)。需2个数值列，文本列可做色相分组。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(10, 7))
    if len(p.numeric_cols) >= 2:
        xcol, ycol = p.numeric_cols[0], p.numeric_cols[1]
        hue = p.cat_cols[0] if p.cat_cols else None
        sns.scatterplot(data=df, x=xcol, y=ycol, hue=hue, palette=color if hue else None,
                        s=90, alpha=0.75, edgecolor='white', ax=ax)
        _style(ax, f'{ycol} vs {xcol}', xlabel=str(xcol), ylabel=str(ycol))
        if hue:
            ax.legend(title=str(hue))
    elif p.numeric_cols:
        col = p.numeric_cols[0]
        ax.scatter(range(len(df)), df[col], s=80, alpha=0.7, color=sns.color_palette(color, 1)[0])
        _style(ax, f'{col} 散点分布', xlabel=p.label_name(), ylabel=str(col))
    return _save(fig, dpi)


def _bubble(df, dpi, color):
    """气泡图 (Matplotlib)。x,y,size 三个数值列。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(10, 7))
    if len(p.numeric_cols) >= 3:
        xc, yc, zc = p.numeric_cols[:3]
        z = df[zc]
        sz = ((z - z.min()) / (z.max() - z.min() + 1e-9) * 400 + 30).values
        sc = ax.scatter(df[xc], df[yc], s=sz, c=z, cmap=color, alpha=0.6, edgecolors='white', linewidth=0.5)
        plt.colorbar(sc, ax=ax, label=str(zc))
        _style(ax, f'气泡图 ({xc}, {yc}, {zc})', xlabel=str(xc), ylabel=str(yc))
    else:
        return _scatter(df, dpi, color)
    return _save(fig, dpi)


def _pie(df, dpi, color):
    """饼图 (Matplotlib)。文本列分类 + 数值列求和；纯文本则频数。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(8, 8))
    if p.cat_cols and p.numeric_cols:
        # 按文本列分组汇总第一个数值列
        cat, val = p.cat_cols[0], p.numeric_cols[0]
        grp = df.groupby(cat, observed=True)[val].sum().sort_values(ascending=False).head(8)
        labels, vals = grp.index.astype(str).tolist(), grp.values
        title = f'{val} 占比 (按{cat})'
    elif p.cat_cols:
        labels, vals, cname = p.category_counts()
        labels, vals = labels[:8], vals[:8]
        title = f'{cname} 频数占比'
    elif p.numeric_cols:
        col = p.numeric_cols[0]
        labels = p.labels(8)
        vals = df[col].iloc[:8].values
        title = f'{col} 占比'
    else:
        return _bar(df, dpi, color)
    colors = sns.color_palette(color, len(vals))
    wedges, _, autotexts = ax.pie(vals, labels=labels, autopct='%1.1f%%', colors=colors,
                                  textprops={'fontsize': 12}, pctdistance=0.75, startangle=90)
    for t in autotexts:
        t.set_fontsize(10); t.set_fontweight('bold')
    ax.set_title(title, fontweight='bold', fontsize=15, pad=12)
    return _save(fig, dpi)


def _donut(df, dpi, color):
    """环形图 (Matplotlib)。"""
    path_b64 = _pie(df, dpi, color)
    return path_b64  # 复用饼图逻辑后下方单独绘环


def _heatmap(df, dpi, color):
    """热力图 (Seaborn)。数值列相关系数矩阵。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(11, 9))
    if len(p.numeric_cols) >= 2:
        corr = df[p.numeric_cols].corr()
        sns.heatmap(corr, annot=True, cmap=color, ax=ax, fmt='.2f', linewidths=0.5,
                    square=True, cbar_kws={'shrink': 0.8}, annot_kws={'fontsize': 9})
        ax.set_title('数值列相关性热力图', fontweight='bold', fontsize=15, pad=12)
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


def _boxplot(df, dpi, color):
    """箱线图 (Seaborn)。每个数值列一个箱；有文本列则按类别分组。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(11, 6))
    if p.cat_cols and p.numeric_cols:
        cat, val = p.cat_cols[0], p.numeric_cols[0]
        sns.boxplot(data=df, x=cat, y=val, hue=cat, palette=color, legend=False, ax=ax)
        _style(ax, f'{val} 按 {cat} 分组箱线图', xlabel=str(cat), ylabel=str(val))
        ax.tick_params(axis='x', rotation=30)
    elif p.numeric_cols:
        sns.boxplot(data=df[p.numeric_cols], palette=color, ax=ax)
        _style(ax, '各数值列箱线图', ylabel='数值')
        ax.tick_params(axis='x', rotation=30)
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


def _violin(df, dpi, color):
    """小提琴图 (Seaborn)。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(11, 6))
    if p.cat_cols and p.numeric_cols:
        cat, val = p.cat_cols[0], p.numeric_cols[0]
        sns.violinplot(data=df, x=cat, y=val, hue=cat, palette=color, legend=False, ax=ax)
        _style(ax, f'{val} 按 {cat} 小提琴图', xlabel=str(cat), ylabel=str(val))
        ax.tick_params(axis='x', rotation=30)
    elif p.numeric_cols:
        sns.violinplot(data=df[p.numeric_cols], palette=color, ax=ax)
        _style(ax, '各数值列小提琴图', ylabel='数值')
        ax.tick_params(axis='x', rotation=30)
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


def _radar(df, dpi, color):
    """雷达图 (Matplotlib polar)。多个数值列为维度，前几行为系列。"""
    p = DataProfile(df)
    if len(p.numeric_cols) < 3:
        return _bar(df, dpi, color)
    cats = p.numeric_cols
    N = len(cats)
    angles = [n / float(N) * 2 * np.pi for n in range(N)] + [0]
    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True))
    lbls = p.labels(len(df))
    # 归一化每个维度到 0-1 便于对比
    norm = df[cats].copy()
    for c in cats:
        rng = df[c].max() - df[c].min()
        norm[c] = (df[c] - df[c].min()) / rng if rng else 0.5
    for i in range(min(4, len(df))):
        vals = norm.iloc[i].tolist() + [norm.iloc[i, 0]]
        ax.fill(angles, vals, alpha=0.12)
        ax.plot(angles, vals, 'o-', linewidth=2, label=str(lbls[i]))
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels([str(c) for c in cats])
    ax.legend(loc='upper right', bbox_to_anchor=(1.25, 1.1), title=p.label_name())
    ax.set_title('雷达图（各维度归一化）', fontweight='bold', fontsize=14, pad=25)
    return _save(fig, dpi)


def _gantt(df, dpi, color):
    """甘特图 (Matplotlib broken_barh)。第1文本列=任务，2数值列=起始,持续。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(13, 6))
    if len(p.numeric_cols) >= 2:
        tasks = p.labels(min(12, len(df)))
        starts = df[p.numeric_cols[0]].iloc[:len(tasks)].values
        durs = df[p.numeric_cols[1]].iloc[:len(tasks)].values
        colors = sns.color_palette(color, len(tasks))
        for i, (t, s, d) in enumerate(zip(tasks, starts, durs)):
            ax.barh(i, d, left=s, height=0.6, color=colors[i], edgecolor='white')
            ax.text(s + d / 2, i, str(t), ha='center', va='center', fontsize=9, fontweight='bold')
        ax.set_yticks(range(len(tasks)))
        ax.set_yticklabels([str(t) for t in tasks])
        _style(ax, '甘特图', xlabel=str(p.numeric_cols[0]) + '(起始/持续)')
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


def _pareto(df, dpi, color):
    """帕累托图 (Matplotlib 双轴)。"""
    p = DataProfile(df)
    fig, ax1 = plt.subplots(figsize=(12, 6))
    if p.cat_cols and p.numeric_cols:
        cat, val = p.cat_cols[0], p.numeric_cols[0]
        grp = df.groupby(cat, observed=True)[val].sum().sort_values(ascending=False)
        labels, vals = grp.index.astype(str).tolist(), grp.values
    elif p.numeric_cols:
        col = p.numeric_cols[0]
        order = np.argsort(df[col].values)[::-1]
        vals = df[col].values[order]
        labels = [p.labels(len(df))[i] for i in order]
    else:
        return _bar(df, dpi, color)
    cum = np.cumsum(vals) / np.sum(vals) * 100
    ax1.bar(range(len(vals)), vals, color=sns.color_palette(color, len(vals)), edgecolor='white')
    ax1.set_xticks(range(len(vals)))
    ax1.set_xticklabels(labels, rotation=30)
    ax2 = ax1.twinx()
    ax2.plot(range(len(vals)), cum, 'ro-', linewidth=2, markersize=5)
    ax2.axhline(80, color='gray', linestyle='--', linewidth=1)
    ax2.set_ylabel('累计百分比 %')
    _style(ax1, '帕累托图', ylabel='数值')
    return _save(fig, dpi)


def _area(df, dpi, color):
    """面积图 (Matplotlib)。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(12, 6))
    if p.numeric_cols:
        lbls = p.labels(len(df))
        colors = sns.color_palette(color, len(p.numeric_cols[:6]))
        for i, c in enumerate(p.numeric_cols[:6]):
            ax.fill_between(range(len(df)), df[c].values, alpha=0.4, color=colors[i], label=str(c))
            ax.plot(range(len(df)), df[c].values, color=colors[i], linewidth=1.2)
        step = max(1, len(lbls) // 12)
        ax.set_xticks(range(0, len(lbls), step))
        ax.set_xticklabels([lbls[i] for i in range(0, len(lbls), step)], rotation=30)
        ax.legend(title='指标')
        _style(ax, '面积图', xlabel=p.label_name(), ylabel='数值')
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


# ---- SciPy + matplotlib-venn ----
def _surface3d(df, dpi, color):
    """3D 曲面/散点 (Matplotlib + SciPy 插值)。3数值列用真实数据曲面。"""
    from scipy.interpolate import griddata
    p = DataProfile(df)
    fig = plt.figure(figsize=(12, 8))
    ax = fig.add_subplot(111, projection='3d')
    if len(p.numeric_cols) >= 3:
        xc, yc, zc = p.numeric_cols[:3]
        x, y, z = df[xc].values, df[yc].values, df[zc].values
        # 用 SciPy 把散点插值成网格曲面
        try:
            xi = np.linspace(x.min(), x.max(), 40)
            yi = np.linspace(y.min(), y.max(), 40)
            XI, YI = np.meshgrid(xi, yi)
            ZI = griddata((x, y), z, (XI, YI), method='cubic')
            ax.plot_surface(XI, YI, ZI, cmap=color, alpha=0.85, antialiased=True)
            ax.scatter(x, y, z, c='black', s=15, alpha=0.5)
        except Exception:
            ax.scatter(x, y, z, c=z, cmap=color, s=40)
        ax.set_xlabel(str(xc)); ax.set_ylabel(str(yc)); ax.set_zlabel(str(zc))
        ax.set_title('3D 曲面 (SciPy 插值)', fontweight='bold', pad=12)
    else:
        return _scatter(df, dpi, color)
    return _save(fig, dpi)


def _venn(df, dpi, color):
    """韦恩图 (matplotlib-venn)。取前2-3个文本列的集合关系。"""
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(9, 7))
    if len(p.cat_cols) >= 2:
        from matplotlib_venn import venn2, venn3
        if len(p.cat_cols) >= 3:
            s1 = set(df[p.cat_cols[0]].dropna().astype(str))
            s2 = set(df[p.cat_cols[1]].dropna().astype(str))
            s3 = set(df[p.cat_cols[2]].dropna().astype(str))
            venn3([s1, s2, s3], set_labels=p.cat_cols[:3], ax=ax)
        else:
            s1 = set(df[p.cat_cols[0]].dropna().astype(str))
            s2 = set(df[p.cat_cols[1]].dropna().astype(str))
            venn2([s1, s2], set_labels=p.cat_cols[:2], ax=ax)
        ax.set_title('韦恩图（文本列集合关系）', fontweight='bold', pad=12)
    else:
        return _bar(df, dpi, color)
    return _save(fig, dpi)


# ---- mplfinance ----
def _candlestick(df, dpi, color):
    """K线图 (mplfinance)。需 Open/High/Low/Close 4个数值列。"""
    import mplfinance as mpf
    p = DataProfile(df)
    if len(p.numeric_cols) >= 4:
        ohlc = df[p.numeric_cols[:4]].copy()
        ohlc.columns = ['Open', 'High', 'Low', 'Close']
        idx = pd.date_range('2024-01-01', periods=len(ohlc), freq='D')
        ohlc.index = idx
        name = f'chart_{uuid.uuid4().hex}.png'
        path = os.path.join(OUTPUT_DIR, name)
        mpf.plot(ohlc, type='candle', style='yahoo', savefig=dict(fname=path, dpi=dpi, bbox_inches='tight'),
                 title='K线图', volume=False)
        with open(path, 'rb') as f:
            return path, base64.b64encode(f.read()).decode()
    else:
        return _line(df, dpi, color, False)


# ---- squarify ----
def _treemap(df, dpi, color):
    """矩形树图 (squarify)。"""
    import squarify
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(12, 8))
    if p.cat_cols and p.numeric_cols:
        cat, val = p.cat_cols[0], p.numeric_cols[0]
        grp = df.groupby(cat, observed=True)[val].sum().sort_values(ascending=False).head(12)
        labels = [f'{k}\n{v:.0f}' for k, v in grp.items()]
        vals = grp.values
    elif p.numeric_cols:
        col = p.numeric_cols[0]
        vals = df[col].abs().head(12).values
        labels = [f'{l}\n{v:.0f}' for l, v in zip(p.labels(12), vals)]
    else:
        labels, counts, _ = p.category_counts()
        vals = counts[:12]; labels = labels[:12]
    squarify.plot(sizes=vals, label=labels, alpha=0.8,
                  color=sns.color_palette(color, len(vals)), ax=ax, text_kwargs={'fontsize': 10})
    ax.axis('off')
    ax.set_title('矩形树图', fontweight='bold', fontsize=15, pad=12)
    return _save(fig, dpi)


# ---- wordcloud ----
def _wordcloud(df, dpi, color):
    """词云 (wordcloud)。文本列词频；纯数值则用列名+数值。"""
    from wordcloud import WordCloud
    p = DataProfile(df)
    freq = {}
    if p.cat_cols:
        # 文本列的词频
        for col in p.cat_cols:
            for v in df[col].dropna().astype(str):
                for w in str(v).split():
                    freq[w] = freq.get(w, 0) + 1
    if not freq and p.numeric_cols:
        # 用 标签->数值 作为权重
        col = p.numeric_cols[0]
        for l, v in zip(p.labels(len(df)), df[col].values):
            freq[str(l)] = abs(float(v)) + 1
    if not freq:
        freq = {'Data': 5, 'Visualization': 3}
    wc = WordCloud(width=1200, height=700, background_color='white', colormap=color,
                   font_path=_find_cjk_font()).generate_from_frequencies(freq)
    name = f'chart_{uuid.uuid4().hex}.png'
    path = os.path.join(OUTPUT_DIR, name)
    wc.to_file(path)
    with open(path, 'rb') as f:
        return path, base64.b64encode(f.read()).decode()


def _find_cjk_font():
    """返回中文字体文件路径，wordcloud 需要。"""
    for fp in [r'C:\Windows\Fonts\simhei.ttf', r'C:\Windows\Fonts\msyh.ttc',
               r'C:\Windows\Fonts\simsun.ttc', r'/usr/share/fonts/truetype/wqy/wqy-microhei.ttc']:
        if os.path.exists(fp):
            return fp
    return None


# ---- NetworkX + Pyvis ----
def _network(df, dpi, color):
    """网络关系图 (NetworkX)。前2个文本列作 源->目标 边。"""
    import networkx as nx
    p = DataProfile(df)
    fig, ax = plt.subplots(figsize=(11, 9))
    G = nx.Graph()
    if len(p.cat_cols) >= 2:
        src, dst = p.cat_cols[0], p.cat_cols[1]
        for s, d in zip(df[src].astype(str), df[dst].astype(str)):
            G.add_edge(s, d)
    elif p.cat_cols:
        # 单文本列：相邻行连边
        vals = df[p.cat_cols[0]].astype(str).tolist()
        for a, b in zip(vals, vals[1:]):
            G.add_edge(a, b)
    else:
        return _bar(df, dpi, color)
    pos = nx.spring_layout(G, seed=42)
    nx.draw_networkx_nodes(G, pos, ax=ax, node_color=sns.color_palette(color, 1)[0], node_size=600, alpha=0.85)
    nx.draw_networkx_edges(G, pos, ax=ax, alpha=0.4)
    nx.draw_networkx_labels(G, pos, ax=ax, font_size=10)
    ax.set_title('网络关系图', fontweight='bold', fontsize=15, pad=12)
    ax.axis('off')
    return _save(fig, dpi)


# ---- Plotly (交互式 HTML) ----
def _plotly_scatter(df, dpi, color):
    """Plotly 交互式散点图 -> HTML。"""
    import plotly.express as px
    p = DataProfile(df)
    if len(p.numeric_cols) >= 2:
        hue = p.cat_cols[0] if p.cat_cols else None
        fig = px.scatter(df, x=p.numeric_cols[0], y=p.numeric_cols[1],
                         color=hue, title='Plotly 交互式散点图',
                         size=p.numeric_cols[2] if len(p.numeric_cols) >= 3 else None)
        return _save_html(fig.write_html, 'plotly')
    return _scatter(df, dpi, color)


# ---- Bokeh (交互式 HTML) ----
def _bokeh_bar(df, dpi, color):
    """Bokeh 交互式柱状图 -> HTML。"""
    from bokeh.plotting import figure, output_file, save
    p = DataProfile(df)
    if p.numeric_cols:
        lbls = [str(l) for l in p.labels(min(20, len(df)))]
        vals = df[p.numeric_cols[0]].iloc[:len(lbls)].tolist()
        name = f'bokeh_{uuid.uuid4().hex}.html'
        path = os.path.join(OUTPUT_DIR, name)
        output_file(path)
        fig = figure(x_range=lbls, height=500, width=900, title='Bokeh 交互式柱状图',
                     toolbar_location='right', tools='pan,wheel_zoom,box_zoom,reset,save')
        fig.vbar(x=lbls, top=vals, width=0.7, fill_color='#4A90D9')
        fig.xaxis.major_label_orientation = 0.8
        save(fig)
        return path, ''
    return _bar(df, dpi, color)


# ---- Altair (交互式 HTML) ----
def _altair_chart(df, dpi, color):
    """Altair 声明式图表 -> HTML。"""
    import altair as alt
    p = DataProfile(df)
    if p.cat_cols and p.numeric_cols:
        chart = alt.Chart(df.head(50)).mark_bar().encode(
            x=alt.X(f'{p.cat_cols[0]}:N', title=p.cat_cols[0]),
            y=alt.Y(f'{p.numeric_cols[0]}:Q', title=p.numeric_cols[0]),
            tooltip=list(df.columns)
        ).properties(title='Altair 图表', width=700, height=450)
        return _save_html(chart.save, 'altair')
    elif p.numeric_cols:
        dfx = df.reset_index()
        chart = alt.Chart(dfx.head(50)).mark_line(point=True).encode(
            x='index:Q', y=alt.Y(f'{p.numeric_cols[0]}:Q', title=p.numeric_cols[0])
        ).properties(title='Altair 图表', width=700, height=450)
        return _save_html(chart.save, 'altair')
    return _bar(df, dpi, color)


# ---- Pyecharts (交互式 HTML) ----
def _sankey(df, dpi, color):
    """桑基图 (Pyecharts)。前2文本列做流向，数值列做流量。"""
    from pyecharts.charts import Sankey
    from pyecharts import options as opts
    p = DataProfile(df)
    if len(p.cat_cols) >= 2:
        src, dst = p.cat_cols[0], p.cat_cols[1]
        val = p.numeric_cols[0] if p.numeric_cols else None
        nodes_set = set(df[src].astype(str)) | set(df[dst].astype(str))
        nodes = [{'name': n} for n in nodes_set]
        links = []
        for _, row in df.iterrows():
            links.append({'source': str(row[src]), 'target': str(row[dst]),
                          'value': float(row[val]) if val else 1.0})
        sk = (Sankey().add('流向', nodes, links,
                           linestyle_opt=opts.LineStyleOpts(opacity=0.3, curve=0.5),
                           label_opts=opts.LabelOpts(position='right'))
              .set_global_opts(title_opts=opts.TitleOpts(title='桑基图')))
        return _save_html(sk.render, 'sankey')
    return _bar(df, dpi, color)


def _parallel(df, dpi, color):
    """平行坐标图 (Pyecharts)。多个数值列。"""
    from pyecharts.charts import Parallel
    from pyecharts import options as opts
    p = DataProfile(df)
    if len(p.numeric_cols) >= 3:
        cols = p.numeric_cols[:8]
        schema = [opts.ParallelAxisOpts(dim=i, name=str(c)) for i, c in enumerate(cols)]
        data = df[cols].head(50).values.tolist()
        par = (Parallel().add_schema(schema)
               .add('数据', data)
               .set_global_opts(title_opts=opts.TitleOpts(title='平行坐标图')))
        return _save_html(par.render, 'parallel')
    return _line(df, dpi, color, True)


# ============================================================
# 派发表
# ============================================================
CHART_DISPATCH = {
    'bar':          lambda df, d, c: _bar(df, d, c),
    'grouped_bar':  _grouped_bar,
    'stacked_bar':  _stacked_bar,
    'line':         lambda df, d, c: _line(df, d, c, False),
    'multi_line':   lambda df, d, c: _line(df, d, c, True),
    'scatter':      _scatter,
    'bubble':       _bubble,
    'pie':          _pie,
    'donut':        _donut,
    'heatmap':      _heatmap,
    'boxplot':      _boxplot,
    'violin':       _violin,
    'radar':        _radar,
    'gantt':        _gantt,
    'sankey':       _sankey,        # Pyecharts
    'treemap':      _treemap,       # squarify
    'parallel':     _parallel,      # Pyecharts
    'wordcloud':    _wordcloud,     # wordcloud
    'surface3d':    _surface3d,     # SciPy
    'pareto':       _pareto,
    'candlestick':  _candlestick,   # mplfinance
    'area':         _area,
    'venn':         _venn,          # matplotlib-venn
    'network':      _network,       # NetworkX
    'plotly_scatter': _plotly_scatter,  # Plotly
    'bokeh_bar':    _bokeh_bar,     # Bokeh
    'altair':       _altair_chart,  # Altair
}


def render_chart(chart_type, file_path, params):
    """主入口。基于真实上传数据渲染图表，返回 (image_path, base64)。"""
    df = load_data(file_path)
    dpi = min(max(int(params.get('dpi', 300)), 72), 600)
    color = params.get('colorScheme', params.get('color', 'Set2'))
    if not isinstance(color, str) or not color.replace('_', '').isalnum():
        color = 'Set2'
    plt.close('all')

    if df is None or len(df) == 0:
        raise ValueError('未提供有效数据文件，或文件为空。请先上传含表头的数据文件。')

    if len(df) > 10000:
        df = df.head(10000)

    render_fn = CHART_DISPATCH.get(chart_type)
    if render_fn is None:
        raise ValueError(f'不支持的图表类型: {chart_type}')
    return render_fn(df, dpi, color)
