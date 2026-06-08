package com.github.gszp1.responder;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

import java.net.InetAddress;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@RestController
@RequestMapping("/api")
public class Controller {

    @PostMapping("")
    public String respond(
            @RequestParam(required = false) String content,
            HttpServletRequest request
    ) {
        try {
            String localIp = InetAddress.getLocalHost().getHostAddress();
            String receivedAt = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
            String remoteAddr = request.getRemoteAddr();

            StringBuilder message = new StringBuilder();
            if (content != null && !content.isEmpty()) {
                message.append("Content: ").append(content).append("\n");
            }
            message.append("\n");
            message.append("\n");
            message.append("Responder received this message.").append("\n");
            message.append("Responder IP: ").append(localIp).append("\n");
            message.append("Time of receiving: ").append(receivedAt).append("\n");
            message.append("Request from: ").append(remoteAddr).append("\n");
            return message.toString();
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }
}
