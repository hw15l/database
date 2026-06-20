package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.Task;
import com.papervision.mapper.DatabaseMapper;
import com.papervision.mapper.TaskMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class RenderHelper {
    private final TaskMapper taskMapper;
    private final DatabaseMapper databaseMapper;
    private final RestTemplate restTemplate;

    public Task executeRenderTask(Long userId, Task task, String pythonUrl,
                                   Map<String, Object> requestBody) {
        databaseMapper.callQuotaCheck(userId, "ENFORCE");
        taskMapper.insert(task);
        databaseMapper.callTaskStateTransition(task.getId(), "PROCESSING", null);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);
            log.info("调用Python渲染服务: url={}, taskId={}", pythonUrl, task.getId());

            ResponseEntity<Map> resp = restTemplate.postForEntity(pythonUrl, entity, Map.class);

            if (resp.getBody() != null && "success".equals(resp.getBody().get("status"))) {
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));
                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
                log.info("渲染任务[{}]成功: type={}", task.getId(), task.getTaskType());
            } else {
                String errMsg = resp.getBody() != null ? String.valueOf(resp.getBody().get("message")) : "未知错误";
                throw new BusinessException("Python服务渲染失败: " + errMsg);
            }
        } catch (Exception e) {
            log.warn("渲染任务[{}]失败: type={}, userId={}, error={}",
                    task.getId(), task.getTaskType(), userId, e.getMessage());
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        return taskMapper.selectById(task.getId());
    }
}
