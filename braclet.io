


#include <ESP8266WiFi.h>
#include <FirebaseESP8266.h>
#include <EasyNTPClient.h>
#include <WiFiUdp.h>
#include <SoftwareSerial.h>
#include <ESP8266WebServer.h>
#include <EEPROM.h>
#include <Wire.h>
#include "MAX30100_PulseOximeter.h"
#define WIFI_SSID "Rizaq"
#define WIFI_PASSWORD "0799534354RIZAQ!((^"
#define FIREBASE_HOST "baby-care-af448.firebaseio.com"
#define FIREBASE_AUTH "A7babaGtwABTBOblSn9F0IJH96jeCrpC6ImGpSC6"


#define REPORTING_PERIOD_MS     2000



//Variables
int i = 0;
int statusCode;
const char* ssid = "text";
const char* passphrase = "text";
String st;
String content;


//Function Decalration
bool testWifi(void);
void launchWeb(void);
void setupAP(void);

//Establishing Local server at port 80 whenever required
ESP8266WebServer server(80);

// Define NTP Client to get time
WiFiUDP ntpUDP;

EasyNTPClient ntpClient(ntpUDP, "asia.pool.ntp.org", (7200)); // IST = GMT + 5:30


long previousMillis = 0;
long interval = 60000;
volatile boolean heartBeatDetected = false;

//lm35------------------------------
const int sensor = A0; // Assigning analog pin A5 to variable 'sensor'

float tempc; //variable to store temperature in degree Celsius

float tempf; //variable to store temperature in Fahreinheit

float vout;



// PulseOximeter is the higher level interface to the sensor
// it offers:
//  * beat detection reporting
//  * heart rate calculation
//  * SpO2 (oxidation level) calculation
PulseOximeter pox;

uint32_t tsLastReport = 0;

String userId = "";
String babyId = "";
FirebaseData fbdo;


unsigned long sendDataPrevMillis = 0;
//
FirebaseData fbdo1;
FirebaseData fbdo2;
String path;
//String path = "/Test/Stream";
String parentPath;
String childPath[2] = {"/data"};
size_t childPathSize = 2;

// Callback (registered below) fired when a pulse is detected
void onBeatDetected()
{
  heartBeatDetected = true;
  Serial.println("Beat!");
}



void printResult(FirebaseData &data);

void streamCallback(MultiPathStreamData stream)
{
  Serial.println();
  Serial.println("Stream Data1 available...");

  size_t numChild = sizeof(childPath) / sizeof(childPath[0]);

  for (size_t i = 0; i < numChild; i++)
  {
    if (stream.get(childPath[i]))
    {
      Serial.println("path: " + stream.dataPath + ", type: " + stream.type + ", value: " + stream.value);
    }
  }

  Serial.println();

}



void streamTimeoutCallback(bool timeout)
{
  if (timeout)
  {
    Serial.println();
    Serial.println("Stream timeout, resume streaming...");
    Serial.println();
  }
}


