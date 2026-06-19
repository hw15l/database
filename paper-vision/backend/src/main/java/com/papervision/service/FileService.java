package com.papervision.service;

import com.papervision.entity.FileEntity;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;

public interface FileService {
    FileEntity uploadFromBytes(byte[] bytes, String fileName, Long userId) throws Exception;
    FileEntity upload(MultipartFile file, Long userId) throws Exception;
    List<FileEntity> listByUser(Long userId);
    List<List<String>> previewData(Long fileId, Long userId, int limit);
    void delete(Long fileId, Long userId);
}
