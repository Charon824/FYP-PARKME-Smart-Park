# Smart-Parking-Systems-Final-Year-Project-
Hi, here is a short introduction of this project

===============================================================================================================================================
ParkMe is a smart parking mobile application designed to help users quickly find and reserve available parking spaces without spending unnecessary time searching for parking. The application provides real-time parking availability, allowing users to view the current status of parking spaces and make reservations directly through the mobile application.

The system includes a physical hardware prototype developed using an ESP32, HC-SR04 ultrasonic sensors, traffic light modules, MFRC522 RFID reader, and servo motor. The hardware is programmed using Arduino C++ to detect parking occupancy, control parking indicators, and perform RFID-based verification with booking system. The prototype is used to demonstrate and test the communication and functionality between the physical hardware and the ParkMe mobile application.

For the backend, ParkMe utilizes Firebase Realtime Database (RTDB) to synchronize parking space information in real time between the hardware and software components. The ESP32 communicates with Firebase using HTTP/HTTPS, enabling parking occupancy and status data to be transmitted and updated dynamically. This allows users to monitor the latest parking availability through the application.

The system also integrates Firebase Cloud Firestore and Firebase Authentication to manage and verify user information securely. Firebase Authentication supports user login through Google, email, and phone number, while Cloud Firestore is used to store and manage user-related information.

**Mobile Application - Flutter
Hardware Implementation - C++
Database - Firebase**
