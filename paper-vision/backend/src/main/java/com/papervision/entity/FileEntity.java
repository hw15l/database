package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@TableName("t_file")
public class FileEntity {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private String fileName;
    private String filePath;
    private String fileType;
    private Long fileSize;
    private Integer totalRows;
    private Integer totalCols;
    private Integer status;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;

    private String fileHash;
    private String metadata;
    private String dataProfile;
    private String uploadIp;
    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private BigDecimal fileSizeMb;
    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private Integer cellCount;
}
