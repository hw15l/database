package com.papervision.service;

import com.papervision.entity.FileEntity;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;

/**
 * 文件服务接口 — 文件上传、预览、删除
 */
public interface FileService {

    /** 从Base64字节数组上传文件(含文件类型校验和魔数验证) */
    FileEntity uploadFromBytes(byte[] bytes, String fileName, Long userId) throws Exception;

    /** 从MultipartFile上传文件 */
    FileEntity upload(MultipartFile file, Long userId) throws Exception;

    /** 查询用户的文件列表(排除已删除) */
    List<FileEntity> listByUser(Long userId);

    /** 预览文件数据(返回前limit行) */
    List<List<String>> previewData(Long fileId, Long userId, int limit);

    /** 软删除文件(设status=0, 同时物理删除文件) */
    void delete(Long fileId, Long userId);

    void ensureDataItems(Long fileId);
}
