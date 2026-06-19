package com.papervision.common;

import lombok.Getter;

/**
 * 业务异常 — 用于替代裸RuntimeException, 携带HTTP状态码
 * <p>由GlobalExceptionHandler统一捕获, 返回Result&lt;Void&gt;给前端</p>
 */
@Getter
public class BusinessException extends RuntimeException {
    private final int code;

    public BusinessException(String message) {
        super(message);
        this.code = 400;
    }

    public BusinessException(int code, String message) {
        super(message);
        this.code = code;
    }
}
