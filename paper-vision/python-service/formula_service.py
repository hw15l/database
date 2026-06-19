"""
公式可视化引擎 v4
渲染用户参数代入后的 LaTeX 印刷体数学公式。
矩阵/行列式用手绘括号替代 mathtext（mathtext 不支持 \begin{array}）。
"""
import os, base64, uuid, numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUTPUT_DIR, exist_ok=True)

for _fp in [r'C:\Windows\Fonts\simhei.ttf', r'C:\Windows\Fonts\msyh.ttc']:
    if os.path.exists(_fp):
        try: fm.fontManager.addfont(_fp); break
        except Exception: pass
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams['mathtext.fontset'] = 'cm'


def _save_path():
    return os.path.join(OUTPUT_DIR, f'formula_{uuid.uuid4().hex}.png')

def _num(v):
    f = float(v)
    return str(int(f)) if f == int(f) else f'{f:g}'

def _render(latex_body, subtitle=None, dpi=300):
    fig = plt.figure(figsize=(9, 4), dpi=dpi, facecolor='white')
    fig.text(0.5, 0.55, f'${latex_body}$', fontsize=34, ha='center', va='center', color='#1a1a2e')
    if subtitle:
        fig.text(0.5, 0.16, subtitle, fontsize=15, ha='center', va='center', color='#888888')
    fig.text(0.5, 0.88, '─' * 30, fontsize=12, ha='center', va='center', color='#dddddd')
    path = _save_path()
    fig.savefig(path, dpi=dpi, bbox_inches='tight', facecolor='white', edgecolor='none', pad_inches=0.5)
    plt.close(fig)
    with open(path, 'rb') as f:
        return path, base64.b64encode(f.read()).decode()

def _draw_matrix(data_rows, subtitle, dpi=300):
    """手绘矩阵：圆括号 + 等宽对齐元素。"""
    nrows = len(data_rows); ncols = max(len(r) for r in data_rows)
    fig, ax = plt.subplots(figsize=(ncols*1.6+1.5, nrows*0.8+1.5), dpi=dpi, facecolor='white')
    ax.axis('off'); ax.set_xlim(-1, ncols+0.5); ax.set_ylim(-0.5, nrows+0.5)
    lw = 3
    # 左括号（圆括号造型：上下弯角+中间竖线）
    ax.plot([-0.3,-0.1], [nrows-0.3,nrows-0.3], color='#333', lw=lw, solid_capstyle='round')
    ax.plot([-0.3,-0.1], [0.3,0.3], color='#333', lw=lw, solid_capstyle='round')
    ax.plot([-0.3,-0.3], [0.3,nrows-0.3], color='#333', lw=lw, solid_capstyle='butt')
    ax.plot([-0.3,-0.3], [0.3,nrows-0.3], color='#333', lw=lw, solid_capstyle='butt')
    # 右括号
    ax.plot([ncols+0.1,ncols+0.3], [nrows-0.3,nrows-0.3], color='#333', lw=lw, solid_capstyle='round')
    ax.plot([ncols+0.1,ncols+0.3], [0.3,0.3], color='#333', lw=lw, solid_capstyle='round')
    ax.plot([ncols+0.3,ncols+0.3], [0.3,nrows-0.3], color='#333', lw=lw, solid_capstyle='butt')
    for i, row in enumerate(data_rows):
        for j, cell in enumerate(row):
            ax.text(j+0.5, nrows-i-1+0.5, str(_num(cell)), fontsize=20,
                    ha='center', va='center', family='monospace', color='#1a1a2e')
    ax.text(ncols/2, nrows+0.8, subtitle, fontsize=13, ha='center', va='center', color='#888888')
    path = _save_path()
    fig.savefig(path, dpi=dpi, bbox_inches='tight', facecolor='white', edgecolor='none', pad_inches=0.3)
    plt.close(fig)
    with open(path, 'rb') as f:
        return path, base64.b64encode(f.read()).decode()

def _draw_determinant(vals, det, dpi=300):
    """手绘 2x2 行列式：竖线 + 数字 + = 结果。"""
    a, b, c, d = vals
    fig, ax = plt.subplots(figsize=(6, 3), dpi=dpi, facecolor='white')
    ax.axis('off')
    for (i, j, v) in [(0,0,a),(0,1,b),(1,0,c),(1,1,d)]:
        ax.text(j+0.5, 1.5-i, str(_num(v)), fontsize=26, ha='center', va='center',
                family='monospace', color='#1a1a2e')
    ax.plot([-0.15,-0.15], [0,2], color='#333', lw=3)
    ax.plot([2.15,2.15], [0,2], color='#333', lw=3)
    eq_x = 3.5
    ax.text(eq_x, 1, f'= {_num(det)}', fontsize=28, ha='left', va='center',
            family='monospace', color='#1a1a2e')
    ax.text(1, 2.3, '行列式', fontsize=12, ha='center', va='center', color='#888888')
    ax.set_xlim(-0.5, eq_x+2); ax.set_ylim(-0.2, 2.5)
    path = _save_path()
    fig.savefig(path, dpi=dpi, bbox_inches='tight', facecolor='white', edgecolor='none', pad_inches=0.3)
    plt.close(fig)
    with open(path, 'rb') as f:
        return path, base64.b64encode(f.read()).decode()


