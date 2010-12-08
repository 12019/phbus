// - fbus library ------------------------------ 

// definitions
#define fbus_buffermax 128
#define fbus_delay 250
byte fbus_txbuffer[fbus_buffermax];
byte fbus_rxbuffer[fbus_buffermax];
static byte fbus_nextseq = 0x60;
typedef unsigned char byte;
struct fbus {
  byte  id;
  byte  destination;
  byte  source;
  byte  command; 
  byte  lenmsb;
  byte  lenlsb;
  byte* data;        
  byte  sequence;
  byte  checkodd;
  byte  checkeven;
};

// begin()
void fbus_begin() {
}

byte* fbus_error(const char* message) {
  error = message;
  Serial.flush();
  return NULL;
}


// - synchronize phone UART w/ Arduino ---------------------------------------
void fbus_synchronize() {
  while (1) {
    while (Serial.available()) {           // flush serial port
      byte b = Serial.read();
    }
    for (size_t n = 0; n < 128; n++) {
      Serial.print(0x55);
      delay(1);
    }
    delay(fbus_delay);
    byte* data = fbus_version();  
    if (data) {
      fbus_nextseq = 0x60;
      return;
    }
    Serial.print("\nERR:" );
    Serial.println(error);
    delay(1000);
  }
}


// - receive fbus frame ------------------------------------------------------
struct fbus* fbus_recv_frame(struct fbus* frame, size_t* length) {
  while (Serial.available())                        // synchronize w/ frameid
    if (Serial.read() == 0x1E) goto read_frame;
  return (struct fbus*)fbus_error("could not sync to frameid");
  
read_frame:
  frame->id = 0x1E;  
  size_t n = 1;   
  for (; n < 6 && Serial.available(); n++) {    // read frame header
    byte b = Serial.read();
    switch (n) {
      case 1: frame->destination = b; break;  
      case 2: frame->source      = b; break;
      case 3: frame->command     = b; break;
      case 4: frame->lenmsb      = b; break;
      case 5: frame->lenlsb      = b; break;
    }
  }
  if (n != 6) return (struct fbus*)fbus_error("Short header");
  
  byte* buf = fbus_rxbuffer;                         // read frame data
  memset(buf, 0, fbus_buffermax);     
  size_t i = 0;
  for (; i < frame->lenlsb && 
         i < fbus_buffermax && 
         Serial.available(); i++) {    
    buf[i] = Serial.read();
    n++;
  }
  if (i != frame->lenlsb) return (struct fbus*)fbus_error("short data read");
  frame->data = buf;  
  frame->sequence = buf[frame->lenlsb-1]; 
  frame->sequence &= 7; // last 3 bits of last data byte
  fbus_nextseq = 0x40 + frame->sequence;
  
  // read checksum
  for (i = 0; i < 2 && Serial.available(); i++) { 
    byte b = Serial.read();
    n++;
    switch (i) {
      case 1: frame->checkodd  = b; break;  
      case 2: frame->checkeven = b; break;
    }
  }
  if (i != 2) return (struct fbus*)fbus_error("no checksum data");
  
  // TODO - check the checksum  
  *length = n;
  return frame;
}


// - send fbus frame ---------------------------------------------------------
size_t fbus_send_frame(byte command, byte* data, size_t length) {
  byte* frame = fbus_txbuffer;
  memset(frame, 0, fbus_buffermax);  
  size_t n = 0;
  frame[n++] = 0x1E;                    // frameid
  frame[n++] = 0x00;                    // destination    (Phone)
  frame[n++] = 0x0C;                    // source         (Terminal)
  frame[n++] = command;                 // phone command
  frame[n++] = 0x00;                    // message length (MSB)  -  TODO
  frame[n++] = length+1;                // message length (LSB)
  for (size_t i = 0; i < length; i++) 
    frame[n++] = data[i];               // data segment
  frame[n++] = fbus_nextseq;            // sequence number  
  n += ((length+1) % 2);                // data segment padding
  frame[n++] = checksum(frame, n, 0);   // checksum XOR odd  bytes
  frame[n++] = checksum(frame, n, 1);   // checksum XOR even bytes
  for (size_t i = 0; i < n; i++) {
    Serial.print(frame[i]);
    delay(1);
  }
  delay(fbus_delay);
  Serial.println("\nSent:");
  for (size_t t = 0; t < n; t++) {
    Serial.print(frame[t], HEX);
    Serial.print(".");
  }
  return n;
}


