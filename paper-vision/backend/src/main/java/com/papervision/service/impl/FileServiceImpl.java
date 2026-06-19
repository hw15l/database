package com.papervision.service.impl;

import cn.hutool.core.io.FileUtil;
import cn.hutool.poi.excel.ExcelReader;
import cn.hutool.poi.excel.ExcelUtil;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.FileEntity;
import com.papervision.mapper.FileMapper;
import com.papervision.service.FileService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class FileServiceImpl implements FileService {
    private final FileMapper fileMapper;
    @Value("${file.upload.path}")
    private String uploadPath;

    @Override
    @Transactional
    public FileEntity uploadFromBytes(byte[] bytes, String originalName, Long userId) throws Exception {
        String ext = originalName.substring(originalName.lastIndexOf(".")).toLowerCase();
        if (!isValidExtension(ext)) throw new BusinessException("不支持的文件类型: " + ext);
        if (!verifyMagicBytes(bytes, ext)) throw new BusinessException("文件内容与扩展名不匹配");
        String storedName = UUID.randomUUID() + ext;
        File dir = new File(uploadPath);
        if (!dir.exists()) dir.mkdirs();
        File dest = new File(uploadPath + storedName);
        java.nio.file.Files.write(dest.toPath(), bytes);

        FileEntity file = new FileEntity();
        file.setUserId(userId); file.setFileName(originalName);
        file.setFilePath(dest.getAbsolutePath()); file.setFileSize((long) bytes.length);
        file.setFileType(ext.replace(".", ""));
        List<List<Object>> rows = parseFile(dest, ext);
        file.setTotalRows(rows.size()); file.setTotalCols(rows.isEmpty() ? 0 : rows.get(0).size());
        fileMapper.insert(file);
        log.info("用户[{}]上传文件: {} ({}KB)", userId, originalName, bytes.length / 1024);
        return file;
    }

    @Override
    @Transactional
    public FileEntity upload(MultipartFile mf, Long userId) throws Exception {
        String originalName = Objects.requireNonNull(mf.getOriginalFilename());
        String ext = originalName.substring(originalName.lastIndexOf(".")).toLowerCase();
        if (!isValidExtension(ext)) throw new BusinessException("不支持的文件类型: " + ext);
        if (!verifyMagicBytes(mf.getBytes(), ext)) throw new BusinessException("文件内容与扩展名不匹配");

        String storedName = UUID.randomUUID() + ext;
        File dir = new File(uploadPath);
        if (!dir.exists()) dir.mkdirs();
        File dest = new File(dir.getAbsoluteFile(), storedName);
        mf.transferTo(dest);

        FileEntity file = new FileEntity();
        file.setUserId(userId); file.setFileName(originalName);
        file.setFilePath(dest.getAbsolutePath()); file.setFileSize(mf.getSize());
        file.setFileType(ext.replace(".", ""));

        List<List<Object>> rows = parseFile(dest, ext);
        file.setTotalRows(rows.size()); file.setTotalCols(rows.isEmpty() ? 0 : rows.get(0).size());
        fileMapper.insert(file);
        log.info("用户[{}]上传文件: {} ({}KB)", userId, originalName, mf.getSize() / 1024);
        return file;
    }

    private boolean isValidExtension(String ext) {
        return ".csv".equals(ext) || ".xlsx".equals(ext) || ".xls".equals(ext) || ".txt".equals(ext);
    }

    private boolean verifyMagicBytes(byte[] bytes, String ext) {
        if (bytes == null || bytes.length < 4) return false;
        int b0 = bytes[0] & 0xFF, b1 = bytes[1] & 0xFF;
        if (".xlsx".equals(ext)) return b0 == 0x50 && b1 == 0x4B;
        if (".xls".equals(ext)) return b0 == 0xD0 && b1 == 0xCF;
        if (".csv".equals(ext) || ".txt".equals(ext)) return b0 < 0x80;
        return true;
    }

    private List<List<Object>> parseFile(File file, String ext) throws Exception {
        List<List<Object>> rows = new ArrayList<>();
        if (".csv".equals(ext)) {
            try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) rows.add(Arrays.asList(line.split(",")));
            }
        } else if (".xlsx".equals(ext) || ".xls".equals(ext)) {
            ExcelReader reader = ExcelUtil.getReader(file);
            for (Map<String, Object> map : reader.readAll()) rows.add(new ArrayList<>(map.values()));
        } else {
            try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) rows.add(Arrays.asList(line.split("\t")));
            }
        }
        return rows;
    }

    @Override
    public List<FileEntity> listByUser(Long userId) {
        return fileMapper.selectList(new LambdaQueryWrapper<FileEntity>()
                .eq(FileEntity::getUserId, userId).eq(FileEntity::getStatus, 1)
                .orderByDesc(FileEntity::getCreateTime));
    }

    @Override
    public List<List<String>> previewData(Long fileId, Long userId, int limit) {
        FileEntity f = fileMapper.selectById(fileId);
        if (f == null) return Collections.emptyList();
        try {
            List<List<Object>> all = parseFile(new File(f.getFilePath()), "." + f.getFileType());
            List<List<String>> result = new ArrayList<>();
            for (int i = 0; i < Math.min(limit, all.size()); i++) {
                List<String> row = new ArrayList<>();
                for (Object obj : all.get(i)) row.add(String.valueOf(obj));
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            log.warn("预览文件失败: fileId={}, {}", fileId, e.getMessage());
            return Collections.emptyList();
        }
    }

    @Override
    @Transactional
    public void delete(Long fileId, Long userId) {
        FileEntity f = fileMapper.selectById(fileId);
        if (f == null) throw new BusinessException(404, "文件不存在");
        if (!f.getUserId().equals(userId)) throw new BusinessException(403, "无权删除");
        f.setStatus(0); fileMapper.updateById(f);
        FileUtil.del(f.getFilePath());
        log.info("用户[{}]删除文件: fileId={}", userId, fileId);
    }
}
