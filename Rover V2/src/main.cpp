#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

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

// ===== PINS (L298N) =====
#define ENA 14 
#define IN1 26
#define IN2 27
#define IN3 25
#define IN4 32
#define ENB 33 

#define TRIG_PIN 18
#define ECHO_PIN 34
#define ENC_PIN 35

// ===== GLOBALS =====
volatile unsigned long encPulseCount = 0;
volatile unsigned long totalPulses = 0;
String currentCmd = "stop";
int targetSpeed = 220; 
float obstacleDist = 999;
unsigned long lastPub = 0;
unsigned long lastHB = 0;

// Telemetry Logic
unsigned long lastTotalPulses = 0;
float linearSpeed = 0;
float currentRPM = 0;
unsigned long lastCalcTime = 0;

WiFiClientSecure secureClient;
PubSubClient mqttClient(secureClient);

void IRAM_ATTR encISR() {
  encPulseCount++;
  totalPulses++;
}

float getDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 15000);
  if (duration == 0) return 999;
  return duration * 0.034 / 2;
}

void setSpeed(int s) {
  ledcWrite(0, s);
  ledcWrite(1, s);
}

void stopAll() {
  digitalWrite(IN1, LOW); digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW); digitalWrite(IN4, LOW);
  setSpeed(0);
  currentCmd = "stop";
}

void moveMotors(int s1, int s2, int s3, int s4) {
  digitalWrite(IN1, s1); digitalWrite(IN2, s2);
  digitalWrite(IN3, s3); digitalWrite(IN4, s4);
  setSpeed(targetSpeed);
}

// Precise Encoder Turn
void turnPulse(bool isRight) {
  encPulseCount = 0;
  const int target = 6; // 90 deg calibration
  
  if (isRight) moveMotors(LOW, HIGH, HIGH, LOW); 
  else moveMotors(HIGH, LOW, LOW, HIGH); 
  
  unsigned long startT = millis();
  while (encPulseCount < target && (millis() - startT < 3000)) {
    mqttClient.loop();
    delay(5);
  }
  stopAll();
  mqttClient.publish(topic_data, "done");
}

void moveDistance(float cm) {
  encPulseCount = 0;
  unsigned long targetPulses = (unsigned long)(cm / 1.65);
  
  Serial.print("Moving custom distance: "); Serial.print(cm); Serial.println(" cm");
  moveMotors(LOW, HIGH, LOW, HIGH); // Forward
  
  unsigned long startT = millis();
  unsigned long timeout = (unsigned long)(cm * 250) + 3000; // Time buffer

  while (encPulseCount < targetPulses && (millis() - startT < timeout)) {
    mqttClient.loop();
    // Safety check
    if (getDistance() < 15) {
       Serial.println("MOVE STOPPED: Obstacle");
       break; 
    }
    delay(5);
  }
  stopAll();
  mqttClient.publish(topic_data, "done");
}

void mqttCallback(char *topic, byte *payload, unsigned int len) {
  String msg = "";
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  msg.trim();
  
  Serial.println("RX: " + msg);

  if (msg == "forward") {
    currentCmd = "forward";
    moveMotors(LOW, HIGH, LOW, HIGH);
  }
  else if (msg == "backward") {
    currentCmd = "backward";
    moveMotors(HIGH, LOW, HIGH, LOW);
  }
  else if (msg == "left") moveMotors(HIGH, LOW, LOW, HIGH);
  else if (msg == "right") moveMotors(LOW, HIGH, HIGH, LOW);
  else if (msg == "stop") stopAll();
  else if (msg == "left90") turnPulse(false);
  else if (msg == "right90") turnPulse(true);
  else if (msg.startsWith("move:")) {
    float d = msg.substring(5).toFloat();
    if (d > 0) moveDistance(d);
  }
  else if (msg.startsWith("speed:")) {
    targetSpeed = msg.substring(6).toInt();
    if (currentCmd != "stop") setSpeed(targetSpeed);
  }
}

void setup() {
  Serial.begin(115200);
  
  pinMode(IN1, OUTPUT); pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT); pinMode(IN4, OUTPUT);
  pinMode(TRIG_PIN, OUTPUT); pinMode(ECHO_PIN, INPUT);
  
  ledcSetup(0, 5000, 8); ledcSetup(1, 5000, 8);
  ledcAttachPin(ENA, 0); ledcAttachPin(ENB, 1);

  pinMode(ENC_PIN, INPUT);
  attachInterrupt(digitalPinToInterrupt(ENC_PIN), encISR, RISING);

  // DNS Fix + WiFi
  IPAddress dns(8, 8, 8, 8); 
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE, dns);
  WiFi.begin(ssid, password);
  WiFi.setSleep(false);
  
  secureClient.setCACert(ca_cert);
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  
  stopAll();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED || !mqttClient.connected()) {
    if (millis() - lastHB > 5000) {
       WiFi.begin(ssid, password);
       String id = "Rover-" + String(random(0xffff), HEX);
       if(mqttClient.connect(id.c_str(), mqtt_username, mqtt_password)) {
          mqttClient.subscribe(topic_cmd);
       }
       lastHB = millis();
    }
  }
  mqttClient.loop();

  obstacleDist = getDistance();
  
  if (millis() - lastPub > 500) {
    unsigned long now = millis();
    unsigned long pulseDelta = totalPulses - lastTotalPulses;
    float timeDeltaSec = (now - lastCalcTime) / 1000.0;
    
    if (timeDeltaSec > 0) {
      linearSpeed = (pulseDelta * 1.65) / timeDeltaSec;
      currentRPM = (pulseDelta / 20.0) * (60.0 / timeDeltaSec);
    }
    
    lastTotalPulses = totalPulses;
    lastCalcTime = now;

    String data = "dist:" + String(totalPulses * 1.65, 1) + 
                  ",obs:" + String(obstacleDist, 1) + 
                  ",spd:" + String(linearSpeed, 1) + 
                  ",rpm:" + String(currentRPM, 0);
                  
    mqttClient.publish(topic_data, data.c_str());
    lastPub = millis();
  }
}