#include <TimerOne.h>

const int buzzerPin = 9;
unsigned int bpm = 60;
boolean lvlOn = false;
float delta[8] = {0,0,0,0,0,0,0,0};
float frequency = 0;
int RegisteredNotes = 0;
unsigned int frequencies[8] = {520, 580, 640, 700, 780, 884, 990, 1060};
volatile int period = -1;
volatile unsigned long prevTime = 0;
volatile unsigned long timeT = 0;
volatile boolean firstRising = true;
volatile boolean Initialisation = false;
static unsigned long lastInterruptTime;
unsigned long currentTime;
unsigned long lastSignalTime = 0;
const unsigned long TIMEOUT = 100000;
unsigned long activationTime = 0;
const unsigned long activationDelay = 1000;

void rising()
{
  currentTime = micros();

  if (currentTime - lastInterruptTime > 100)
  {
    lastSignalTime = currentTime;

    if (firstRising)
    {
      prevTime = lastSignalTime;
      firstRising = false;
    }
    else
    {
      timeT = lastSignalTime;
      period = timeT - prevTime;
      prevTime = timeT;
    }

    lastInterruptTime = currentTime;
  }
}

void checkSignalTimeout()
{
  unsigned long currentTime = micros();

  if (currentTime - lastSignalTime > TIMEOUT)
  {
    period = -1;
    firstRising = true;
  }
}

int lane()
{
  if (period == -1)
    return -1;

  frequency = 1000000.0 / period;

  for (int i = 0; i < 8; i++)
  {
    if (abs(frequencies[i] - frequency - delta[i]) < 30)
    {
      delta[i] = frequency - frequencies[i];
      return i;
    }
  }

  return -1;
}

void metronomeTick()
{
  if (lvlOn)
  {
    tone(buzzerPin, 1000, 50);
  }
}

void setup()
{
  Serial.begin(9600);
  pinMode(buzzerPin, OUTPUT);

  attachInterrupt(0, rising, RISING);

  Timer1.initialize(60000000 / bpm);
  Timer1.attachInterrupt(metronomeTick);
}

void loop()
{
  checkSignalTimeout();
  frequency = (period == -1 ? -1 : 1000000.0 / period);

  if (Initialisation)
  {
    int currentlane = lane();
    Serial.println(currentlane);
    delay(100);

    if (Serial.available() > 0)
    {
      char character = Serial.read();

      if (character == 'l')
      {
        if (!lvlOn)
        {
          activationTime = millis();
        }
        lvlOn = !lvlOn;
      }
      if (character == 'B')
      {
        int newBpm = Serial.parseInt();
        if (newBpm > 0 && newBpm <= 300)
        {
          bpm = newBpm;
          Timer1.initialize(60000000 / bpm);
          Timer1.attachInterrupt(metronomeTick);
        }
      }
      if(character == 'N')
      {
        Initialisation = false;
      }
    }
  }
  else
  {
    if (RegisteredNotes < 8)
    {
      if (frequency > 0 && frequency < 1500)
      {
        delay(75);
        frequencies[RegisteredNotes] = frequency;
        RegisteredNotes++;
        Serial.println(0);
        delay(1000);
      }
    }
    else if (RegisteredNotes >= 8)
    {
      Initialisation = true;
    }
  }
}