package com.papervision.controller;

import com.papervision.entity.User;
import com.papervision.mapper.UserMapper;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {
    private final TaskService taskService;
    private final UserMapper userMapper;

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> stats() {
        return ResponseEntity.ok(taskService.getStats());
    }

    @GetMapping("/ranking")
    public ResponseEntity<Map<String, Object>> ranking(@RequestParam(defaultValue = "10") int topN) {
        return ResponseEntity.ok(taskService.getUserRanking(topN));
    }

    @GetMapping("/users")
    public ResponseEntity<List<User>> listUsers() {
        List<User> users = userMapper.selectList(null);
        users.forEach(u -> u.setPassword(null));
        return ResponseEntity.ok(users);
    }

    @PutMapping("/users/{id}/status")
    public ResponseEntity<String> toggleUser(@PathVariable Long id, @RequestParam Integer status) {
        User user = userMapper.selectById(id);
        if (user != null) { user.setStatus(status); userMapper.updateById(user); }
        return ResponseEntity.ok("更新成功");
    }
}
