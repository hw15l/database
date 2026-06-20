"""
公式可视化引擎 v6 — 动态尺寸 · 主题系统 · 矩阵网格渲染 · 多公式组合

架构:
  REGISTRY     注册表模式, 每种公式一个构建器函数
  THEMES       预设主题(paper/presentation/dark), 控制颜色/字号/边距
  _render_latex    标准公式渲染(动态计算图片尺寸)
  _render_matrix   矩阵/行列式专用渲染(网格布局 + Bézier曲线括号)
  _render_multi    多公式组合渲染(垂直堆叠, 自动编号)

v5→v6 关键改进:
  - 动态尺寸: 根据LaTeX复杂度自动计算figsize, 告别固定(10,4)
  - 矩阵: 从\\substack(元素被缩小)改为网格布局+Bézier曲线括号, 视觉质量大幅提升
  - 主题: paper/presentation/dark 三套预设, 一键切换风格
  - 多公式: 支持一张图片内渲染多个公式, 自动对齐编号
"""

import os
import base64
import uuid
import logging
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from matplotlib.path import Path as MplPath
import matplotlib.patches as mpatches

logger = logging.getLogger(__name__)

# ═══════════════════════════════════════════════
# 全局配置
# ═══════════════════════════════════════════════
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUTPUT_DIR, exist_ok=True)

MAX_FIGSIZE_W = 16
MAX_FIGSIZE_H = 12
MAX_IMAGE_BYTES = 10 * 1024 * 1024

for _fp in [r'C:\Windows\Fonts\simhei.ttf', r'C:\Windows\Fonts\msyh.ttc',
            '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc']:
    if os.path.exists(_fp):
        try:
            fm.fontManager.addfont(_fp)
            break
        except Exception:
            pass
plt.rcParams.update({
    'font.sans-serif': ['SimHei', 'Microsoft YaHei', 'WenQuanYi Zen Hei', 'DejaVu Sans'],
    'axes.unicode_minus': False,
    'mathtext.fontset': 'cm',
    'figure.autolayout': False,
})

# ═══════════════════════════════════════════════
# 主题系统
# ═══════════════════════════════════════════════
THEMES = {
    'paper': {
        'fontsize': 34, 'color': '#000000', 'subtitle_color': '#666666',
        'bg_color': 'white', 'bracket_color': '#000000', 'bracket_lw': 2.0,
        'dpi': 300, 'pad_inches': 0.3, 'subtitle_size': 13,
    },
    'presentation': {
        'fontsize': 42, 'color': '#1a1a2e', 'subtitle_color': '#888888',
        'bg_color': 'white', 'bracket_color': '#333333', 'bracket_lw': 2.5,
        'dpi': 200, 'pad_inches': 0.5, 'subtitle_size': 16,
    },
    'dark': {
        'fontsize': 36, 'color': '#e0e0e0', 'subtitle_color': '#999999',
        'bg_color': '#1e1e2e', 'bracket_color': '#cccccc', 'bracket_lw': 2.0,
        'dpi': 300, 'pad_inches': 0.4, 'subtitle_size': 13,
    },
}
DEFAULT_THEME = 'paper'


def _resolve_params(user_params):
    """合并主题默认值 + 用户参数, 返回完整渲染参数。"""
    theme_name = (user_params or {}).get('theme', DEFAULT_THEME)
    base = dict(THEMES.get(theme_name, THEMES[DEFAULT_THEME]))
    base['transparent'] = False
    base['format'] = 'png'
    if user_params:
        base.update({k: v for k, v in user_params.items() if v is not None})
    base['dpi'] = min(max(int(base.get('dpi', 300)), 72), 600)
    return base


# ═══════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════
def _num(v):
    """数值→字符串: 整数去小数点, 浮点保留有效位。"""
    try:
        f = float(v)
        return str(int(f)) if f == int(f) else f'{f:g}'
    except (TypeError, ValueError):
        return str(v)


def _save_path(fmt='png'):
    return os.path.join(OUTPUT_DIR, f'formula_{uuid.uuid4().hex}.{fmt}')


