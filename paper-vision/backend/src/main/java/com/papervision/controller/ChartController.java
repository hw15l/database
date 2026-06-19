package com.papervision.controller;

import com.papervision.entity.Chart;
import com.papervision.entity.Task;
import com.papervision.service.ChartService;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/chart")
@RequiredArgsConstructor
public class ChartController {
    private final ChartService chartService;
    private final UserService userService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @GetMapping("/list")
    public ResponseEntity<List<Chart>> list() { return ResponseEntity.ok(chartService.listCharts()); }

    @GetMapping("/category/{catId}")
    public ResponseEntity<List<Chart>> listByCategory(@PathVariable Long catId) {
        return ResponseEntity.ok(chartService.listByCategory(catId));
    }

    @PostMapping("/generate")
    public ResponseEntity<Task> generate(@RequestBody Map<String, Object> req) {
        Long chartId = req.get("chartId") != null ? Long.valueOf(req.get("chartId").toString()) : null;
        if (chartId == null) throw new RuntimeException("chartId is required");
        Long fileId = req.get("fileId") != null ? Long.valueOf(req.get("fileId").toString()) : null;
        Map<String, Object> params = (Map<String, Object>) req.get("params");
        return ResponseEntity.ok(chartService.createChartTask(uid(), chartId, fileId, params));
    }

    @PostMapping("/generate-batch")
    public ResponseEntity<List<Task>> generateBatch(@RequestBody Map<String, Object> req) {
        Object idsObj = req.get("chartIds");
        if (!(idsObj instanceof List)) throw new RuntimeException("chartIds (array) is required");
        List<?> rawIds = (List<?>) idsObj;
        if (rawIds.isEmpty()) throw new RuntimeException("请至少选择一种图表");
        Long fileId = req.get("fileId") != null ? Long.valueOf(req.get("fileId").toString()) : null;
        Map<String, Object> params = (Map<String, Object>) req.get("params");
        Long userId = uid();
        List<Task> tasks = new ArrayList<>();
        for (Object idObj : rawIds) {
            Long chartId = Long.valueOf(idObj.toString());
            tasks.add(chartService.createChartTask(userId, chartId, fileId, params));
        }
        return ResponseEntity.ok(tasks);
    }
}
