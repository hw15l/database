"""
论文可视化助手 - Python 渲染服务入口
FastAPI 提供 /render/chart 和 /render/formula 两个接口
"""
import os
import traceback
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from typing import Optional
from chart_service import render_chart
from formula_service import render_formula

app = FastAPI(title="Paper Vision Render Service", version="1.0.0")

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUTPUT_DIR, exist_ok=True)


class ChartRequest(BaseModel):
    chart_type: str = 'bar'
    file_path: Optional[str] = None
    params: dict = {}


class FormulaRequest(BaseModel):
    formula_type: str = 'integral'
    latex: Optional[str] = None
    params: dict = {}


@app.get("/health")
async def health():
    return {"status": "ok", "service": "paper-vision-render"}


@app.post("/render/chart")
async def render_chart_api(req: ChartRequest):
    try:
        path, b64 = render_chart(req.chart_type, req.file_path, req.params)
        return JSONResponse({"status": "success", "image_path": path, "image_base64": b64, "chart_type": req.chart_type})
    except Exception as e:
        traceback.print_exc()
        return JSONResponse({"status": "error", "message": str(e)}, status_code=500)


@app.post("/render/formula")
async def render_formula_api(req: FormulaRequest):
    try:
        path, b64 = render_formula(req.formula_type, req.params, req.latex)
        return JSONResponse({"status": "success", "image_path": path, "image_base64": b64, "formula_type": req.formula_type})
    except Exception as e:
        traceback.print_exc()
        return JSONResponse({"status": "error", "message": str(e)}, status_code=500)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5002)
