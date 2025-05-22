#include <WiFi.h>
#include <WebSocketsServer.h>

const char* apSSID = "ESP32_LED_Controller";
const char* apPassword = "12345678";
#define SWITCH_PIN 4   // Verify switch connected to GPIO4-GND
#define LED_PIN 23     // LED on GPIO23

WebSocketsServer webSocket(81);
const int MAX_LEDS = 10;

struct Led {
  int pin;
  bool state;
  String name;
};

Led leds[MAX_LEDS] = {{LED_PIN, false, "Main LED"}};
int ledCount = 1;

void updateAllClients(int index) {
  String message = "LED_UPDATE:" + 
                  String(leds[index].pin) + ":" + 
                  (leds[index].state ? "ON" : "OFF") + ":" +
                  leds[index].name;
  webSocket.broadcastTXT(message);
}

void handleWebSocketEvent(uint8_t client_num, WStype_t type, uint8_t* payload, size_t length) {
  switch(type) {
    case WStype_DISCONNECTED:
      Serial.printf("[%u] Disconnected!\n", client_num);
      break;
      
    case WStype_CONNECTED: {
      for(int i=0; i<ledCount; i++) {
        String msg = "LED_UPDATE:" + 
                    String(leds[i].pin) + ":" + 
                    (leds[i].state ? "ON" : "OFF") + ":" +
                    leds[i].name;
        webSocket.sendTXT(client_num, msg);
      }
      break;
    }
      
    case WStype_TEXT: {
      String command = String((char*)payload);
      
      if(command.startsWith("SET_LED:")) {
        int sep1 = command.indexOf(':', 8);
        int sep2 = command.indexOf(':', sep1+1);
        int pin = command.substring(8, sep1).toInt();
        bool state = command.substring(sep1+1, sep2) == "ON";
        
        for(int i=0; i<ledCount; i++) {
          if(leds[i].pin == pin) {
            leds[i].state = state;
            digitalWrite(pin, state);
            updateAllClients(i);
            break;
          }
        }
      }
      else if(command.startsWith("ADD_LED:")) {
        int pin = command.substring(8).toInt();
        if(ledCount < MAX_LEDS && pin >= 0 && pin <= 39) {
          leds[ledCount] = {pin, false, "LED " + String(pin)};
          pinMode(pin, OUTPUT);
          digitalWrite(pin, LOW);
          ledCount++;
          updateAllClients(ledCount-1);
          webSocket.broadcastTXT("LED_ADDED:" + String(pin));
        }
      }
      else if(command.startsWith("RENAME_LED:")) {
        int sep = command.indexOf(':', 11);
        int pin = command.substring(11, sep).toInt();
        String newName = command.substring(sep+1);
        
        for(int i=0; i<ledCount; i++) {
          if(leds[i].pin == pin) {
            leds[i].name = newName;
            updateAllClients(i);
            break;
          }
        }
      }
      else if(command.startsWith("REMOVE_LED:")) {
        int pin = command.substring(11).toInt();
        for(int i=0; i<ledCount; i++) {
          if(leds[i].pin == pin) {
            digitalWrite(pin, LOW);
            for(int j=i; j<ledCount-1; j++) {
              leds[j] = leds[j+1];
            }
            ledCount--;
            webSocket.broadcastTXT("LED_REMOVED:" + String(pin));
            break;
          }
        }
      }
      break;
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  
  pinMode(SWITCH_PIN, INPUT_PULLUP);

  for(int i=0; i<3; i++) {
    digitalWrite(LED_PIN, HIGH); delay(200);
    digitalWrite(LED_PIN, LOW); delay(200);
  }
  
  WiFi.softAP(apSSID, apPassword);
  webSocket.begin();
  webSocket.onEvent(handleWebSocketEvent);

  Serial.println("\nSystem Ready - GPIO23 Control");
  Serial.println("=============================");
  Serial.printf("Switch: GPIO%d | LED: GPIO%d\n", SWITCH_PIN, LED_PIN);
}

void loop() {
  webSocket.loop();
  
  static bool lastStableState = HIGH;
  static unsigned long lastDebounce = 0;
  const unsigned long debounceDelay = 100;
  bool reading = digitalRead(SWITCH_PIN);

  if (reading != lastStableState) {
    lastDebounce = millis();
  }

  if ((millis() - lastDebounce) > debounceDelay) {
    if (reading != lastStableState) {
      lastStableState = reading;
      
      leds[0].state = !lastStableState;
      digitalWrite(LED_PIN, leds[0].state);
      
      Serial.printf("SW: %s → LED%d: %s\n",
                   lastStableState ? "OPEN " : "PRESS",
                   LED_PIN,
                   leds[0].state ? "ON " : "OFF");
    }
  }
}