"""
上传27个测试Excel到数据中心 + 全流程渲染测试
"""
import os, sys, json, base64, time, urllib.request, urllib.error

BASE = "http://localhost:8080/api"
PY_DIR = os.path.dirname(__file__)
TEST_DIR = os.path.join(PY_DIR, 'test_data')

CHART_MAP = [
    ('bar', '柱状图测试'),
    ('grouped_bar', '分组柱状图测试'),
    ('stacked_bar', '堆叠柱状图测试'),
    ('line', '折线图测试'),
    ('multi_line', '多折线图测试'),
    ('scatter', '散点图测试'),
    ('bubble', '气泡图测试'),
    ('pie', '饼图测试'),
    ('donut', '环形图测试'),
    ('heatmap', '热力图测试'),
    ('boxplot', '箱线图测试'),
    ('violin', '小提琴图测试'),
    ('radar', '雷达图测试'),
    ('gantt', '甘特图测试'),
    ('sankey', '桑基图测试'),
    ('treemap', '矩形树图测试'),
    ('parallel', '平行坐标图测试'),
    ('wordcloud', '词云测试'),
    ('surface3d', '3D曲面图测试'),
    ('pareto', '帕累托图测试'),
    ('candlestick', 'K线图测试'),
    ('area', '面积图测试'),
    ('venn', '韦恩图测试'),
    ('network', '网络关系图测试'),
    ('plotly_scatter', 'Plotly交互散点图测试'),
    ('bokeh_bar', 'Bokeh交互柱状图测试'),
    ('altair', 'Altair声明式图表测试'),
]


def api(method, path, data=None, token=None):
    url = BASE + path
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=60)
        result = json.loads(resp.read().decode())
        if result.get("code") == 200:
            return result.get("data")
        print(f"    API error: {result.get('message')}")
        return None
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            err = json.loads(body)
            print(f"    HTTP {e.code}: {err.get('message', body[:100])}")
        except:
            print(f"    HTTP {e.code}: {body[:100]}")
        return None
    except Exception as e:
        print(f"    Request failed: {e}")
        return None


def register_or_login(username, password):
    print(f"  尝试登录: {username}")
    result = api("POST", "/auth/login", {"username": username, "password": password})
    if result and result.get("token"):
        print(f"  登录成功")
        return result["token"]
    print(f"  登录失败, 尝试注册...")
    result = api("POST", "/auth/register", {
        "username": username, "password": password,
        "email": f"{username}@test.com", "nickname": "测试用户"
    })
    if result and result.get("token"):
        print(f"  注册并登录成功")
        return result["token"]
    print(f"  注册也失败!")
    return None


def upload_file(token, filepath, filename):
    with open(filepath, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    result = api("POST", "/data/upload", {"fileName": filename, "fileData": b64}, token)
    return result


def get_chart_id_by_code(token, chart_code):
    charts = api("GET", "/chart/list", token=token)
    if charts:
        for c in charts:
            if c.get("chartCode") == chart_code:
                return c.get("id")
    return None


def main():
    print("=" * 60)
    print("步骤1: 认证")
    print("=" * 60)
    token = register_or_login("testuser", "Test123456")
    if not token:
        print("认证失败, 退出")
        return False

    print("\n" + "=" * 60)
    print("步骤2: 上传27个测试Excel到数据中心")
    print("=" * 60)
    uploaded_files = {}
    for chart_code, name in CHART_MAP:
        fpath = os.path.join(TEST_DIR, f"{name}.xlsx")
        if not os.path.exists(fpath):
            print(f"  [SKIP] {name}.xlsx 不存在")
            continue
        result = upload_file(token, fpath, f"{name}.xlsx")
        if result and result.get("id"):
            uploaded_files[chart_code] = result
            print(f"  [OK] {name}.xlsx -> fileId={result['id']} ({result.get('totalRows',0)}行)")
        else:
            print(f"  [FAIL] {name}.xlsx 上传失败")

    print(f"\n  成功上传: {len(uploaded_files)}/27")

    print("\n" + "=" * 60)
    print("步骤3: 获取图表类型列表")
    print("=" * 60)
    charts = api("GET", "/chart/list", token=token)
    if not charts:
        print("  无法获取图表列表!")
        return False
    chart_id_map = {c["chartCode"]: c["id"] for c in charts}
    print(f"  系统中共有 {len(charts)} 种图表类型")

    print("\n" + "=" * 60)
    print("步骤4: 逐一调用渲染接口测试")
    print("=" * 60)
    results = []
    for chart_code, name in CHART_MAP:
        chart_id = chart_id_map.get(chart_code)
        file_info = uploaded_files.get(chart_code)

        if not chart_id:
            print(f"  [SKIP] {name} - 图表类型 {chart_code} 不在数据库中")
            results.append((chart_code, name, "SKIP", "图表类型不存在"))
            continue
        if not file_info:
            print(f"  [SKIP] {name} - 文件未上传成功")
            results.append((chart_code, name, "SKIP", "文件未上传"))
            continue

        task = api("POST", "/chart/generate", {
            "chartId": chart_id,
            "fileId": file_info["id"],
            "params": {"colorScheme": "Set2", "dpi": 150}
        }, token)

        if task and task.get("status") == "SUCCESS":
            print(f"  [PASS] {name:<20s} taskId={task['id']} status=SUCCESS")
            results.append((chart_code, name, "PASS", f"taskId={task['id']}"))
        elif task:
            print(f"  [FAIL] {name:<20s} taskId={task.get('id')} status={task.get('status')} err={task.get('errorMsg','')[:50]}")
            results.append((chart_code, name, "FAIL", task.get("errorMsg", "")[:80]))
        else:
            print(f"  [FAIL] {name:<20s} API调用失败")
            results.append((chart_code, name, "FAIL", "API调用失败"))

    print("\n" + "=" * 60)
    print("全流程测试结果汇总")
    print("=" * 60)
    passed = sum(1 for r in results if r[2] == "PASS")
    failed = sum(1 for r in results if r[2] == "FAIL")
    skipped = sum(1 for r in results if r[2] == "SKIP")
    print(f"  通过: {passed}")
    print(f"  失败: {failed}")
    print(f"  跳过: {skipped}")

    if failed > 0:
        print("\n  失败项:")
        for r in results:
            if r[2] == "FAIL":
                print(f"    - {r[1]} ({r[0]}): {r[3]}")

    if skipped > 0:
        print("\n  跳过项(图表类型未在数据库注册):")
        for r in results:
            if r[2] == "SKIP":
                print(f"    - {r[1]} ({r[0]}): {r[3]}")

    return failed == 0


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
