package com.papervision.common;

import lombok.Data;
import java.io.Serializable;

/**
 * 统一API响应封装类
 * <p>所有Controller接口统一返回此对象, 保证前后端数据格式一致</p>
 * <ul>
 *   <li>code: HTTP状态码(200成功, 400业务错误, 422校验失败, 500系统错误)</li>
 *   <li>message: 提示信息</li>
 *   <li>data: 业务数据(泛型)</li>
 *   <li>timestamp: 响应时间戳(毫秒)</li>
 * </ul>
 *
 * @param <T> 业务数据类型
 */
@Data
public class Result<T> implements Serializable {
    private int code;
    private String message;
    private T data;
    private long timestamp;

    private Result() {
        this.timestamp = System.currentTimeMillis();
    }

    public static <T> Result<T> ok() {
        Result<T> r = new Result<>();
        r.code = 200;
        r.message = "操作成功";
        return r;
    }

    public static <T> Result<T> ok(T data) {
        Result<T> r = new Result<>();
        r.code = 200;
        r.message = "操作成功";
        r.data = data;
        return r;
    }

    public static <T> Result<T> ok(T data, String message) {
        Result<T> r = new Result<>();
        r.code = 200;
        r.message = message;
        r.data = data;
        return r;
    }

    public static <T> Result<T> fail(String message) {
        Result<T> r = new Result<>();
        r.code = 400;
        r.message = message;
        return r;
    }

    public static <T> Result<T> fail(int code, String message) {
        Result<T> r = new Result<>();
        r.code = code;
        r.message = message;
        return r;
    }
}
