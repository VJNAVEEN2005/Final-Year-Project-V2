#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

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
const char *topic_status = "rover/status";

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

// ===== PINS (L293D) =====
#define IN1 25    // Motor A Dir 1
#define IN2 26    // Motor A Dir 2
#define EN1 27    // Motor A Speed (PWM)
#define IN3 14    // Motor B Dir 1
#define IN4 12    // Motor B Dir 2
#define EN2 13    // Motor B Speed (PWM)

#define TRIG_PIN 5
#define ECHO_PIN 18
#define ENC_PIN 19

#define SDA_PIN 21
#define SCL_PIN 22

#define LED_BUILTIN 2
#define CM_PER_PULSE 0.5

// ===== MPU6050 =====
Adafruit_MPU6050 mpu;
sensors_event_t a, g, temp;
float gyroZ_offset = 0;

// ===== PID CONTROLLER =====
struct PID {
  float kp, ki, kd;
  float integral;
  float prevError;
};

PID turnPID = {2.2, 0.0, 0.8, 0, 0};
PID movePID = {1.8, 0.0, 0.5, 0, 0};

float computePID(PID &pid, float error, float dt) {
  pid.integral += error * dt;
  
  float maxIntegral = 100.0;
  if (pid.integral > maxIntegral) pid.integral = maxIntegral;
  if (pid.integral < -maxIntegral) pid.integral = -maxIntegral;
  
  float derivative = (error - pid.prevError) / dt;
  pid.prevError = error;
  return pid.kp * error + pid.ki * pid.integral + pid.kd * derivative;
}

void calibrateMPU6050() {
  Serial.println("Calibrating MPU6050... Keep rover still!");
  
  const int samples = 300;
  float sumZ = 0;
  
  for (int i = 0; i < samples; i++) {
    mpu.getEvent(&a, &g, &temp);
    sumZ += g.gyro.z;
    delay(5);
  }
  
  gyroZ_offset = sumZ / samples;
  
  Serial.print("Calibration done! Z offset: ");
  Serial.println(gyroZ_offset, 6);
}

// ===== STATE MACHINE =====
enum RobotState {
  IDLE,
  TURNING,
  MOVING
};

RobotState state = IDLE;
float targetYaw = 0;
float moveTargetYaw = 0;

// ===== GLOBALS =====
volatile unsigned long encPulseCount = 0;
volatile unsigned long totalPulses = 0;
volatile unsigned long targetPulses = 0;
String currentCmd = "stop";
int targetSpeed = 255; 

float obstacleDist = 999;
unsigned long lastPub = 0;
unsigned long lastHB = 0;
unsigned long lastStatusPub = 0;

float lastKnownYaw = 0;
bool publishDone = false;
int currentSpeed = 0;

// Telemetry
unsigned long lastTotalPulses = 0;
float linearSpeed = 0;
float currentRPM = 0;
float currentYaw = 0;
unsigned long lastCalcTime = 0;

// Complementary Filter
float accelYaw = 0;
float alpha = 0.98;

WiFiClientSecure secureClient;
PubSubClient mqttClient(secureClient);

// ===== ENCODER ISR =====
void IRAM_ATTR encISR() {
  encPulseCount++;
  totalPulses++;
}

// ===== ULTRASONIC =====
float getDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 8000);
  if (duration == 0) return 999;
  return duration * 0.034 / 2;
}

// ===== MOTOR CONTROL =====
void setSpeed(int target) {
  int step = 5;
  if (currentSpeed < target) currentSpeed += step;
  else if (currentSpeed > target) currentSpeed -= step;
  ledcWrite(0, currentSpeed);
  ledcWrite(1, currentSpeed);
}

void setSpeedRaw(int s) {
  ledcWrite(0, s);
  ledcWrite(1, s);
}

void stopAll() {
  digitalWrite(IN1, LOW); digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW); digitalWrite(IN4, LOW);
  setSpeed(0);
  currentCmd = "stop";
  state = IDLE;
  lastKnownYaw = currentYaw;
  publishDone = true;
}

void moveMotors(int s1, int s2, int s3, int s4) {
  digitalWrite(IN1, s1); digitalWrite(IN2, s2);
  digitalWrite(IN3, s3); digitalWrite(IN4, s4);
  setSpeed(targetSpeed);
}

// ===== CLEAN IMU SYSTEM (SINGLE SOURCE OF TRUTH) =====
void updateIMU() {
  static unsigned long lastTime = micros();
  unsigned long now = micros();
  
  mpu.getEvent(&a, &g, &temp);
  
  float dt = (now - lastTime) / 1000000.0;
  lastTime = now;
  
  if (dt <= 0 || dt > 0.05) return;
  
  float gyroRate = (g.gyro.z - gyroZ_offset) * 57.2958;
  currentYaw += gyroRate * dt;
  
  if (currentYaw > 180) currentYaw -= 360;
  if (currentYaw < -180) currentYaw += 360;
}