void setup() {
  Serial.begin(115200); //Initialising if(DEBUG)Serial Monitor
  Serial.println();
  Serial.println("Disconnecting previously connected WiFi");
  WiFi.disconnect();
  EEPROM.begin(512); //Initialasing EEPROM
  //    for (int i = 0 ; i < EEPROM.length() ; i++) {
  //
  //EEPROM.write(i, 0);
  //
  //}
  delay(10);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.println();
  Serial.println();
  Serial.println("Startup");
  //---------------------------------------- Read eeprom for ssid and pass
  Serial.println("Reading EEPROM ssid");

  String esid;
  for (int i = 0; i < 32; ++i)
  {
    esid += char(EEPROM.read(i));
  }
  Serial.println();
  Serial.print("SSID: ");
  Serial.println(esid);
  Serial.println("Reading EEPROM pass");

  String epass = "";
  for (int i = 32; i < 96; ++i)
  {
    epass += char(EEPROM.read(i));
  }
  Serial.print("PASS: ");
  Serial.println(epass);


  WiFi.begin(esid.c_str(), epass.c_str());
  if (testWifi())
  {
    Serial.println("Succesfully Connected!!!");
    delay(100);
  }
  else
  {
    Serial.println("Turning the HotSpot On");
    launchWeb();
    setupAP();// Setup HotSpot
  }

  Serial.println();
  Serial.println("Waiting.");

  while ((WiFi.status() != WL_CONNECTED))
  {
    Serial.print(".");
    delay(100);
    server.handleClient();
  }

  delay(100);


  Firebase.begin(FIREBASE_HOST, FIREBASE_AUTH);
  Firebase.reconnectWiFi(true);
  fbdo.setBSSLBufferSize(1024, 1024);
  fbdo.setResponseSize(1024);

    //Set the size of WiFi rx/tx buffers in the case where we want to work with large data.
  fbdo1.setBSSLBufferSize(1024, 1024);

  //Set the size of HTTP response buffers in the case where we want to work with large data.
  fbdo1.setResponseSize(1024);


  //Set the size of WiFi rx/tx buffers in the case where we want to work with large data.
  fbdo2.setBSSLBufferSize(1024, 1024);

  //Set the size of HTTP response buffers in the case where we want to work with large data.
  fbdo2.setResponseSize(1024);
  //

  if (userId == "")
  {
    Serial.println(" while ...... " + parentPath);

    if (Firebase.getString(fbdo, "12345/babyId")) {

      if (fbdo.dataType() == "string") {
        Serial.println(fbdo.stringData());


        babyId = fbdo.stringData();
        parentPath = "/babys/" + babyId + "/data/";
        path = "/babys/" + babyId + "/logs/";
        Serial.println(" while ...... " + parentPath);

      }

    } else {
      Serial.println(fbdo.errorReason());
    }
    delay(1000);

  }

  if (!Firebase.beginMultiPathStream(fbdo1, parentPath, childPath, childPathSize))
  {
    Serial.println("------------------------------------");
    Serial.println("Can't begin stream connection...");
    Serial.println("REASON: " + fbdo1.errorReason());
    Serial.println("------------------------------------");
    Serial.println();
  }

  Firebase.setMultiPathStreamCallback(fbdo1, streamCallback, streamTimeoutCallback);


  if (!pox.begin()) {
    Serial.println("FAILED");
    for (;;);
  } else {
    Serial.println("SUCCESS");
  }


  // Register a callback for the beat detection
  pox.setOnBeatDetectedCallback(onBeatDetected);
}


void loop() {


  vout = analogRead(sensor); //Reading the value from sensor

  // Converting to Fahrenheit
  vout = (vout * 330.0) / 1023.0;

  tempc = vout ; // Storing value in Degree Celsius

  tempf = (vout * 1.8) + 32;

  pox.update();

//  unsigned long currentMillis = millis();
  if (millis() - tsLastReport > REPORTING_PERIOD_MS) {
    float bpm = pox.getHeartRate();
    float SpO2 = pox.getSpO2();
    Serial.print("Heart rate:");
    Serial.print(bpm);
    Serial.print("bpm / SpO2:");
    Serial.print(SpO2);
    Serial.print("temp / temp:");
    Serial.print(tempc);
    Serial.println("%");
    if (millis() - sendDataPrevMillis > 6000)
    {
       sendDataPrevMillis = millis();
      pox.shutdown();

      
  Serial.println("------------------------------------");
    Serial.println("Set JSON..."+ parentPath);

      
      FirebaseJson json;
      json.set("bpm", bpm);
      json.set("SpO2", SpO2);
      json.set("tempc", tempc);
    
      if (Firebase.setJSON(fbdo2, parentPath, json))
      {

        Serial.println("PASSED");
        Serial.println();
      }
      else
      {
//        pox.resume();
        Serial.println("FAILED");
        Serial.println("REASON: " + fbdo2.errorReason());
        Serial.println("------------------------------------");
        Serial.println();
      }

      pox.resume();
      Serial.println("------------------------------------");
      Serial.println("Set JSON...");





    }



    tsLastReport = millis();
  }


}



















//----------------------------------------------- Fuctions used for WiFi credentials saving and connecting to it which you do not need to change
bool testWifi(void)
{
  int c = 0;
  Serial.println("Waiting for Wifi to connect");
  while ( c < 20 ) {
    if (WiFi.status() == WL_CONNECTED)
    {
      return true;
    }
    delay(500);
    Serial.print("*");
    c++;
  }
  Serial.println("");
  Serial.println("Connect timed out, opening AP");
  return false;
}

