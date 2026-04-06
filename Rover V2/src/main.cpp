#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Wire.h>


// ===== WIFI =====
const char *ssid = "Nothing Phone (2a)";
const char *password = "naveenvel";

// ===== EMQX CLOUD =====
const char *mqtt_server = "kc7f274c.ala.us-east-1.emqxsl.com";
const int mqtt_port = 8883;
const char *mqtt_username = "vjnaveen2005";
const char *mqtt_password = "Naveenvel@31";
const char *topic_cmd = "rover/cmd";
const char *topic_data = "rover/data";
const char *topic_status = "rover/status"; // online/offline heartbeat

// EMQX root CA - paste your ca.crt content here
const char *ca_cert = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
MrY=
-----END CERTIFICATE-----
)EOF";

// ===== MOTOR PINS - Driver A (Left) =====
#define PWMA 13
#define AIN1 12
#define AIN2 14
#define PWMB 27
#define BIN1 26
#define BIN2 25

// ===== MOTOR PINS - Driver B (Right) =====
#define PWMC 33
#define CIN1 32
#define CIN2 15 // FC-03 Front-Right CIN2 pin

#define PWMD 18
#define DIN1 19
#define DIN2 23

// ===== SENSORS =====
#define TRIG_PIN 5
#define ECHO_PIN 4
#define ENC_PIN 35 // FC-03 Optical Encoder D0 pin

volatile unsigned long encPulseCount = 0;
volatile unsigned long totalPulses = 0;

void IRAM_ATTR encISR() {
  encPulseCount++;
  totalPulses++;
}

// ===== OLED =====
#define OLED_SDA 21
#define OLED_SCL 22
Adafruit_SH1106G display(128, 64, &Wire, -1);

// ===== PWM CHANNELS =====
#define CH_FL 0
#define CH_RL 1
#define CH_FR 2
#define CH_RR 3

// ===== GLOBALS =====
float distanceCm = 0;
int motorSpeed = 50; // User-requested default speed (50-255 range)
String currentCmd = "stop";
const float SPEED_CM_S_MAX =
    220.0; // Calibrated: rover moved 11x too far at 20.0, so 20*11=220

WiFiClientSecure secureClient;
PubSubClient mqttClient(secureClient);

// ===== MOTOR HELPERS =====
void setMotor(int ch, int in1, int in2, int spd, bool fwd) {
  digitalWrite(in1, fwd ? HIGH : LOW);
  digitalWrite(in2, fwd ? LOW : HIGH);
  ledcWrite(ch, spd);
}

void stopAll() {
  ledcWrite(CH_FL, 0);
  ledcWrite(CH_RL, 0);
  ledcWrite(CH_FR, 0);
  ledcWrite(CH_RR, 0);
}

void moveForward(int s) {
  setMotor(CH_FL, AIN1, AIN2, s, true);
  setMotor(CH_RL, BIN1, BIN2, s, true);
  setMotor(CH_FR, CIN1, CIN2, s, true);
  setMotor(CH_RR, DIN1, DIN2, s, true);
}

void moveBackward(int s) {
  setMotor(CH_FL, AIN1, AIN2, s, false);
  setMotor(CH_RL, BIN1, BIN2, s, false);
  setMotor(CH_FR, CIN1, CIN2, s, false);
  setMotor(CH_RR, DIN1, DIN2, s, false);
}

void turnLeft(int s) {
  setMotor(CH_FL, AIN1, AIN2, s, false);
  setMotor(CH_RL, BIN1, BIN2, s, false);
  setMotor(CH_FR, CIN1, CIN2, s, true);
  setMotor(CH_RR, DIN1, DIN2, s, true);
}

void turnRight(int s) {
  setMotor(CH_FL, AIN1, AIN2, s, true);
  setMotor(CH_RL, BIN1, BIN2, s, true);
  setMotor(CH_FR, CIN1, CIN2, s, false);
  setMotor(CH_RR, DIN1, DIN2, s, false);
}

