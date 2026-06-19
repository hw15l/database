package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_task")
public class Task {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private String taskType;
    private Long chartId;
    private Long formulaId;
    private Long fileId;
    private String taskParams;
    private String resultPath;
    private String resultPdf;
    private String status;
    private String errorMsg;
    private Long totalTasks;
    private LocalDateTime startTime;
    private LocalDateTime finishTime;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;
}