void launchWeb()
{
  Serial.println("");
  if (WiFi.status() == WL_CONNECTED)
    Serial.println("WiFi connected");
  Serial.print("Local IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("SoftAP IP: ");
  Serial.println(WiFi.softAPIP());
  createWebServer();
  // Start the server
  server.begin();
  Serial.println("Server started");
}

void setupAP(void)
{
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  int n = WiFi.scanNetworks();
  Serial.println("scan done");
  if (n == 0)
    Serial.println("no networks found");
  else
  {
    Serial.print(n);
    Serial.println(" networks found");
    for (int i = 0; i < n; ++i)
    {
      // Print SSID and RSSI for each network found
      Serial.print(i + 1);
      Serial.print(": ");
      Serial.print(WiFi.SSID(i));
      Serial.print(" (");
      Serial.print(WiFi.RSSI(i));
      Serial.print(")");
      Serial.println((WiFi.encryptionType(i) == ENC_TYPE_NONE) ? " " : "*");
      delay(10);
    }
  }
  Serial.println("");
  st = "<ol>";
  for (int i = 0; i < n; ++i)
  {
    // Print SSID and RSSI for each network found
    st += "<li>";
    st += WiFi.SSID(i);
    st += " (";
    st += WiFi.RSSI(i);

    st += ")";
    st += (WiFi.encryptionType(i) == ENC_TYPE_NONE) ? " " : "*";
    st += "</li>";
  }
  st += "</ol>";
  delay(100);
  WiFi.softAP("BabyCareBracelet", "");
  Serial.println("softap");
  launchWeb();
  Serial.println("over");
}

void createWebServer()
{
  {
    server.on("/", []() {

      IPAddress ip = WiFi.softAPIP();
      String ipStr = String(ip[0]) + '.' + String(ip[1]) + '.' + String(ip[2]) + '.' + String(ip[3]);
      content = "<!DOCTYPE HTML>\r\n<html>Hello from BabyCare conaction at ";
      content += "<form action=\"/scan\" method=\"POST\"><input type=\"submit\" value=\"scan\"></form>";
      content += ipStr;
      content += "<p>";
      content += st;
      content += "</p><form method='get' action='setting'><label>SSID: </label><input name='ssid' length=32><input name='pass' length=64><input type='submit'></form>";
      content += "</html>";
      server.send(200, "text/html", content);
    });
    server.on("/scan", []() {
      //setupAP();
      IPAddress ip = WiFi.softAPIP();
      String ipStr = String(ip[0]) + '.' + String(ip[1]) + '.' + String(ip[2]) + '.' + String(ip[3]);

      content = "<!DOCTYPE HTML>\r\n<html>go back";
      server.send(200, "text/html", content);
    });

    server.on("/setting", []() {
      String qsid = server.arg("ssid");
      String qpass = server.arg("pass");
      if (qsid.length() > 0 && qpass.length() > 0) {
        Serial.println("clearing eeprom");
        for (int i = 0; i < 96; ++i) {
          EEPROM.write(i, 0);
        }
        Serial.println(qsid);
        Serial.println("");
        Serial.println(qpass);
        Serial.println("");

        Serial.println("writing eeprom ssid:");
        for (int i = 0; i < qsid.length(); ++i)
        {
          EEPROM.write(i, qsid[i]);
          Serial.print("Wrote: ");
          Serial.println(qsid[i]);
        }
        Serial.println("writing eeprom pass:");
        for (int i = 0; i < qpass.length(); ++i)
        {
          EEPROM.write(32 + i, qpass[i]);
          Serial.print("Wrote: ");
          Serial.println(qpass[i]);
        }
        EEPROM.commit();

        content = "{\"Success\":\"saved to eeprom... reset to boot into new wifi\"}";
        statusCode = 200;
        ESP.reset();
      } else {
        content = "{\"Error\":\"404 not found\"}";
        statusCode = 404;
        Serial.println("Sending 404");
      }
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(statusCode, "application/json", content);

    });
  }
}