// ===== PERFECT TURN CONTROLLER =====
void startTurn(float angle) {
  targetYaw = currentYaw + angle;
  
  if (targetYaw > 180) targetYaw -= 360;
  if (targetYaw < -180) targetYaw += 360;
  
  state = TURNING;
  currentCmd = angle > 0 ? "right90" : "left90";
}

void handleTurning() {
  static unsigned long lastTime = micros();
  unsigned long now = micros();
  float dt = (now - lastTime) / 1000000.0;
  lastTime = now;

  float error = targetYaw - currentYaw;
  
  if (error > 180) error -= 360;
  if (error < -180) error += 360;
  
  if (abs(error) < 1.0) {
    stopAll();
    publishDone = true;
    turnPID.integral = 0;
    return;
  }
  
  float output = computePID(turnPID, error, dt);
  int speed = constrain(abs(output), 80, targetSpeed);
  
  if (error > 0) {
    moveMotors(LOW, HIGH, LOW, HIGH);
  } else {
    moveMotors(HIGH, LOW, HIGH, LOW);
  }
  
  setSpeed(speed);
}

// ===== STRAIGHT MOVEMENT (DRIFT-FREE) =====
void startForward() {
  currentYaw = lastKnownYaw;
  moveTargetYaw = currentYaw;
  state = MOVING;
  moveMotors(LOW, HIGH, HIGH, LOW);
}

void handleForward() {
  // Obstacle check - stop at 5cm
  if (getDistance() < 5) {
    Serial.println("OBSTACLE DETECTED");
    stopAll();
    targetPulses = 0;
    publishDone = true;
    return;
  }
  
  // Check if using encoder-based movement
  if (targetPulses > 0) {
    if (encPulseCount >= targetPulses) {
      stopAll();
      targetPulses = 0;
      publishDone = true;
      return;
    }
  }
  
  // Drift correction - PID for straight line
  float error = moveTargetYaw - currentYaw;
  if (error > 180) error -= 360;
  if (error < -180) error += 360;

  static unsigned long lastTimeF = micros();
  unsigned long nowF = micros();
  float dt = (nowF - lastTimeF) / 1000000.0;
  lastTimeF = nowF;

  float correction = computePID(movePID, error, dt);
  
  int left = constrain(targetSpeed - correction, 100, 255);
  int right = constrain(targetSpeed + correction, 100, 255);
  
  ledcWrite(0, left);
  ledcWrite(1, right);
}

// ===== MQTT CALLBACK =====
void mqttCallback(char *topic, byte *payload, unsigned int len) {
  String msg = "";
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  msg.trim();
  
  Serial.println("RX: " + msg);
  
  if (msg == "forward") {
    currentCmd = "forward";
    startForward();
  }
  else if (msg == "backward") {
    currentCmd = "backward";
    moveMotors(HIGH, LOW, LOW, HIGH);
  }
  else if (msg == "left") {
    currentCmd = "left";
    moveMotors(HIGH, LOW, HIGH, LOW);
  }
  else if (msg == "right") {
    currentCmd = "right";
    moveMotors(LOW, HIGH, LOW, HIGH);
  }
  else if (msg == "stop") {
    stopAll();
  }
  else if (msg == "left90") {
    startTurn(-90);
  }
  else if (msg == "right90") {
    startTurn(90);
  }
  else if (msg.startsWith("move:")) {
    // Custom distance move - non-blocking using state machine
    float d = msg.substring(5).toFloat();
    if (d > 0) {
      encPulseCount = 0;
      // 20 slots = 40 edges per rev, ~10cm wheel = 0.25 cm per pulse
      targetPulses = (unsigned long)(d / CM_PER_PULSE);
      state = MOVING;
      moveMotors(LOW, HIGH, HIGH, LOW);
      // Store target distance for telemetry
      currentCmd = "move";
    }
  }
  else if (msg.startsWith("speed:")) {
    targetSpeed = constrain(msg.substring(6).toInt(), 0, 255);
    if (currentCmd != "stop") setSpeed(targetSpeed);
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  
  // Motor pins
  int motorPins[] = {IN1, IN2, IN3, IN4, EN1, EN2};
  for (int p : motorPins) {
    pinMode(p, OUTPUT);
    digitalWrite(p, LOW);
  }
  
  pinMode(TRIG_PIN, OUTPUT); pinMode(ECHO_PIN, INPUT);
  
  ledcSetup(0, 5000, 8); ledcSetup(1, 5000, 8);
  ledcAttachPin(EN1, 0); ledcAttachPin(EN2, 1);

  pinMode(ENC_PIN, INPUT);
  pinMode(LED_BUILTIN, OUTPUT);
  attachInterrupt(digitalPinToInterrupt(ENC_PIN), encISR, RISING);

  // MPU6050
  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  if (mpu.begin()) {
    Serial.println("MPU6050 connected!");
    mpu.setFilterBandwidth(MPU6050_BAND_5_HZ);
    mpu.setGyroRange(MPU6050_RANGE_250_DEG);
    calibrateMPU6050();
  } else {
    Serial.println("MPU6050 not found!");
  }

  // WiFi
  IPAddress dns(8, 8, 8, 8); 
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE, dns);
  WiFi.begin(ssid, password);
  WiFi.setSleep(false);
  
  secureClient.setCACert(ca_cert);
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  
  stopAll();
  
  // MQTT connection
  String id = "Rover-" + String(random(0xffff), HEX);
  if(mqttClient.connect(id.c_str(), mqtt_username, mqtt_password)) {
    mqttClient.subscribe(topic_cmd);
    mqttClient.publish(topic_status, "online");
  }
}

