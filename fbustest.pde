
#include <Ethernet.h>

// - global definitions ------------------------------------------------------
static const char* error;


// - server configuration ----------------------------------------------------
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192, 168, 1, 253 };
byte gateway[] = { 192, 168, 1, 254 };
byte subnet[] = { 255, 255, 255, 0 };
Server server = Server(80);




// - setup -------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("Starting...");
  
  /*char* message = "hey there sailor!";
  size_t messagelen = strlen(message);
  char message7[messagelen];
  memset(message7, 0, messagelen);
  size_t message7len = pack7(message, messagelen, message7);
  Serial.print("Packed (");
  Serial.print(message7len);
  Serial.print(") |");
  for (size_t t = 0; t < message7len; t++) {
    Serial.print((byte)message7[t], HEX);
    Serial.print(".");
  }
  Serial.println("|");
  
  char message8[messagelen+1];
  memset(message8, 0, messagelen+1);
  size_t message8len = unpack7(message7, messagelen, message8);
  Serial.print("Unpacked (");
  Serial.print(message8len);
  Serial.print(") |");
  for (size_t t = 0; t < message8len; t++) {
    Serial.print((byte)message8[t]);
    Serial.print(".");
  }
  Serial.println("|");*/
  
  Ethernet.begin(mac, ip, gateway, subnet);
  server.begin();  
  delay(1000);
  fbus_synchronize();  
}


// - loop --------------------------------------------------------------------
void loop() {   
  byte* data = NULL;
 
poll:
  //delay(2000);
  //data = fbus_version();  
  //if (!data) goto sync;

  if (Serial.available())  // Is there a message available on FBUS?
    dispatch_http();
  if (server.available())  // Is there a message available on HTTP?
    dispatch_fbus();    
    
  return;
  
sync:
  fbus_synchronize();  
  data = fbus_version();  
  if (data) return;
  Serial.print("\nERR:" );
  Serial.println(error);
  delay(2000);
  goto sync;
}


// - dispatch SMS on FBUS ----------------------------------------------------
// GET /sms/0824485157/this is my message I send HTTP/1.0
void dispatch_fbus() {
  byte buf[256];      // use fbus_buffer
  memset(buf, 0, 256);     
  Client client = server.available();    
  size_t index = 0;
  while (server.available()) {
    byte b = client.read();
    if (b == 13 || index >= 256) {
      buf[index] = '\0';
      server.write("HTTP/1.0 200 OK\n");
      server.write("Content-Type: text/plain\n\n");      
      server.write((char*)buf);
      server.write("\n");
      client.stop(); // TODO
      index = 0;
    } else {
      buf[index] = b;
      index++;
    }
  }
  // TODO - finish HTTP support
  // extract message text
  // uudecode it
  // send it -> fbus_send_sms();
  //fbus_synchronize();
  byte* data = fbus_sms((byte*)"0701397129", buf, strlen((char*)buf));  
  //byte* data = fbus_version();
  if (!data) {
    Serial.print("\nCOULD NOT SEND:" );
    Serial.println(error);
    fbus_synchronize();
    return;
  }    
  Serial.print("\nDispatched message on FBUS: ");
  Serial.println((char*)buf); 
}


// - dispatch SMS on HTTP ----------------------------------------------------
void dispatch_http() {
}





