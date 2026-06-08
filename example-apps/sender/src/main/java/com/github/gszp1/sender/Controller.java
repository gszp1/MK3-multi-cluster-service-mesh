package com.github.gszp1.sender;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import java.net.InetAddress;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@RestController
@RequestMapping("/api")
public class Controller {

    private final String responderUrl;

    public Controller(@Value("${responder.url}") String responderUrl) {
        this.responderUrl = responderUrl;
    }

    @GetMapping("")
    public String passMessageToResponder(
            @RequestParam(required = false) String content,
            HttpServletRequest request
    ) {
        try {
            String localIp = InetAddress.getLocalHost().getHostAddress();
            String receivedAt = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
            String remoteAddr = request.getRemoteAddr();

            StringBuilder message = new StringBuilder();
            message.append("Sender received this message.").append("\n");
            message.append("Sender IP: ").append(localIp).append("\n");
            message.append("Time of receiving: ").append(receivedAt).append("\n");
            message.append("Request from: ").append(remoteAddr).append("\n");
            if (content != null && !content.isEmpty()) {
                message.append("Content: ").append(content).append("\n");
            }

            RestTemplate restTemplate = new RestTemplate();
            return restTemplate.postForObject(responderUrl, message.toString(), String.class);
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }
}
