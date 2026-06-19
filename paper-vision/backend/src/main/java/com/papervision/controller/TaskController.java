package com.papervision.controller;

import com.papervision.entity.History;
import com.papervision.entity.Task;
import com.papervision.service.TaskService;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/task")
@RequiredArgsConstructor
public class TaskController {
    private final TaskService taskService;
    private final UserService userService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @GetMapping("/list")
    public ResponseEntity<List<Task>> listTasks() {
        return ResponseEntity.ok(taskService.listByUser(uid()));
    }

    @GetMapping("/{taskId}")
    public ResponseEntity<Task> getTask(@PathVariable Long taskId) {
        Task task = taskService.getTask(taskId);
        if (task == null || !task.getUserId().equals(uid()))
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        return ResponseEntity.ok(task);
    }

    @GetMapping("/{taskId}/image")
    public ResponseEntity<byte[]> getImage(@PathVariable Long taskId) {
        Task task = taskService.getTask(taskId);
        if (task == null || !task.getUserId().equals(uid()))
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        byte[] data = taskService.getResultImage(taskId);
        if (data == null) return ResponseEntity.notFound().build();
        HttpHeaders headers = new HttpHeaders();
        String path = task.getResultPath();
        if (path != null && path.endsWith(".html")) {
            headers.setContentType(MediaType.TEXT_HTML);
        } else {
            headers.setContentType(MediaType.IMAGE_PNG);
        }
        return new ResponseEntity<>(data, headers, HttpStatus.OK);
    }

    @GetMapping("/history")
    public ResponseEntity<List<History>> listHistory() {
        return ResponseEntity.ok(taskService.listHistory(uid()));
    }

    @DeleteMapping("/history/{historyId}")
    public ResponseEntity<String> deleteHistory(@PathVariable Long historyId) {
        taskService.deleteHistory(historyId, uid());
        return ResponseEntity.ok("OK");
    }
}
