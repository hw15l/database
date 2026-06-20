package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.config.JwtUtils;
import com.papervision.dto.*;
import com.papervision.entity.User;
import com.papervision.mapper.UserMapper;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.*;

@Slf4j
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
        if (roles.isEmpty()) roles.add("ROLE_USER");
        return roles;
    }

    @Override
    @Transactional
    public Map<String, Object> login(LoginDTO dto) {
        User user = userMapper.selectOne(
                new LambdaQueryWrapper<User>().eq(User::getUsername, dto.getUsername()));
        if (user == null || (user.getStatus() != null && user.getStatus() == 0))
            throw new BusinessException("用户名或密码错误");
        if (!passwordEncoder.matches(dto.getPassword(), user.getPassword()))
            throw new BusinessException("用户名或密码错误");
        user.setLastLoginTime(LocalDateTime.now());
        user.setLoginCount(user.getLoginCount() != null ? user.getLoginCount() + 1 : 1);
        userMapper.updateById(user);
        log.info("用户登录成功: {}", user.getUsername());
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
    @Transactional
    @CacheEvict(value = {"stats", "ranking"}, allEntries = true)
    public Map<String, Object> register(RegisterDTO dto) {
        if (userMapper.selectCount(new LambdaQueryWrapper<User>().eq(User::getUsername, dto.getUsername())) > 0)
            throw new BusinessException("用户名已存在");
        User user = new User();
        user.setUsername(dto.getUsername());
        user.setPassword(passwordEncoder.encode(dto.getPassword()));
        user.setEmail(dto.getEmail());
        user.setNickname(dto.getNickname() != null ? dto.getNickname() : dto.getUsername());
        userMapper.insert(user);
        userMapper.insertDefaultRole(user.getId());
        log.info("用户注册成功: {}", user.getUsername());
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
    @Transactional
    public void updateProfile(String username, UserUpdateDTO dto) {
        User user = getCurrentUser(username);
        if (dto.getEmail() != null) user.setEmail(dto.getEmail());
        if (dto.getNickname() != null) user.setNickname(dto.getNickname());
        if (dto.getAvatar() != null) user.setAvatar(dto.getAvatar());
        userMapper.updateById(user);
        log.info("用户更新资料: {}", username);
    }

    @Override
    @Transactional
    public void changePassword(String username, PasswordDTO dto) {
        User user = getCurrentUser(username);
        if (!passwordEncoder.matches(dto.getOldPassword(), user.getPassword()))
            throw new BusinessException("原密码错误");
        user.setPassword(passwordEncoder.encode(dto.getNewPassword()));
        userMapper.updateById(user);
        log.info("用户修改密码: {}", username);
    }
}
