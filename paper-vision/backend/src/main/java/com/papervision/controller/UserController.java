package com.papervision.controller;

import com.papervision.dto.*;
import com.papervision.entity.User;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/user")
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;
    private String username() { return SecurityContextHolder.getContext().getAuthentication().getName(); }

    @GetMapping("/me")
    public ResponseEntity<User> me() {
        User user = userService.getCurrentUser(username());
        user.setPassword(null);
        return ResponseEntity.ok(user);
    }

    @PutMapping("/profile")
    public ResponseEntity<String> updateProfile(@RequestBody UserUpdateDTO dto) {
        userService.updateProfile(username(), dto);
        return ResponseEntity.ok("OK");
    }

    @PutMapping("/password")
    public ResponseEntity<String> changePassword(@RequestBody PasswordDTO dto) {
        userService.changePassword(username(), dto);
        return ResponseEntity.ok("OK");
    }
}