// - send fbus command -------------------------------------------------------
byte* fbus_command(byte command, byte* data, size_t length, size_t* replylen) {
  // send command
  size_t framelen = fbus_send_frame(command, data, length);
  
  // receive ack frame
  struct fbus  frame;
  struct fbus* ret;    
  ret = fbus_recv_frame(&frame, &length); 
  if (!ret) {     
    Serial.print("\nerr: ");
    Serial.println(error);
    return fbus_error("did not receive reply");
  }  
  //if (frame.command != 0x7F)
 
  // receive data frame
  ret = fbus_recv_frame(&frame, &length);
  if (!ret) {
    Serial.print("\nerr: ");
    Serial.println(error);
    return fbus_error("did not receive data frame");
  } else if (!frame.data) {
    Serial.print("\nerr: ");
    Serial.println(error);    
    return fbus_error("null data frame");    
  } 
 
  // send ack 
  byte ack [] = { 0xD2 };
  framelen = fbus_send_frame(0x7F, ack, 1);

#if 1  
  Serial.print("\n|");
  for (int n = 0; n < frame.lenlsb; n++) {
    byte b = frame.data[n];
    Serial.print(b);
  }
  Serial.println("|");  
#endif

  *replylen = frame.lenlsb;
  return frame.data;  
}


// - get phone hardware and version information ------------------------------
static byte data_version [] = { 0x00, 0x01, 0x00, 0x03, 0x00, 0x01 };
byte* fbus_version() {
  size_t length = 0;
  byte* data = fbus_command(0xD1, data_version, 6, &length);
  return data;  
}


// - send an SMS --------------------------------------------------------------
static byte data_sms [] = { 
  0x00, 0x01, 0x00,  // start of SMS Frame Header
  0x01, 0x02, 0x00,  // send SMS Message
  0x07,              // SMSC number length
  0x91,              // SMSC number type (0x81=unknown, 0x91=international, 0xa1=national)   
  //0x52, 0x74, 0x52, 0x00, 0x10, 0xF0, // SMSC number Kenya safaricom: +25 47 25 00 01 0(f)  BYTE 08 - 17
  0x16, 0x14, 0x91, 0x09, 0x10, 0xF0, 
  0x00, 0x00, 0x00, 0x00,             // padding?                      52 74 52 00 10 f0 (octet format) 
  0x15,              // message type - xxxx xxx1 = submit, xxxx xxx0 = deliver
  0x00,              // message ref
  0x00,              // protocol id
  0x00,              // data coding scheme
  0x33,              // message size (unpacked!)  BYTE 22
  0x0A,              // Destination number length
  0x81,              // Number type (0x81=unknown, 0x91=international, 0xa1=national)
  //0x52, 0x07, 0x31, 0x79, 0x21, 0xf9,  // Dest#  +25 70 13 97 12 9(f)  -  BYTE 25 -> 34
  0x40, 0x30, 0x87, 0x00, 0x47, 0x00,   
  0x00, 0x00, 0x00, 0x00,              //         52 07 31 79 21 f9
  0xA7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 // Validity Period / Service Centre Time Stamp ???
}; // 42 bytes long
byte* fbus_sms(byte* number, byte* message, size_t messagelen) {

  message = (byte*)"Hi All. This message was sent through F-Bus. Cool!";
  messagelen = strlen((char*)message);
  
  char message7[messagelen];
  memset(message7, 0, messagelen);
  size_t message7len = pack7((char*)message, messagelen, message7);
  
  size_t bufsize = 42 + message7len + 1;
  byte buf[bufsize];
  memset(buf, 0, bufsize);
  size_t i = 0;
  for (size_t t = 0; t < 42; t++, i++) {
    buf[i] = data_sms[t];
  }
  data_sms[22] = messagelen;  
  for (size_t t = 0; t < message7len; t++, i++) {
    buf[i] = message7[t];
  }
  buf[i] = 0x93; // end bit
  
  size_t length = 0;
  byte* data = fbus_command(0x02, buf, bufsize, &length);
  return data;
}


