package com.papervision.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class FileUploadDTO {
    @NotBlank(message = "文件名不能为空")
    private String fileName;
    @NotBlank(message = "文件数据不能为空")
    private String fileData;
}
