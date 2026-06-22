package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.entity.History;
import com.papervision.entity.Task;
import com.papervision.entity.User;
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
    private Long uid() {
        User u = userService.getCurrentUser(SecurityContextHolder.getContext().getAuthentication().getName());
        if (u == null) throw new BusinessException(401, "用户未登录或不存在");
        return u.getId();
    }

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
        Task task = taskService.getTask(taskId);
        if (task == null) throw new BusinessException(404, "任务不存在");
        if (!task.getUserId().equals(uid())) throw new BusinessException(403, "无权访问该任务");
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
        if (path != null && path.endsWith(".html")) {
            headers.setContentType(MediaType.parseMediaType("text/html;charset=UTF-8"));
        } else {
            headers.setContentType(MediaType.IMAGE_PNG);
        }
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

    @PutMapping("/history/{historyId}/rating")
    public Result<Void> rateHistory(@PathVariable Long historyId, @RequestParam Integer rating) {
        taskService.rateHistory(historyId, uid(), rating);
        return Result.ok();
    }

    @PutMapping("/history/{historyId}/favorite")
    public Result<Void> toggleFavorite(@PathVariable Long historyId) {
        taskService.toggleFavorite(historyId, uid());
        return Result.ok();
    }
}