/** commands
  7F ACK
  D1 VERSION   */

// - Utilities ------------------------------
byte checksum(byte* data, size_t length, byte even) {
  byte check = 0;
  for (size_t n = even; n < length; n+=2) check ^= data[n];
  return check;
}

/*unsigned char transtable [] = {
  '@' ,0xa3,'§' ,0xa5,0xe8,0xe9,0xf9,0xec,
  0xf2,0xc7,'\n',0xd8,0xf8,'\r',0xc5,0xe5,
  '?' ,'_' ,'?' ,'?' ,'?' ,'?' ,'?' ,'?' ,
  '?' ,'?' ,'?' ,'?' ,0xc6,0xe6,0xdf,0xc9,
  ' ' ,'!' ,'\"','#' ,0xa4,'%' ,'&' ,'\'',
  '(' ,')' ,'*' ,'+' ,',' ,'-' ,'.' ,'/' ,
  '0' ,'1' ,'2' ,'3' ,'4' ,'5' ,'6' ,'7' ,
  '8' ,'9' ,':' ,';' ,'<' ,'=' ,'>' ,'?' ,
  0xa1,'A' ,'B' ,'C' ,'D' ,'E' ,'F' ,'G' ,
  'H' ,'I' ,'J' ,'K' ,'L' ,'M' ,'N' ,'O' ,
  'P' ,'Q' ,'R' ,'S' ,'T' ,'U' ,'V' ,'W' ,
  'X' ,'Y' ,'Z' ,0xc4,0xd6,0xd1,0xdc,0xa7,
  0xbf,'a' ,'b' ,'c' ,'d' ,'e' ,'f' ,'g' ,
  'h' ,'i' ,'j' ,'k' ,'l' ,'m' ,'n' ,'o' ,
  'p' ,'q' ,'r' ,'s' ,'t' ,'u' ,'v' ,'w' ,
  'x' ,'y' ,'z' ,0xe4,0xf6,0xf1,0xfc,0xe0
};
byte translate7(byte b) {
  unsigned char n;
  if (b == '?') return 0x3f;
  for (n = 0; n < 128; n++) {
    if(transtable[n] == b) return n;
  }
  return 0x3f;  
}*/

size_t pack7(char* src, size_t length, char* dst) {
  unsigned char c, w;
  int n, shift, x;
  shift = 0; 
  for (n = 0; n < length; n++) {
    c = src[n] & 0x7f;
    c >>= shift;
    w = src[n+1] & 0x7f;
    w <<= (7-shift);
    shift +=1;
    c = c | w;
    if (shift == 7) {
      shift = 0x00;
      n++;
    }
    x = strlen(dst);
    dst[x] = c;
    dst[x+1] = 0;
  }
  return strlen(dst);
}

size_t unpack7(char* src, size_t length, char* dst) {
  int b1, bnext;
  int mod;
  int pand;
  int dstlen = 0;
  b1 = bnext = 0;
  for (size_t i = 0; i < length; i++) {
    mod = i%7;
    pand = 0xff >> (mod + 1);
    b1 = ((src[i] & pand) << mod) | bnext;
    bnext = (0xff & src[i]) >> (7 - mod);
    dst[dstlen++] = (char)b1;
    if (mod == 6) {
      dst[dstlen++] = (char)bnext;
      bnext = 0;
    }
  }
  dst[dstlen] = 0;
  return dstlen;
}
  