def _save_fig(fig, params):
    """统一的图片保存 + base64编码流程。"""
    p = params
    fmt = p.get('format', 'png')
    dpi = int(p.get('dpi', 300))
    transparent = p.get('transparent', False)
    bg = 'none' if transparent else p.get('bg_color', 'white')
    pad = float(p.get('pad_inches', 0.3))

    w, h = fig.get_size_inches()
    if w > MAX_FIGSIZE_W or h > MAX_FIGSIZE_H:
        fig.set_size_inches(min(w, MAX_FIGSIZE_W), min(h, MAX_FIGSIZE_H))

    path = _save_path(fmt)
    fig.savefig(path, dpi=dpi, bbox_inches='tight', facecolor=bg,
                edgecolor='none', pad_inches=pad, format=fmt, transparent=transparent)
    plt.close(fig)

    fsize = os.path.getsize(path)
    if fsize > MAX_IMAGE_BYTES:
        os.remove(path)
        raise ValueError(f'生成的图片过大({fsize // 1024 // 1024}MB), 请降低DPI')

    with open(path, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode()
    logger.info("渲染完成: %s (dpi=%d, size=%dKB)", path, dpi, fsize // 1024)
    return path, b64


def _estimate_size(latex, has_subtitle=False):
    """根据LaTeX复杂度估算figsize, 避免固定尺寸导致的过大/过小。"""
    n = len(latex)
    has_frac = r'\frac' in latex or r'\int' in latex or r'\sum' in latex
    has_stack = r'\substack' in latex or r'\atop' in latex

    w = max(5.0, min(14.0, 3.0 + n * 0.065))
    h = 2.8
    if has_frac:
        h = 3.6
    if has_stack:
        h = max(h, 3.2 + latex.count(r'\\') * 0.35)
    if has_subtitle:
        h += 0.8
    return (w, h)


# ═══════════════════════════════════════════════
# 矩阵网格渲染器 (替代 \substack 方案)
# ═══════════════════════════════════════════════
def _draw_bracket(ax, x, y_bot, y_top, side, style, color, lw):
    """用三次Bézier曲线绘制一条光滑括号。"""
    h = y_top - y_bot
    bulge = h * 0.18
    if style in ('vert', 'double_vert'):
        ax.plot([x, x], [y_bot, y_top], color=color, lw=lw, solid_capstyle='round')
        if style == 'double_vert':
            offset = 0.15
            dx = -offset if side == 'left' else offset
            ax.plot([x + dx, x + dx], [y_bot, y_top], color=color, lw=lw, solid_capstyle='round')
        return
    sign = -1 if side == 'left' else 1
    verts = [
        (x, y_top),
        (x + sign * bulge, y_top - h * 0.15),
        (x + sign * bulge, y_bot + h * 0.15),
        (x, y_bot),
    ]
    codes = [MplPath.MOVETO, MplPath.CURVE4, MplPath.CURVE4, MplPath.CURVE4]
    patch = mpatches.PathPatch(MplPath(verts, codes), facecolor='none',
                               edgecolor=color, lw=lw, capstyle='round')
    ax.add_patch(patch)


def _render_matrix(rows, bracket='paren', subtitle=None, result_suffix=None, params=None):
    """
    高质量矩阵渲染: 网格布局 + Bézier曲线括号。
    每个单元格用mathtext渲染, 保证字体与标准公式一致。

    Args:
        rows:           二维列表
        bracket:        paren/bracket/vert/double_vert
        subtitle:       下方说明文字
        result_suffix:  行列式等号及结果(如 '= -1')
        params:         渲染参数
    """
    p = _resolve_params(params)
    nrows = len(rows)
    ncols = max(len(r) for r in rows)
    fs = int(p.get('fontsize', 34))
    cell_fs = max(18, int(fs * 0.65))
    color = p.get('color', '#000')
    br_color = p.get('bracket_color', color)
    br_lw = float(p.get('bracket_lw', 2.0))
    dpi = int(p.get('dpi', 300))

    col_w = 1.1
    row_h = 0.85
    content_w = ncols * col_w
    content_h = nrows * row_h
    margin_l = 1.0
    margin_r = 1.0
    suffix_w = 0.0
    if result_suffix:
        suffix_w = max(2.0, len(result_suffix) * 0.28)
        margin_r += suffix_w
    margin_y = 1.0 if subtitle else 0.6

    fig_w = content_w + margin_l + margin_r
    fig_h = content_h + margin_y * 2

    fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=dpi,
                           facecolor='none' if p.get('transparent') else p['bg_color'])
    ax.set_xlim(0, fig_w)
    ax.set_ylim(0, fig_h)
    ax.axis('off')
    ax.set_aspect('equal')

    ox = margin_l
    oy = margin_y * 0.85 + (0.25 if subtitle else 0)

    for i in range(nrows):
        for j in range(min(ncols, len(rows[i]))):
            cx = ox + j * col_w + col_w / 2
            cy = oy + (nrows - 1 - i) * row_h + row_h / 2
            ax.text(cx, cy, f'${_num(rows[i][j])}$', fontsize=cell_fs,
                    ha='center', va='center', color=color)

    pad_x = 0.25
    pad_y = 0.15
    bx_l = ox - pad_x
    bx_r = ox + content_w + pad_x
    by_bot = oy + pad_y
    by_top = oy + content_h - pad_y

    _draw_bracket(ax, bx_l, by_bot, by_top, 'left', bracket, br_color, br_lw)
    _draw_bracket(ax, bx_r, by_bot, by_top, 'right', bracket, br_color, br_lw)

    if result_suffix:
        rx = bx_r + 0.4
        ry = oy + content_h / 2
        ax.text(rx, ry, f'${result_suffix}$', fontsize=cell_fs,
                ha='left', va='center', color=color)

    if subtitle:
        ax.text(fig_w / 2, 0.35, subtitle, fontsize=int(p.get('subtitle_size', 13)),
                ha='center', va='center', color=p.get('subtitle_color', '#666'))

    return _save_fig(fig, p)


# ═══════════════════════════════════════════════
# 标准公式渲染引擎 (动态尺寸)
# ═══════════════════════════════════════════════
def _render_latex(latex_body, subtitle=None, params=None):
    """
    核心渲染函数 — 动态计算图片尺寸, 自动适配公式复杂度。

    Args:
        latex_body: LaTeX数学表达式(不含$符号)
        subtitle:   公式下方中文说明
        params:     渲染参数(主题+自定义)
    Returns:
        (file_path, base64_string)
    """
    p = _resolve_params(params)
    fs = int(p.get('fontsize', 34))
    color = p.get('color', '#000')
    sub_color = p.get('subtitle_color', '#666')
    sub_size = int(p.get('subtitle_size', 13))
    bg = 'none' if p.get('transparent') else p.get('bg_color', 'white')

    fig_w, fig_h = _estimate_size(latex_body, bool(subtitle))
    fig = plt.figure(figsize=(fig_w, fig_h), dpi=int(p.get('dpi', 300)), facecolor=bg)

    y_formula = 0.55 if subtitle else 0.50
    fig.text(0.5, y_formula, f'${latex_body}$',
             fontsize=fs, ha='center', va='center', color=color)

    if subtitle:
        fig.text(0.5, 0.08, subtitle,
                 fontsize=sub_size, ha='center', va='center', color=sub_color)

    return _save_fig(fig, p)


# ═══════════════════════════════════════════════
# 多公式组合渲染
# ═══════════════════════════════════════════════
def _render_multi(formulas, params=None):
    """
    在一张图中垂直排列多个公式, 自动编号对齐。

    Args:
        formulas: [(latex_body, label), ...] 列表
        params:   渲染参数
    Returns:
        (file_path, base64_string)
    """
    p = _resolve_params(params)
    n = len(formulas)
    fs = int(p.get('fontsize', 30))
    color = p.get('color', '#000')
    bg = 'none' if p.get('transparent') else p.get('bg_color', 'white')
    row_h = 1.6
    fig_h = max(3.0, n * row_h + 1.0)
    fig_w = 12.0

    fig = plt.figure(figsize=(fig_w, fig_h), dpi=int(p.get('dpi', 300)), facecolor=bg)

    for i, (latex_body, label) in enumerate(formulas):
        y = 1.0 - (i + 0.5) / (n + 0.5)
        fig.text(0.50, y, f'${latex_body}$',
                 fontsize=fs, ha='center', va='center', color=color)
        if label:
            fig.text(0.92, y, f'({label})',
                     fontsize=int(fs * 0.45), ha='left', va='center', color=p.get('subtitle_color', '#666'))

    return _save_fig(fig, p)


# ═══════════════════════════════════════════════
# 注册表
# ═══════════════════════════════════════════════
REGISTRY = {}
MATRIX_TYPES = set()


def register(formula_type, is_matrix=False):
    """装饰器: 注册公式构建函数。is_matrix=True 时走矩阵网格渲染器。"""
    def decorator(func):
        REGISTRY[formula_type] = func
        if is_matrix:
            MATRIX_TYPES.add(formula_type)
        return func
    return decorator


# ═══════════════════════════════════════════════
# 公式构建器 — 标准公式 (返回 latex_body, subtitle)
# ═══════════════════════════════════════════════

@register('integral')
def _b_integral(p, latex):
    """定积分  |  a(下限) b(上限) func(被积函数) var(变量)"""
    a = _num(p.get('lower_limit', p.get('a', 0))); b = _num(p.get('upper_limit', p.get('b', 1))); var = p.get('var', 'x')
    func = p.get('function_expr', p.get('func', 'f(x)'))
    fmap = {'sin': rf'\sin {var}', 'cos': rf'\cos {var}', 'tan': rf'\tan {var}',
            'exp': rf'e^{{{var}}}', 'poly': rf'{var}^{{2}}', 'sqrt': rf'\sqrt{{{var}}}',
            'ln': rf'\ln {var}', 'f(x)': f'f({var})'}
    return rf'\int_{{{a}}}^{{{b}}} {fmap.get(func, func)} \, d{var}', '定积分'


@register('double_integral')
def _b_double_integral(p, latex):
    """二重积分  |  domain(积分域) func(被积函数)"""
    domain = p.get('domain', 'D'); func = p.get('function_expr', p.get('func', 'f(x,y)'))
    return rf'\iint_{{{domain}}} {func}\,dx\,dy', '二重积分'


@register('sum')
def _b_sum(p, latex):
    """求和  |  n(上限) start(起始) var(变量) expr(表达式)"""
    n = int(p.get('n', 10)); s = int(p.get('start', 1))
    var = p.get('var', 'i'); expr = p.get('function_expr', p.get('expr', f'{var}^2'))
    return rf'\sum_{{{var}={s}}}^{{{n}}} {expr}', '求和公式'


@register('multi_sum')
def _b_multi_sum(p, latex):
    """多重求和  |  n m(上限) expr"""
    n = int(p.get('n', 4)); m = int(p.get('m', 3)); expr = p.get('function_expr', p.get('expr', 'a_{ij}'))
    return rf'\sum_{{i=1}}^{{{n}}}\sum_{{j=1}}^{{{m}}} {expr}', '双重求和'


@register('partial_diff')
def _b_partial_diff(p, latex):
    """偏导数  |  func(函数名) var(变量) order(阶数)"""
    func = p.get('func', 'f'); var = p.get('var', 'x'); order = int(p.get('order', 1))
    if order == 1:
        body = rf'\frac{{\partial {func}}}{{\partial {var}}}'
    else:
        body = rf'\frac{{\partial^{{{order}}} {func}}}{{\partial {var}^{{{order}}}}}'
    return body, '偏导数'


@register('gradient')
def _b_gradient(p, latex):
    """梯度  |  func(函数名) vars(变量列表)"""
    func = p.get('func', 'f')
    vs = p.get('vars', ['x', 'y'])
    if isinstance(vs, str):
        vs = [v.strip() for v in vs.split(',')]
    parts = ', '.join(rf'\frac{{\partial {func}}}{{\partial {v}}}' for v in vs)
    return rf'\nabla {func} = \left( {parts} \right)', '梯度'


@register('normal_dist')
def _b_normal_dist(p, latex):
    """正态分布  |  mu(均值) sigma(标准差)"""
    mu = _num(p.get('mu', 0)); sigma = _num(p.get('sigma', 1))
    return (rf'f(x)=\frac{{1}}{{{sigma}\sqrt{{2\pi}}}}'
            rf'e^{{-\frac{{(x-{mu})^2}}{{2\cdot{sigma}^2}}}}'), '正态分布'


@register('bayes')
def _b_bayes(p, latex):
    """贝叶斯  |  PA PBA PB(概率值) compute(是否代入计算)"""
    pa = float(p.get('p_a', p.get('PA', 0.01))); pba = float(p.get('p_b_given_a', p.get('PBA', 0.95))); pb = float(p.get('p_b', p.get('PB', 0.05)))
    if p.get('compute', True) and pb > 0:
        pab = pba * pa / pb
        body = rf'P(A|B)=\frac{{{_num(pba)}\cdot{_num(pa)}}}{{{_num(pb)}}}={pab:.4f}'
    else:
        body = r'P(A|B)=\frac{P(B|A)\cdot P(A)}{P(B)}'
    return body, '贝叶斯公式'


@register('fourier')
def _b_fourier(p, latex):
    """傅里叶变换  |  func(函数名) var(变量) freq_var(频率变量)"""
    func = p.get('func', 'f'); var = p.get('var', 't'); fv = p.get('freq_var', r'\omega')
    return rf'F({fv})=\int_{{-\infty}}^{{\infty}}{func}({var})e^{{-i{fv} {var}}}d{var}', '傅里叶变换'


@register('matrix_mul')
def _b_matrix_mul(p, latex):
    """矩阵乘法  |  mat_a mat_b mat_c(矩阵名)"""
    a = p.get('mat_a', 'A'); b = p.get('mat_b', 'B'); c = p.get('mat_c', 'C')
    return rf'{c}_{{ij}}=\sum_k {a}_{{ik}}{b}_{{kj}}', '矩阵乘法'


@register('polynomial')
def _b_polynomial(p, latex):
    """多项式  |  a b c(系数) var(变量)"""
    a = float(p.get('coeff_a', p.get('a', 2))); b = float(p.get('coeff_b', p.get('b', -3))); c = float(p.get('coeff_c', p.get('c', -5)))
    var = p.get('var', 'x'); terms = []
    if a != 0: terms.append(rf'{_num(a)}{var}^{{2}}')
    if b != 0:
        s = '+ ' if b > 0 and terms else ('- ' if b < 0 else '')
        terms.append(rf'{s}{_num(abs(b))}{var}')
    if c != 0:
        s = '+ ' if c > 0 and terms else ('- ' if c < 0 else '')
        terms.append(rf'{s}{_num(abs(c))}')
    return 'y = ' + (' '.join(terms) if terms else '0'), '多项式'


@register('exponential')
def _b_exponential(p, latex):
    """指数函数  |  a(系数) k/exp(指数) base(底数)"""
    a = p.get('a', ''); k = _num(p.get('exponent', p.get('exp', p.get('k', 2)))); base = p.get('base', 'e')
    prefix = f'{_num(a)} \\cdot ' if a not in ('', 1, '1') else ''
    if base == 'e':
        return rf'y = {prefix}e^{{{k}x}}', '指数函数'
    return rf'y = {prefix}{_num(base)}^{{{k}x}}', '指数函数'


@register('logarithm')
def _b_logarithm(p, latex):
    """对数  |  base(底数, e=自然对数)"""
    base = p.get('base', 'e')
    if base == 'e':
        return r'y = \ln x', '自然对数'
    return rf'y = \log_{{{_num(base)}}} x', '对数函数'


@register('sine_wave')
def _b_sine_wave(p, latex):
    """简谐振动  |  amplitude frequency phase"""
    amp = _num(p.get('amplitude', 2)); freq = _num(p.get('frequency', 1))
    ph = float(p.get('phase', 0))
    ps = (rf'+{_num(ph)}' if ph > 0 else rf'-{_num(abs(ph))}') if ph != 0 else ''
    return rf'y = {amp}\sin({freq}x{ps})', '简谐振动'


@register('limit')
def _b_limit(p, latex):
    """极限  |  var approach func result"""
    var = p.get('var', 'x'); ap = p.get('approach', r'\infty')
    func = p.get('func', f'f({var})'); res = p.get('result', None)
    body = rf'\lim_{{{var} \to {ap}}} {func}'
    if res is not None:
        body += rf' = {_num(res)}'
    return body, '极限'


@register('taylor')
def _b_taylor(p, latex):
    """泰勒展开  |  func a(展开点) n(阶数)"""
    func = p.get('func', 'f'); a = p.get('a', '0'); n = int(p.get('n', 3))
    if str(a) == '0':
        terms = [f'{func}(0)']
        for i in range(1, n + 1):
            coeff = rf"\frac{{{func}^{{({i})}}(0)}}{{{i}!}}" if i > 1 else rf"{func}'(0)"
            power = rf'x^{{{i}}}' if i > 1 else 'x'
            terms.append(rf'{coeff}{power}')
        return ' + '.join(terms) + r' + \cdots', '麦克劳林展开'
    return rf'{func}(x)=\sum_{{n=0}}^{{\infty}}\frac{{{func}^{{(n)}}({a})}}{{n!}}(x-{a})^n', '泰勒展开'


@register('eigenvalue')
def _b_eigenvalue(p, latex):
    """特征值方程  |  mat(矩阵名)"""
    mat = p.get('mat', 'A')
    return rf'\det({mat} - \lambda I) = 0', '特征值方程'


@register('cross_product')
def _b_cross_product(p, latex):
    """向量叉积"""
    return r'\vec{a} \times \vec{b} = |\vec{a}||\vec{b}|\sin\theta \, \hat{n}', '向量叉积'


@register('laplace')
def _b_laplace(p, latex):
    """拉普拉斯变换  |  func(函数名)"""
    func = p.get('func', 'f')
    return rf'\mathcal{{L}}\{{{func}(t)\}}=\int_0^{{\infty}}{func}(t)e^{{-st}}dt', '拉普拉斯变换'


@register('custom')
def _b_custom(p, latex):
    """自定义LaTeX渲染"""
    body = latex if latex else p.get('latex', r'E = mc^2')
    if body.startswith('$'):
        body = body.strip('$')
    return body, p.get('subtitle', None)


# ═══════════════════════════════════════════════
# 公式构建器 — 矩阵类 (走网格渲染器)
# ═══════════════════════════════════════════════

def _parse_matrix_rows(p):
    """从params解析矩阵行数据。"""
    if 'rows' in p and isinstance(p['rows'], list):
        return p['rows']
    rows = []
    for key in ['row1', 'row2', 'row3', 'row4', 'row5']:
        val = p.get(key)
        if val is not None:
            rows.append(str(val).strip().split())
    return rows if rows else [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]


@register('matrix', is_matrix=True)
def _b_matrix(p, latex):
    """矩阵  |  rows/row1~row5(矩阵数据) bracket(括号类型)"""
    rows = _parse_matrix_rows(p)
    bracket = p.get('bracket', 'paren')
    return rows, bracket, '矩阵', None


@register('determinant', is_matrix=True)
def _b_determinant(p, latex):
    """行列式  |  a b c d(2×2元素) show_result(显示结果)"""
    a = float(p.get('a', 2)); b = float(p.get('b', 3))
    c = float(p.get('c', 5)); d = float(p.get('d', 7))
    rows = [[a, b], [c, d]]
    suffix = None
    if p.get('show_result', True):
        det_val = a * d - b * c
        suffix = rf'= {_num(det_val)}'
    return rows, 'vert', '行列式', suffix


# ═══════════════════════════════════════════════
# 主入口
# ═══════════════════════════════════════════════

def render_formula(formula_type, params=None, latex=None):
    """
    公式渲染主入口 — 完全向后兼容 v4/v5 调用方式。

    Args:
        formula_type: 公式类型(如 'integral','matrix','bayes'等, 共22种)
        params:       参数字典(公式参数 + 渲染参数, 可选theme='paper'/'presentation'/'dark')
        latex:        自定义LaTeX(custom类型或未知类型时使用)
    Returns:
        (file_path, base64_string)
    """
    if params is None:
        params = {}

    builder = REGISTRY.get(formula_type)
    if builder is None:
        if latex:
            builder = REGISTRY['custom']
        else:
            logger.warning("未知公式类型 '%s', 回退默认", formula_type)
            return _render_latex(r'E = mc^2', '质能方程', params)

    try:
        if formula_type in MATRIX_TYPES:
            rows, bracket, subtitle, suffix = builder(params, latex)
            return _render_matrix(rows, bracket, subtitle, suffix, params)
        else:
            latex_body, subtitle = builder(params, latex)
            return _render_latex(latex_body, subtitle, params)
    except Exception as e:
        logger.error("公式渲染失败 [%s]: %s", formula_type, e, exc_info=True)
        raise ValueError(f"渲染失败 ({formula_type}): {e}")


def render_batch(formula_list, params=None):
    """
    批量公式渲染 — 一张图中显示多个公式。

    Args:
        formula_list: [{'type':'integral','params':{},'label':'1'}, ...]
        params:       全局渲染参数
    Returns:
        (file_path, base64_string)
    """
    if params is None:
        params = {}
    items = []
    for item in formula_list:
        ft = item.get('type', 'custom')
        fp = item.get('params', {})
        fl = item.get('latex')
        builder = REGISTRY.get(ft, REGISTRY['custom'])
        latex_body, _ = builder(fp, fl)
        items.append((latex_body, item.get('label', str(len(items) + 1))))
    return _render_multi(items, params)
