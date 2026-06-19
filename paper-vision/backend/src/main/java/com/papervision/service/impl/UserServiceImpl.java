package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.config.JwtUtils;
import com.papervision.dto.*;
import com.papervision.entity.User;
import com.papervision.mapper.UserMapper;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {
    private final UserMapper userMapper;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtils jwtUtils;

    private List<String> getUserRoles(Long userId) {
        List<String> roles = new ArrayList<>();
        List<Map<String, Object>> dbRoles = userMapper.selectUserRoles(userId);
        if (dbRoles != null) {
            for (Map<String, Object> row : dbRoles) {
                Object code = row.get("role_code");
                if (code != null) roles.add(code.toString());
            }
        }
        if (roles.isEmpty()) roles.add("ROLE_USER"); // fallback
        return roles;
    }

    @Override
    public Map<String, Object> login(LoginDTO dto) {
        User user = userMapper.selectOne(
                new LambdaQueryWrapper<User>().eq(User::getUsername, dto.getUsername()));
        if (user == null || (user.getStatus() != null && user.getStatus() == 0))
            throw new RuntimeException("用户名或密码错误");
        if (!passwordEncoder.matches(dto.getPassword(), user.getPassword()))
            throw new RuntimeException("用户名或密码错误");
        user.setLastLoginTime(LocalDateTime.now());
        userMapper.updateById(user);
        List<String> roles = getUserRoles(user.getId());
        String token = jwtUtils.generateToken(user.getUsername(), roles);
        user.setPassword(null);
        Map<String, Object> result = new HashMap<>();
        result.put("token", token);
        result.put("user", user);
        result.put("roles", roles);
        return result;
    }

    @Override
    public Map<String, Object> register(RegisterDTO dto) {
        if (userMapper.selectCount(new LambdaQueryWrapper<User>().eq(User::getUsername, dto.getUsername())) > 0)
            throw new RuntimeException("用户名已存在");
        User user = new User();
        user.setUsername(dto.getUsername());
        user.setPassword(passwordEncoder.encode(dto.getPassword()));
        user.setEmail(dto.getEmail());
        user.setNickname(dto.getNickname() != null ? dto.getNickname() : dto.getUsername());
        userMapper.insert(user);
        userMapper.insertDefaultRole(user.getId());
        List<String> roles = getUserRoles(user.getId());
        String token = jwtUtils.generateToken(user.getUsername(), roles);
        user.setPassword(null);
        Map<String, Object> result = new HashMap<>();
        result.put("token", token);
        result.put("user", user);
        result.put("roles", roles);
        return result;
    }

    @Override
    @Cacheable(value = "user", key = "#username")
    public User getCurrentUser(String username) {
        return userMapper.selectOne(new LambdaQueryWrapper<User>().eq(User::getUsername, username));
    }

    @Override
    public void updateProfile(String username, UserUpdateDTO dto) {
        User user = getCurrentUser(username);
        if (dto.getEmail() != null) user.setEmail(dto.getEmail());
        if (dto.getNickname() != null) user.setNickname(dto.getNickname());
        if (dto.getAvatar() != null) user.setAvatar(dto.getAvatar());
        userMapper.updateById(user);
    }

    @Override
    public void changePassword(String username, PasswordDTO dto) {
        User user = getCurrentUser(username);
        if (!passwordEncoder.matches(dto.getOldPassword(), user.getPassword())) throw new RuntimeException("原密码错误");
        user.setPassword(passwordEncoder.encode(dto.getNewPassword()));
        userMapper.updateById(user);
    }
}