// ===== ULTRASONIC =====
float getDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long dur = pulseIn(ECHO_PIN, HIGH, 30000);
  return dur * 0.034f / 2.0f;
}

// ===== OLED =====
void updateOLED(float obs) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);
  display.setCursor(0, 0);
  display.println("=== ROVER ===");
  display.print("Cmd: ");
  display.println(currentCmd);
  display.print("Dist: ");
  display.print(distanceCm, 1);
  display.println("cm");
  display.print("Obs:  ");
  display.print(obs, 1);
  display.println("cm");
  display.print("Spd:  ");
  display.println(motorSpeed);
  display.display();
}

// ===== MQTT CALLBACK =====
void mqttCallback(char *topic, byte *payload, unsigned int len) {
  (void)topic;
  String msg = "";
  for (unsigned int i = 0; i < len; i++) {
    msg += (char)payload[i];
  }
  msg.trim();
  currentCmd = msg;
  Serial.println("CMD: " + msg);

  if (msg == "forward")
    moveForward(motorSpeed);
  else if (msg == "backward")
    moveBackward(motorSpeed);
  else if (msg == "left")
    turnLeft(motorSpeed);
  else if (msg == "right")
    turnRight(motorSpeed);
  else if (msg == "stop")
    stopAll();
  else if (msg.startsWith("speed:")) {
    motorSpeed = constrain(msg.substring(6).toInt(), 50, 255);
    Serial.println("Speed set to: " + String(motorSpeed));
  } else if (msg.startsWith("move:")) {
    float targetCm = msg.substring(5).toFloat();
    
    // ALGEBRAIC CALIBRATION BASED ON USER DATA:
    // 20 pulses -> 14 cm
    // 40 pulses -> 25 cm
    // Distance = (cwPerPulse * pulses) + drift
    // 11cm difference = 20 pulses --> cmPerPulse = 0.55 cm
    // Drift (sliding after stop) = 3.0 cm
    float cmPerPulse = 0.55; 
    float driftCm = 3.0;
    
    float adjustedTarget = targetCm - driftCm;
    if (adjustedTarget <= 0) adjustedTarget = targetCm / 2.0; // prevent 0 or negative pulses
    
    unsigned long targetPulses = (unsigned long)(adjustedTarget / cmPerPulse);
    if (targetPulses == 0) targetPulses = 1; // Minimum 1 pulse

    // Timeout safety fallback (assume 10cm/s minimum speed)
    float estimatedSpeed = (motorSpeed / 255.0f) * SPEED_CM_S_MAX;
    if (estimatedSpeed <= 0) estimatedSpeed = 10.0f;
    long timeoutMs = (long)((targetCm / estimatedSpeed) * 1000.0f) + 3000; 
    
    encPulseCount = 0;
    unsigned long startTime = millis();

    Serial.println("Moving " + String(targetCm) + "cm, target pulses: " + 
                   String(targetPulses) + ", timeout: " + String(timeoutMs) + "ms");
    moveForward(motorSpeed);

    unsigned long lastPrintCount = 0;
    while (encPulseCount < targetPulses && (millis() - startTime < (unsigned long)timeoutMs)) {
      float obs = getDistance();
      if (obs > 0 && obs < 15) {
        stopAll();
        mqttClient.publish(topic_data, "obstacle_detected");
        return;
      }
      
      // Print pulse count every time it changes so we can see if the sensor works
      if (encPulseCount != lastPrintCount) {
        Serial.println("Pulses: " + String(encPulseCount) + " / " + String(targetPulses));
        lastPrintCount = encPulseCount;
      }

      delay(10);
      mqttClient.loop(); // keep alive
    }
    
    if (encPulseCount < targetPulses) {
      Serial.println("WARNING: Stopped due to safety TIMEOUT! The sensor did NOT send enough pulses.");
    } else {
      Serial.println("SUCCESS: Target distance reached properly via encoder.");
    }
    
    stopAll();
    mqttClient.publish(topic_data, "movement_done");
  }
}