// ===== LOOP =====
void loop() {
  static unsigned long lastLedToggle = 0;
  static bool ledState = false;
  static unsigned long lastWifiCheck = 0;
  
  // WiFi status
  byte wifiStatus = WiFi.status();
  
  if (millis() - lastWifiCheck >= 2000) {
    Serial.print("=== WiFi Status: ");
    if (wifiStatus == 0) Serial.println("WL_IDLE_STATUS");
    else if (wifiStatus == 1) Serial.println("WL_NO_SSID_AVAIL");
    else if (wifiStatus == 2) Serial.println("WL_SCAN_COMPLETED");
    else if (wifiStatus == 3) Serial.println("WL_CONNECTED");
    else if (wifiStatus == 4) Serial.println("WL_CONNECT_FAILED");
    else if (wifiStatus == 5) Serial.println("WL_CONNECTION_LOST");
    else if (wifiStatus == 6) Serial.println("WL_DISCONNECTED");
    else Serial.println(wifiStatus);
    
    if (wifiStatus == 3) {
      Serial.print("IP: ");
      Serial.println(WiFi.localIP());
      Serial.print("RSSI: ");
      Serial.println(WiFi.RSSI());
    }
    lastWifiCheck = millis();
  }
  
  // LED blink when disconnected
  if (wifiStatus != WL_CONNECTED) {
    if (millis() - lastLedToggle >= 500) {
      ledState = !ledState;
      digitalWrite(LED_BUILTIN, ledState ? HIGH : LOW);
      lastLedToggle = millis();
    }
  } else {
    digitalWrite(LED_BUILTIN, LOW);
  }

  // Reconnect WiFi
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastHB > 5000) {
      WiFi.reconnect();
      lastHB = millis();
    }
  }
  
  // Reconnect MQTT separately
  if (!mqttClient.connected()) {
    if (millis() - lastHB > 5000) {
      String id = "Rover-" + String(random(0xffff), HEX);
      if(mqttClient.connect(id.c_str(), mqtt_username, mqtt_password)) {
        mqttClient.subscribe(topic_cmd);
        mqttClient.publish(topic_status, "online");
      }
      lastHB = millis();
    }
  }
  mqttClient.loop();

  if (publishDone && mqttClient.connected()) {
    if (obstacleDist < 20) {
      mqttClient.publish(topic_data, "obstacle_detected");
    } else if (targetPulses == 0 && state == IDLE) {
      mqttClient.publish(topic_data, "done");
    }
    publishDone = false;
  }

  // Obstacle sensor
  obstacleDist = getDistance();
  
  // ===== CLEAN ARCHITECTURE: SINGLE SOURCE OF TRUTH =====
  updateIMU();
  
  // State-based motion control
  switch (state) {
    case TURNING:
      handleTurning();
      break;
    case MOVING:
      handleForward();
      break;
    case IDLE:
      setSpeed(0);
      break;
  }
   
  // Telemetry
  if (millis() - lastPub > 500) {
    unsigned long now = millis();
    unsigned long pulseDelta = totalPulses - lastTotalPulses;
    float timeDeltaSec = (now - lastCalcTime) / 1000.0;
    
    if (timeDeltaSec > 0) {
      linearSpeed = (pulseDelta * CM_PER_PULSE) / timeDeltaSec;
      currentRPM = (pulseDelta / 20.0) * (60.0 / timeDeltaSec);
    }
    
    lastTotalPulses = totalPulses;
    lastCalcTime = now;

    String data = "dist:" + String(totalPulses * CM_PER_PULSE, 1) + 
                  ",obs:" + String(obstacleDist, 1) + 
                  ",spd:" + String(linearSpeed, 1) + 
                  ",rpm:" + String(currentRPM, 0) +
                  ",yaw:" + String(currentYaw, 1);
                   
    mqttClient.publish(topic_data, data.c_str());
    lastPub = millis();
  }
  
  if (millis() - lastStatusPub > 5000) {
    mqttClient.publish(topic_status, "online");
    lastStatusPub = millis();
  }
}