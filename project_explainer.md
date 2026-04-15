# Rover V2 Project: Technical Documentation

This document explains the core algorithms, features, and architecture of the Rover V2 project.

---

## 1. A* (A-Star) Pathfinding Algorithm
The **A* Algorithm** is the heart of the rover's navigation system. It is used to find the most efficient path between two points on a grid map while avoiding obstacles.

### Why are we using it?
- **Efficiency**: Unlike simpler algorithms, A* uses a "heuristic" (an educated guess) to prioritize paths that look closer to the goal, making it much faster.
- **Accuracy**: It guarantees the shortest path possible on our 2D grid.
- **Obstacle Avoidance**: It treats "scanned" obstacles as high-cost or impassable zones, ensuring the rover never crashes into a wall during automated movement.

### A* Pseudocode
For your presentation, here is a simplified version of the logic:

```text
Initialize OpenSet (nodes to visit) and ClosedSet (visited nodes)
Add StartNode to OpenSet

While OpenSet is not empty:
    CurrentNode = Node in OpenSet with lowest "f" cost
    
    If CurrentNode is GoalNode:
        Return PATH (Success!)
    
    Move CurrentNode from OpenSet to ClosedSet
    
    For each Neighbor of CurrentNode:
        If Neighbor is a Wall or in ClosedSet:
            Skip to next neighbor
            
        new_g = CurrentNode.g + distance_to_neighbor
        
        If new_g < Neighbor.g or Neighbor not in OpenSet:
            Neighbor.parent = CurrentNode
            Neighbor.g = new_g
            Neighbor.h = distance_to_goal (Manhattan)
            If Neighbor not in OpenSet:
                Add Neighbor to OpenSet
```

---

## 2. Reflector App Features (Flutter/Dart)
The **Reflector App** is the control center for the Rover. It is built using Flutter for a premium, cross-platform experience.

### Key Features:
- **AR Floor Scanning**: Uses Augmented Reality to scan the room and identify the walkable floor area.
- **Real-time Map Generation**: Converts AR data into a 2D grid map that the rover can understand.
- **Live Telemetry Dashboard**: Displays the rover's current speed (cm/s), distance travelled, and connection status.
- **Manual & Auto Control**: Provides a virtual joystick for manual driving and an "Auto-Path" mode using the A* algorithm.

---

## 3. MQTT Communication (Message Queuing Telemetry Transport)
**MQTT** is a lightweight messaging protocol used for "Internet of Things" (IoT) devices.

### Role in the Project:
- **Broker (The Post Office)**: We use **EMQX Cloud** as our broker. It acts as a central server that forwards messages between the app and the rover.
- **Publish/Subscribe Model**:
    - The App **Publishes** commands (like `forward` or `move:50`) to the `rover/cmd` topic.
    - The Rover **Subscribes** to that topic and executes the commands.
    - The Rover **Publishes** its sensor data (distance, encoder pulses) to the `rover/data` topic for the app to display.

---

## 4. Hardware Optimization (No-Lag Core)
To ensure the rover responds instantly to user commands, we have removed the OLED display from the loop. This eliminates I2C blocking calls and reduces system latency to near-zero.

### Power & Torque (11.1V + PWM)
- **High Voltage**: Using a 3S Li-ion setup (11.1V) provides maximum torque.
- **PWM Speed Control**: The motors are controlled via GPIO 14 (ENA) and GPIO 27 (ENB).
- **Static Friction Kick**: Every time the rover starts moving, it applies a 100ms full-power pulse to overcome static friction before settling to the target speed.

---

## 5. Obstacle Avoidance (Ultrasonic Sensor)
The rover uses an **HC-SR04 Ultrasonic Sensor** for real-time safety and environment mapping.

### Technical Details:
- **Pins**: Trigger (GPIO 13), Echo (GPIO 12).
- **Auto-Stop Logic**: If the sensor detects an object within 15cm while moving forward, the rover triggers an emergency stop and notifies the app.
- **Live Monitoring**: The app displays the current distance to any obstacle in front of the rover.

---

## 4. Front-end vs. Back-end Overview

### Front-end (The Brain/Interface)
- **Technology**: Flutter / Dart
- **Location**: Your smartphone.
- **Responsibility**: Handles the user interface, complex calculations (like A* pathfinding), and AR scanning. It acts as the "high-level" brain that tells the rover where to go.

### Back-end (The Muscle/Logic)
- **Technology**: C++ / Arduino (via PlatformIO)
- **Location**: ESP32 Microcontroller on the Rover.
- **Responsibility**: Manages low-level hardware. It reads the Optical Encoder (FC-03 sensor), controls the **L298N Motor Driver**, and implements PWM speed control with a torque-boost mechanism to ensure movement on all surfaces.

### Hardware Pinout (L298N)
- **ENA / ENB**: GPIO 14 / 27 (Speed PWM)
- **IN1 / IN2**: GPIO 5 / 18 (Left Motor)
- **IN3 / IN4**: GPIO 21 / 19 (Right Motor)
- **TRIG / ECHO**: GPIO 13 / 12 (Ultrasonic)
- **Encoder**: GPIO 35 (Speed Sensor)