def render_formula(formula_type, params=None, latex=None):
    if params is None: params = {}
    p = params

    if formula_type == 'integral':
        a = _num(p.get('a',0)); b = _num(p.get('b',1))
        func = p.get('func','f(x)')
        fmap = {'sin':r'\sin x','cos':r'\cos x','exp':'e^{x}','poly':'x^{2}','f(x)':'f(x)'}
        return _render(rf'\int_{{{a}}}^{{{b}}} {fmap.get(func,"f(x)")} \, dx', '定积分')

    elif formula_type == 'double_integral':
        return _render(r'\iint_{D} f(x,y)\,dx\,dy', '二重积分')

    elif formula_type == 'sum':
        n = int(p.get('n',10)); expr = p.get('expr','i^2')
        return _render(rf'\sum_{{i=1}}^{{{n}}} {expr}', '求和公式')

    elif formula_type == 'multi_sum':
        n = int(p.get('n',4)); m = int(p.get('m',3))
        return _render(rf'\sum_{{i=1}}^{{{n}}}\sum_{{j=1}}^{{{m}}} a_{{ij}}', '双重求和')

    elif formula_type == 'matrix':
        r1 = p.get('row1','1 2 3'); r2 = p.get('row2','4 5 6'); r3 = p.get('row3','7 8 9')
        rows = [r1.strip().split(), r2.strip().split(), r3.strip().split()]
        return _draw_matrix(rows, '矩阵')

    elif formula_type == 'determinant':
        a = float(p.get('a',2)); b = float(p.get('b',3))
        c = float(p.get('c',5)); d = float(p.get('d',7))
        return _draw_determinant([a,b,c,d], a*d-b*c)

    elif formula_type == 'partial_diff':
        return _render(r'\frac{\partial f}{\partial x}', '偏导数')

    elif formula_type == 'gradient':
        return _render(r'\nabla f = (\frac{\partial f}{\partial x}, \frac{\partial f}{\partial y})', '梯度')

    elif formula_type == 'normal_dist':
        mu = _num(p.get('mu',0)); sigma = _num(p.get('sigma',1))
        return _render(rf'f(x)=\frac{{1}}{{{sigma}\sqrt{{2\pi}}}}e^{{-\frac{{(x-{mu})^2}}{{2{sigma}^2}}}}', '正态分布')

    elif formula_type == 'bayes':
        pa = float(p.get('PA',0.01)); pba = float(p.get('PBA',0.95)); pb = float(p.get('PB',0.05))
        pab = pba*pa/pb if pb>0 else 0
        return _render(rf'P(A|B)=\frac{{{_num(pba)}\cdot{_num(pa)}}}{{{_num(pb)}}}={pab:.4f}', '贝叶斯公式')

    elif formula_type == 'fourier':
        return _render(r'F(\omega)=\int_{-\infty}^{\infty}f(t)e^{-i\omega t}dt', '傅里叶变换')

    elif formula_type == 'matrix_mul':
        return _render(r'C_{ij}=\sum_k A_{ik}B_{kj}', '矩阵乘法')

    elif formula_type == 'polynomial':
        a = float(p.get('a',2)); b = float(p.get('b',-3)); c = float(p.get('c',-5))
        terms = []
        if a != 0: terms.append(rf'{_num(a)}x^{{2}}')
        if b != 0: terms.append((r'+ ' if b>0 else r'- ')+rf'{_num(abs(b))}x')
        if c != 0: terms.append((r'+ ' if c>0 else r'- ')+_num(abs(c)))
        body = 'y = '+' '.join(terms) if terms else 'y = 0'
        return _render(body, '二次多项式')

    elif formula_type == 'exponential':
        k = _num(p.get('exp',2))
        return _render(rf'y = e^{{{k}x}}', '指数函数')

    elif formula_type == 'logarithm':
        base = p.get('base','e')
        if base == 'e': return _render(r'y = \ln x', '自然对数')
        return _render(rf'y = \log_{{{_num(base)}}} x', '对数函数')

    elif formula_type == 'sine_wave':
        amp = _num(p.get('amplitude',2)); freq = _num(p.get('frequency',1))
        ph = float(p.get('phase',0))
        phase_str = '' if ph==0 else (rf'+{_num(abs(ph))}' if ph>0 else rf'-{_num(abs(ph))}')
        return _render(rf'y = {amp}\sin({freq}x{phase_str})', '简谐振动')

    else:
        if latex:
            body = latex[1:-1] if latex.startswith('$') else latex
            return _render(body)
        return _render(r'E = mc^2', '质能方程')
