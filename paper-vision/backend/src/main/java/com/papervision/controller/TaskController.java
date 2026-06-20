package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.entity.History;
import com.papervision.entity.Task;
import com.papervision.service.DatabaseService;
import com.papervision.service.TaskService;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/task")
@RequiredArgsConstructor
public class TaskController {
    private final TaskService taskService;
    private final UserService userService;
    private final DatabaseService databaseService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @GetMapping("/list")
    public Result<List<Task>> listTasks() {
        return Result.ok(taskService.listByUser(uid()));
    }

    @GetMapping("/{taskId}")
    public Result<Task> getTask(@PathVariable Long taskId) {
        Task task = taskService.getTask(taskId);
        if (task == null) throw new BusinessException(404, "任务不存在");
        if (!task.getUserId().equals(uid())) throw new BusinessException(403, "无权访问该任务");
        return Result.ok(task);
    }

    /** 任务详情增强 — [DB] v_task_detail_enhanced视图(6表JOIN+窗口函数+闭包表路径) */
    @GetMapping("/{taskId}/detail")
    public Result<Map<String, Object>> getTaskDetail(@PathVariable Long taskId) {
        return Result.ok(databaseService.getTaskDetailEnhanced(taskId));
    }

    @GetMapping("/{taskId}/image")
    public ResponseEntity<byte[]> getImage(@PathVariable Long taskId) {
        Task task = taskService.getTask(taskId);
        if (task == null) throw new BusinessException(404, "任务不存在");
        if (!task.getUserId().equals(uid())) throw new BusinessException(403, "无权访问该任务");
        byte[] data = taskService.getResultImage(taskId);
        if (data == null) throw new BusinessException(404, "结果图片不存在");
        HttpHeaders headers = new HttpHeaders();
        String path = task.getResultPath();
        headers.setContentType(path != null && path.endsWith(".html") ? MediaType.TEXT_HTML : MediaType.IMAGE_PNG);
        return new ResponseEntity<>(data, headers, HttpStatus.OK);
    }

    @GetMapping("/history")
    public Result<List<History>> listHistory() {
        return Result.ok(taskService.listHistory(uid()));
    }

    @DeleteMapping("/history/{historyId}")
    public Result<Void> deleteHistory(@PathVariable Long historyId) {
        taskService.deleteHistory(historyId, uid());
        return Result.ok();
    }
}
