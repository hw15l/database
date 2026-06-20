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

    private static final int MAX_PARSE_ROWS = 50000;
    private static final long MAX_FILE_SIZE = 50 * 1024 * 1024;

    @Override
    @Transactional
    public FileEntity uploadFromBytes(byte[] bytes, String originalName, Long userId) throws Exception {
        if (bytes.length > MAX_FILE_SIZE) {
            throw new BusinessException("文件大小不能超过50MB");
        }
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
        return parseFile(file, ext, MAX_PARSE_ROWS);
    }

    private List<List<Object>> parseFile(File file, String ext, int maxRows) throws Exception {
        List<List<Object>> rows = new ArrayList<>();
        if (".csv".equals(ext)) {
            try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null && rows.size() < maxRows) {
                    rows.add(Arrays.asList(line.split(",")));
                }
            }
        } else if (".xlsx".equals(ext) || ".xls".equals(ext)) {
            ExcelReader reader = ExcelUtil.getReader(file);
            List<Map<String, Object>> all = reader.readAll();
            int limit = Math.min(all.size(), maxRows);
            for (int i = 0; i < limit; i++) {
                rows.add(new ArrayList<>(all.get(i).values()));
            }
            reader.close();
        } else {
            try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null && rows.size() < maxRows) {
                    rows.add(Arrays.asList(line.split("\t")));
                }
            }
        }
        if (rows.size() >= maxRows) {
            log.warn("文件行数超过上限({}), 仅解析前{}行: {}", maxRows, maxRows, file.getName());
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
            List<List<Object>> all = parseFile(new File(f.getFilePath()), "." + f.getFileType(), limit);
            List<List<String>> result = new ArrayList<>();
            for (List<Object> row : all) {
                List<String> strRow = new ArrayList<>();
                for (Object obj : row) strRow.add(String.valueOf(obj));
                result.add(strRow);
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