// ===== WIFI WATCHDOG =====
void checkWiFiWatchdog() {
  if (WiFi.status() != WL_CONNECTED) {
    stopAll(); // Securely stop motors
    Serial.print("WiFi dropped. Reconnecting...");
    WiFi.disconnect();
    WiFi.begin(ssid, password);
    unsigned long startAttemptTime = millis();
    while (WiFi.status() != WL_CONNECTED &&
           millis() - startAttemptTime < 10000) {
      delay(500);
      Serial.print(".");
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWiFi reconnected.");
    } else {
      Serial.println("\nWiFi reconnect failed.");
    }
  }
}

// ===== MQTT WATCHDOG =====
void reconnectMQTT() {
  stopAll(); // Auto stop motors while MQTT is reconnecting
  while (!mqttClient.connected()) {
    checkWiFiWatchdog();
    if (WiFi.status() != WL_CONNECTED) {
      delay(3000);
      continue;
    }

    Serial.print("Connecting EMQX...");
    String id = "ESP32Rover-" + String(random(0xffff), HEX);

    // LWT built into connect(): broker auto-publishes "offline" (retained) if
    // ESP32 drops
    if (mqttClient.connect(id.c_str(), mqtt_username, mqtt_password,
                           topic_status, // will topic
                           1,            // will QoS (at least once)
                           true,         // will retain
                           "offline"     // will message
                           )) {
      Serial.println("connected");
      mqttClient.subscribe(topic_cmd);
      // Announce rover is online (retained — new subscribers get it
      // immediately)
      mqttClient.publish(topic_status, "online", true);
    } else {
      Serial.print("failed rc=");
      Serial.println(mqttClient.state());
      delay(3000);
    }
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);

  // Motor direction pins
  int dirPins[] = {AIN1, AIN2, BIN1, BIN2, CIN1, CIN2, DIN1, DIN2};
  for (int p : dirPins) {
    pinMode(p, OUTPUT);
  }

  // PWM
  ledcSetup(CH_FL, 20000, 8);
  ledcAttachPin(PWMA, CH_FL);
  ledcSetup(CH_RL, 20000, 8);
  ledcAttachPin(PWMB, CH_RL);
  ledcSetup(CH_FR, 20000, 8);
  ledcAttachPin(PWMC, CH_FR);
  ledcSetup(CH_RR, 20000, 8);
  ledcAttachPin(PWMD, CH_RR);

  // Sensors
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  
  // Optical Encoder FC-03
  pinMode(ENC_PIN, INPUT);
  attachInterrupt(digitalPinToInterrupt(ENC_PIN), encISR, RISING);

  // OLED
  Wire.begin(OLED_SDA, OLED_SCL);
  display.begin(0x3C, true);
  display.clearDisplay();
  display.display();

  // WiFi
  WiFi.begin(ssid, password);
  WiFi.setSleep(false);
  WiFi.setTxPower(WIFI_POWER_19_5dBm);
  Serial.print("WiFi connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi OK: " + WiFi.localIP().toString());

  // TLS + MQTT
  secureClient.setCACert(ca_cert);
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setKeepAlive(60);

  stopAll();
}

// ===== LOOP =====
unsigned long lastPub = 0;

void loop() {
  checkWiFiWatchdog();
  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();

  float obs = getDistance();

  // Auto obstacle stop
  if (obs > 0 && obs < 15 && currentCmd == "forward") {
    stopAll();
    currentCmd = "stop";
    mqttClient.publish(topic_data, "obstacle_detected");
  }

  // Publish every 500ms
  if (millis() - lastPub > 500) {
    float cmPerPulse = 0.55; 
    float currentDist = totalPulses * cmPerPulse;
    String data = "dist:" + String(currentDist, 1) + ",obs:" + String(obs, 1);
    mqttClient.publish(topic_data, data.c_str());
    lastPub = millis();
  }

  updateOLED(obs);
}