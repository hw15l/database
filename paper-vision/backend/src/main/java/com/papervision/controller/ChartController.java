package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.dto.BatchChartTaskDTO;
import com.papervision.dto.CreateChartTaskDTO;
import com.papervision.entity.Chart;
import com.papervision.entity.Task;
import com.papervision.entity.User;
import com.papervision.service.ChartService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.ArrayList;
import java.util.List;

@RestController
@RequestMapping("/api/chart")
@RequiredArgsConstructor
public class ChartController {
    private final ChartService chartService;
    private final UserService userService;
    private Long uid() {
        User u = userService.getCurrentUser(SecurityContextHolder.getContext().getAuthentication().getName());
        if (u == null) throw new BusinessException(401, "用户未登录或不存在");
        return u.getId();
    }

    @GetMapping("/list")
    public Result<List<Chart>> list() {
        return Result.ok(chartService.listCharts());
    }

    @GetMapping("/category/{catId}")
    public Result<List<Chart>> listByCategory(@PathVariable Long catId) {
        return Result.ok(chartService.listByCategory(catId));
    }

    @PostMapping("/generate")
    public Result<Task> generate(@Valid @RequestBody CreateChartTaskDTO dto) {
        return Result.ok(chartService.createChartTask(uid(), dto.getChartId(), dto.getFileId(), dto.getParams()));
    }

    @PostMapping("/generate-batch")
    @Transactional
    public Result<List<Task>> generateBatch(@Valid @RequestBody BatchChartTaskDTO dto) {
        if (dto.getChartIds() == null || dto.getChartIds().isEmpty()) {
            throw new BusinessException("请至少选择一种图表");
        }
        if (dto.getChartIds().size() > 20) {
            throw new BusinessException("单次批量最多生成20个图表");
        }
        Long userId = uid();
        List<Task> tasks = new ArrayList<>();
        for (Long chartId : dto.getChartIds()) {
            tasks.add(chartService.createChartTask(userId, chartId, dto.getFileId(), dto.getParams()));
        }
        return Result.ok(tasks);
    }
}
