package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.dto.FileUploadDTO;
import com.papervision.entity.FileEntity;
import com.papervision.entity.User;
import com.papervision.mapper.FileMapper;
import com.papervision.service.DatabaseService;
import com.papervision.service.FileService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.Base64;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/data")
@RequiredArgsConstructor
public class DataController {
    private final FileService fileService;
    private final UserService userService;
    private final DatabaseService databaseService;
    private final FileMapper fileMapper;
    private Long uid() {
        User u = userService.getCurrentUser(SecurityContextHolder.getContext().getAuthentication().getName());
        if (u == null) throw new BusinessException(401, "用户未登录或不存在");
        return u.getId();
    }

    @PostMapping("/upload")
    public Result<FileEntity> upload(@Valid @RequestBody FileUploadDTO dto) throws Exception {
        byte[] bytes = Base64.getDecoder().decode(dto.getFileData());
        return Result.ok(fileService.uploadFromBytes(bytes, dto.getFileName(), uid()));
    }

    @GetMapping("/files")
    public Result<List<FileEntity>> listFiles() {
        return Result.ok(fileService.listByUser(uid()));
    }

    @GetMapping("/preview/{fileId}")
    public Result<List<List<String>>> preview(@PathVariable Long fileId,
                                               @RequestParam(defaultValue = "20") int limit) {
        return Result.ok(fileService.previewData(fileId, uid(), limit));
    }

    @DeleteMapping("/{fileId}")
    public Result<Void> delete(@PathVariable Long fileId) {
        fileService.delete(fileId, uid());
        return Result.ok();
    }

    /** 数据质量审计 — [DB] sp_data_quality_audit: 逐列分析 + 质量评分 + 回写data_profile */
    @PostMapping("/{fileId}/audit")
    public Result<Map<String, Object>> auditQuality(@PathVariable Long fileId) {
        FileEntity f = fileMapper.selectById(fileId);
        if (f == null) throw new BusinessException(404, "文件不存在");
        if (!f.getUserId().equals(uid())) throw new BusinessException(403, "无权操作该文件");
        fileService.ensureDataItems(fileId);
        databaseService.runDataQualityAudit(fileId);
        return Result.ok(databaseService.getDataQualityDashboard(fileId));
    }
}
