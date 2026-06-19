package com.papervision.controller;

import com.papervision.common.Result;
import com.papervision.dto.*;
import com.papervision.entity.User;
import com.papervision.service.DatabaseService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/user")
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;
    private final DatabaseService databaseService;
    private String username() { return SecurityContextHolder.getContext().getAuthentication().getName(); }

    @GetMapping("/me")
    public Result<User> me() {
        User user = userService.getCurrentUser(username());
        user.setPassword(null);
        return Result.ok(user);
    }

    @GetMapping("/profile360")
    public Result<Map<String, Object>> profile360() {
        Long userId = userService.getCurrentUser(username()).getId();
        return Result.ok(databaseService.getUserProfile360(userId));
    }

    @GetMapping("/quota")
    public Result<Map<String, Object>> quota() {
        Long userId = userService.getCurrentUser(username()).getId();
        return Result.ok(databaseService.checkQuota(userId));
    }

    @PutMapping("/profile")
    public Result<Void> updateProfile(@Valid @RequestBody UserUpdateDTO dto) {
        userService.updateProfile(username(), dto);
        return Result.ok();
    }

    @PutMapping("/password")
    public Result<Void> changePassword(@Valid @RequestBody PasswordDTO dto) {
        userService.changePassword(username(), dto);
        return Result.ok();
    }
}
