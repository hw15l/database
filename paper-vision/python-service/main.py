"""
论文可视化助手 - Python 渲染服务入口
FastAPI 提供 /render/chart 和 /render/formula 两个接口
"""
import os
import logging
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from chart_service import render_chart
from formula_service import render_formula

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

app = FastAPI(title="Paper Vision Render Service", version="1.0.0")

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUTPUT_DIR, exist_ok=True)

MAX_PARAM_COUNT = 30
MAX_LATEX_LENGTH = 2000
ALLOWED_CHART_TYPES = {
    'bar', 'grouped_bar', 'stacked_bar', 'line', 'multi_line', 'scatter', 'bubble',
    'pie', 'donut', 'heatmap', 'boxplot', 'violin', 'radar', 'gantt', 'sankey',
    'treemap', 'parallel', 'wordcloud', 'surface3d', 'pareto', 'candlestick',
    'area', 'venn', 'network', 'plotly_scatter', 'bokeh_bar', 'altair'
}


class ChartRequest(BaseModel):
    chart_type: str = 'bar'
    file_path: Optional[str] = None
    params: dict = {}

    @field_validator('chart_type')
    @classmethod
    def validate_chart_type(cls, v):
        if v not in ALLOWED_CHART_TYPES:
            raise ValueError(f'不支持的图表类型: {v}')
        return v

    @field_validator('params')
    @classmethod
    def validate_params(cls, v):
        if len(v) > MAX_PARAM_COUNT:
            raise ValueError(f'参数数量超过限制({MAX_PARAM_COUNT})')
        dpi = v.get('dpi')
        if dpi is not None:
            dpi = int(dpi)
            if dpi < 72 or dpi > 600:
                raise ValueError('DPI范围应在72-600之间')
            v['dpi'] = min(max(dpi, 72), 600)
        return v


class FormulaRequest(BaseModel):
    formula_type: str = 'integral'
    latex: Optional[str] = None
    params: dict = {}

    @field_validator('latex')
    @classmethod
    def validate_latex(cls, v):
        if v is not None and len(v) > MAX_LATEX_LENGTH:
            raise ValueError(f'LaTeX表达式长度不能超过{MAX_LATEX_LENGTH}字符')
        return v

    @field_validator('params')
    @classmethod
    def validate_params(cls, v):
        if len(v) > MAX_PARAM_COUNT:
            raise ValueError(f'参数数量超过限制({MAX_PARAM_COUNT})')
        return v


@app.get("/health")
async def health():
    return {"status": "ok", "service": "paper-vision-render"}


@app.post("/render/chart")
async def render_chart_api(req: ChartRequest):
    try:
        logger.info("图表渲染请求: type=%s, file=%s", req.chart_type, req.file_path)
        path, b64 = render_chart(req.chart_type, req.file_path, req.params)
        return JSONResponse({"status": "success", "image_path": path, "image_base64": b64, "chart_type": req.chart_type})
    except ValueError as e:
        logger.warning("图表渲染参数错误 [%s]: %s", req.chart_type, e)
        return JSONResponse({"status": "error", "message": str(e)}, status_code=400)
    except Exception as e:
        logger.error("图表渲染失败 [%s]: %s", req.chart_type, e, exc_info=True)
        return JSONResponse({"status": "error", "message": "渲染服务内部错误"}, status_code=500)


@app.post("/render/formula")
async def render_formula_api(req: FormulaRequest):
    try:
        logger.info("公式渲染请求: type=%s", req.formula_type)
        path, b64 = render_formula(req.formula_type, req.params, req.latex)
        return JSONResponse({"status": "success", "image_path": path, "image_base64": b64, "formula_type": req.formula_type})
    except ValueError as e:
        logger.warning("公式渲染参数错误 [%s]: %s", req.formula_type, e)
        return JSONResponse({"status": "error", "message": str(e)}, status_code=400)
    except Exception as e:
        logger.error("公式渲染失败 [%s]: %s", req.formula_type, e, exc_info=True)
        return JSONResponse({"status": "error", "message": "渲染服务内部错误"}, status_code=500)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5002)
