package com.papervision.controller;

import com.papervision.entity.FileEntity;
import com.papervision.service.FileService;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.Base64;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/data")
@RequiredArgsConstructor
public class DataController {
    private final FileService fileService;
    private final UserService userService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @PostMapping("/upload")
    public ResponseEntity<FileEntity> upload(@RequestBody Map<String, Object> req) throws Exception {
        String fileName = (String) req.get("fileName");
        String base64 = (String) req.get("fileData");
        if (fileName == null || base64 == null) throw new RuntimeException("fileName and fileData required");
        byte[] bytes = Base64.getDecoder().decode(base64);
        return ResponseEntity.ok(fileService.uploadFromBytes(bytes, fileName, uid()));
    }

    @GetMapping("/files")
    public ResponseEntity<List<FileEntity>> listFiles() {
        return ResponseEntity.ok(fileService.listByUser(uid()));
    }

    @GetMapping("/preview/{fileId}")
    public ResponseEntity<List<List<String>>> preview(@PathVariable Long fileId,
                                                       @RequestParam(defaultValue = "20") int limit) {
        return ResponseEntity.ok(fileService.previewData(fileId, uid(), limit));
    }

    @DeleteMapping("/{fileId}")
    public ResponseEntity<String> delete(@PathVariable Long fileId) {
        fileService.delete(fileId, uid());
        return ResponseEntity.ok("OK");
    }
}
