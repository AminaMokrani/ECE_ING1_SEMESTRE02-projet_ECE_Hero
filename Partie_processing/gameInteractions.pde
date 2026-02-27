import processing.serial.*;
import ddf.minim.*;

// Variables pour les images et le visuel
PImage jouer, option, quitter, titleImg, img, lvlSelectBackground;
PImage lvl01, lvl02, volumeON, volumeOFF;
PImage selectButton, resultsBackground;
PImage ResultsIcon;
PImage[] levelBackgrounds = new PImage[2];
boolean initialisationDone = false;
// Système audio
Minim minim;
AudioPlayer menuMusic;
AudioPlayer currentLevelMusic;
boolean isMenuMusicPlaying = false;

// Variables pour les niveaux
float baseBPM = 60.0;
int selectedLvl = 0;
PFont customFont;
int score = 0, selectedOption = 0;
boolean option1Active = false, menuLvlActive = false, menuOptionActive = false;
boolean metroOn = true;
boolean resultsScreenActive = false;
boolean mainMenuActive = false;


// Variables de lanes
int cols = 8, roadTopWidth = 200, roadBottomWidth, roadHeight, limit;
float[] lanePositionsXTop, lanePositionsXBottom;

// Patterns pour chaque musique
int[][] mapNotes = {
  {1, 1, 1, 1,
    1, 1, 1, 1, 1,
    2, 4, 5, 2, 4, 6, 5, 2, 4, 5, 4, 2, 1,
    2, 4, 5, 2, 4, 6, 5, 2, 4, 5, 4, 2, 1,
    2, 4, 5, 2, 4, 6, 5, 2, 4, 5, 4, 2, 1,
    2, 4, 5, 2, 4, 6, 5, 2, 4, 5, 4, 2, 1,
  2, 4, 5, 2, 4, 6, 5, 2, 4, 5, 4, 2, 1},


  {1, 1, 1, 1,
   3,3,4,5,5,4,3,2,1,1,2,3,3,2,2,
  3,3,4,5,5,4,3,2,1,1,2,3,2,1,1
  }
};

int[][] mapLen = {
  {0, 0, 0, 0,
    0, 0, 0, 0, 0, 
   2, 2, 10, 1, 1, 1, 5, 1, 1, 8, 2, 8,0,
   2, 2, 10, 1, 1, 1, 5, 1, 1, 8, 2, 8,0,
   2, 2, 10, 1, 1, 1, 5, 1, 1, 8, 2, 8,0,
   2, 2, 10, 1, 1, 1, 5, 1, 1, 8, 2, 8,0,
  2, 2, 10, 1, 2, 1, 5, 1, 1, 8, 2, 8, 0},

  {
    0, 0, 0, 0,
    2,2,2,2,2,2,2,2,2,2,2,2,4,2,4,
    2,2,2,2,2,2,2,2,2,2,2,2,4,2,4
  }
};

int[] BPMs = {65, 55};


color[] laneColors = new color[cols];

// Variables pour la communication
Serial myPort;
int arduinoInput = -1;

// Variables pour le rythme
int lastBeatTime = 0;
int beatInterval;
int noteIndex = 0;
boolean allNotesActivated = false;

// Variables pour le timer
int levelStartTime;
int levelEndTime;
boolean timerRunning = false;

// Listes
ArrayList<Square> squares;
ArrayList<Note> notes;
ArrayList<Lvl> lvls;

// Variables pour l'effet de fin
ArrayList<Particle> particles;
PGraphics blurBuffer;
int blurRadius = 0;
int maxBlurRadius = 10;
boolean increasingBlur = true;

// Particules pour l'effet de fin
class Particle {
  float x, y;
  float speed;
  float size;
  float alpha;

  Particle() {
    this.x = random(width);
    this.y = height + random(100);
    this.speed = random(1, 3);
    this.size = random(2, 8);
    this.alpha = random(100, 255);
  }

  void update() {
    y -= speed;
    alpha -= 0.5;
    if (alpha < 0) alpha = 0;
  }

  void display() {
    noStroke();
    fill(255, alpha);
    ellipse(x, y, size, size);
  }

  boolean isDead() {
    return y < -10 || alpha <= 0;
  }
}



class Square {
  float x1, x2, y;
  float baseSpeed;
  float currentSpeed;
  color Color;
  int lane;
  boolean toRemove = false, trail = false, stop = false;

  Square(int lane, float y, boolean trail) {
    this.lane = lane;
    this.y = y;
    this.Color = laneColors[lane];
    this.trail = trail;
    setBPM(baseBPM);
    updatePosition();
  }

  void setBPM(float newBPM) {
    float beatsPerSecond = newBPM / 60.0;
    float secondsPerMeasure = 4.0 / beatsPerSecond;
    float framesPerMeasure = secondsPerMeasure * 60;
    this.baseSpeed = height / framesPerMeasure;
    this.currentSpeed = this.baseSpeed;
  }

  void updatePosition() {
    float interp = y / height;
    x1 = lerp(lanePositionsXTop[lane], lanePositionsXBottom[lane], interp);
    x2 = lerp(lanePositionsXTop[lane + 1], lanePositionsXBottom[lane + 1], interp);

    float distanceToLimit = limit - y;
    if (distanceToLimit < 300) {
      float accelerationFactor = map(distanceToLimit, 300, 0, 1.0, 2);
      this.currentSpeed = baseSpeed * accelerationFactor;
    } else {
      this.currentSpeed = baseSpeed;
    }
  }

  boolean display(boolean stop, ArrayList<HitEffect> hitEffects) {
    y += currentSpeed;
    updatePosition();

    fill(trail ? color(Color, 150) : Color);
    noStroke();
    beginShape();
    vertex(x1, y - 40);
    vertex(x2, y - 40);
    vertex(x2, y);
    vertex(x1, y);
    endShape(CLOSE);

    if (y >= limit && y <= limit + 20) {
      if (!stop) {
        if (arduinoInput == lane) {
          toRemove = true;
          score += 20;
          float effectX = (x1 + x2) / 2;
          float effectY = limit;
          hitEffects.add(new HitEffect(effectX, effectY));
        } else {
          stop = true;
        }
      }
    }

    if (y >= height) toRemove = true;
    return stop;
  }
}

class Note {
  int len, lane;
  boolean stop = false;
  ArrayList<Square> squares;
  boolean active = false;
  boolean completed = false;

  Note(int i, int level) {
    this.len = mapLen[level][i];
    this.lane = mapNotes[level][i];
    squares = new ArrayList<Square>();
  }

  void activate() {
    active = true;
    int add = 0;
    for (int j = 0; j < len; j++) {
      boolean notTrail = (j == 0 || j == len - 1);
      squares.add(new Square(lane - 1, -add, !notTrail));
      add += 10;
    }
  }

  void display(ArrayList<HitEffect> hitEffects) {
    if (active && !completed) {
      for (int i = squares.size() - 1; i >= 0; i--) {
        Square s = squares.get(i);
        stop = s.display(stop, hitEffects);
        if (s.toRemove) squares.remove(i);
      }

      if (squares.isEmpty()) {
        completed = true;
      }
    }
  }
}

class Lvl {
  int[] laneMap, lenMap;
  PImage background;
  ArrayList<Note> notes;
  ArrayList<HitEffect> hitEffects;
  boolean bpmSent = false;
  float currentBPM;
  int levelNum;
  float levelBPM;

  Lvl(int levelNum, int BPM) {
    this.levelNum = levelNum;
    this.laneMap = mapNotes[levelNum];
    this.lenMap = mapLen[levelNum];
    this.background = levelBackgrounds[levelNum];
    this.levelBPM = BPM;
    this.currentBPM = levelBPM;

    notes = new ArrayList<Note>();
    hitEffects = new ArrayList<HitEffect>();
    for (int i = 0; i < laneMap.length; i++) {
      notes.add(new Note(i, levelNum));
    }
  }

  void setBPM(float newBPM) {
    this.currentBPM = newBPM;
    beatInterval = (int)(60000 / newBPM);
  }

  void display() {
    if (!bpmSent) {
      if (menuMusic != null) {
        menuMusic.pause();
        isMenuMusicPlaying = false;
      }

      String musicFile = (levelNum == 0) ? "lvl01.mp3" : "lvl02.mp3";
      if (currentLevelMusic != null) currentLevelMusic.close();
      currentLevelMusic = minim.loadFile(musicFile);
      currentLevelMusic.play();
      if (metroOn) myPort.write("l\n");
      myPort.write("B\n");
      myPort.write(currentBPM + "\n");
      bpmSent = true;
      setBPM(currentBPM);
      lastBeatTime = millis();
      noteIndex = 0;
      allNotesActivated = false;
      levelStartTime = millis();
      timerRunning = true;
    }

    if (!allNotesActivated && millis() - lastBeatTime >= beatInterval) {
      lastBeatTime = millis();
      if (noteIndex < notes.size()) {
        notes.get(noteIndex).activate();
        noteIndex++;
      } else {
        allNotesActivated = true;
      }
    }

    imageMode(CORNER);
    image(background, 0, 0);
    drawRoad();

    stroke(255, 0, 0);
    line(0, limit, width, limit);

    for (int i = hitEffects.size() - 1; i >= 0; i--) {
      HitEffect effect = hitEffects.get(i);
      effect.update();
      effect.display();
      if (effect.isFinished) hitEffects.remove(i);
    }

    boolean allNotesCompleted = true;
    for (int j = 0; j < notes.size(); j++) {
      Note ln = notes.get(j);
      ln.display(hitEffects);
      if (!ln.completed) {
        allNotesCompleted = false;
      }
    }


    fill(255, 180);
    noStroke();
    rect(40, 20, 300, 200, 15);
    fill(0);
    textAlign(LEFT, TOP);
    textSize(30);
    text("Level: " + (levelNum+1), 60, 30);
    text("Score: " + score, 60, 80);
    textSize(20);
    text("BPM: " + currentBPM, 60, 130);
    if (timerRunning) {
      text("Time: " + ((millis() - levelStartTime)/1000) + "s", 60, 180);
    }

    if (allNotesActivated && allNotesCompleted) {
      levelEndTime = millis();
      timerRunning = false;
      if (currentLevelMusic != null) {
        currentLevelMusic.pause();
      }
      if (metroOn) myPort.write("l\n");
      resultsScreenActive = true;
      option1Active = false;
      bpmSent = false;
    }
  }
}

class HitEffect {
  float x, y, size = 10, maxSize = 100, growthSpeed = 5;
  boolean isFinished = false;

  HitEffect(float x, float y) {
    this.x = x;
    this.y = y;
  }

  void update() {
    if (size < maxSize) size += growthSpeed;
    else isFinished = true;
  }

  void display() {
    noFill();
    stroke(255, 200, 0, 255 - map(size, 10, maxSize, 0, 255));
    strokeWeight(3);
    ellipse(x, y, size, size);
    strokeWeight(1);
  }
}

void setupMenuLvl() {
  lvlSelectBackground = loadImage("MenuSelect.png");
  lvlSelectBackground.resize(width, height);
  lvl01 = loadImage("lvl01.png");
  lvl01.resize(245, 170);
  selectButton = loadImage("selectButton.png");
  lvl02 = loadImage("lvl02.png");
  lvl02.resize(250, 170);

  volumeON = loadImage("volume-up.png");
  volumeON.resize(200, 200);
  volumeOFF = loadImage("volume-down.png");
  volumeOFF.resize(200, 200);

  resultsBackground = loadImage("LvlSelectMenu.png");
}

void drawOption(float x, float y, PImage img) {
  imageMode(CORNER);
  image(img, x, y);
}

void drawMenuLvl() {
  image(lvlSelectBackground, 0, 0);
  drawOption(185, 250, lvl01);
  drawOption(185, 330, lvl02);
  image(selectButton, (selectedLvl == 0 ? 373 : 390), (selectedLvl == 0 ? 180 : 250));
  String texts[] = {"Haut", "Bas", "Confirmer", "Quitter"};
  int indexC [] = {0, 1, 2, 4};
  drawControlsBackground();
  drawControls(texts, texts.length, indexC);
}

void drawResultsScreen() {
  // Dessiner le niveau flou en arrière-plan
  blurBuffer.beginDraw();
  Lvl currentLvl = lvls.get(selectedLvl);
  blurBuffer.image(currentLvl.background, 0, 0);
  blurBuffer.endDraw();

  // Appliquer l'effet de flou
  if (increasingBlur && blurRadius < maxBlurRadius) {
    blurRadius++;
  }
  fastBlur(blurBuffer, blurRadius);
  image(blurBuffer, 0, 0);

  // Ajouter des particules
  if (frameCount % 2 == 0) {
    particles.add(new Particle());
  }

  // Mettre à jour et afficher les particules
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) {
      particles.remove(i);
    }
  }


  fill(255, 200);
  rectMode(CENTER);
  rect(width/2, height/2, width * 0.8, height * 0.7, 20);


  fill(0);
  textAlign(CENTER, CENTER);
  imageMode(CENTER);
  image(ResultsIcon, width/2, height/2 - 100);
  imageMode(CORNER);
  textSize(30);
  text("Score: " + score, width/2, height/2 - 30);
  text("Temps: " + ((levelEndTime - levelStartTime)/1000) + "s", width/2, height/2 + 20);


  textSize(20);
  fill(0);
  textSize(20);
  text("Appuyez sur ", width/2 - 100, height/2 + 100);

  fill(laneColors[3]);
  noStroke();
  rect(width/2 - 20, height/2 + 100, 15, 15, 3);
  fill(0);
  text("pour continuer", width/2+80, height/2 + 100);

  if (!resultsScreenActive) {
    blurRadius = 0;
    particles.clear();
  }
}





void fastBlur(PGraphics img, int radius) {
  if (radius < 1) return;
  img.loadPixels();
  int w = img.width;
  int h = img.height;
  int wm = w - 1;
  int hm = h - 1;
  int wh = w * h;
  int div = radius + radius + 1;

  int r[] = new int[wh];
  int g[] = new int[wh];
  int b[] = new int[wh];
  int rsum, gsum, bsum, x, y, i, p, yp, yi, yw;
  int vmin[] = new int[max(w, h)];

  int divsum = (div + 1) >> 1;
  divsum *= divsum;
  int dv[] = new int[256 * divsum];
  for (i = 0; i < 256 * divsum; i++) {
    dv[i] = (i / divsum);
  }

  yw = yi = 0;

  int[][] stack = new int[div][3];
  int stackpointer;
  int stackstart;
  int[] sir;
  int rbs;
  int r1 = radius + 1;
  int routsum, goutsum, boutsum;
  int rinsum, ginsum, binsum;

  for (y = 0; y < h; y++) {
    rinsum = ginsum = binsum = routsum = goutsum = boutsum = rsum = gsum = bsum = 0;
    for (i = -radius; i <= radius; i++) {
      p = img.pixels[yi + min(wm, max(i, 0))];
      sir = stack[i + radius];
      sir[0] = (p & 0xff0000) >> 16;
      sir[1] = (p & 0x00ff00) >> 8;
      sir[2] = (p & 0x0000ff);
      rbs = r1 - abs(i);
      rsum += sir[0] * rbs;
      gsum += sir[1] * rbs;
      bsum += sir[2] * rbs;
      if (i > 0) {
        rinsum += sir[0];
        ginsum += sir[1];
        binsum += sir[2];
      } else {
        routsum += sir[0];
        goutsum += sir[1];
        boutsum += sir[2];
      }
    }
    stackpointer = radius;

    for (x = 0; x < w; x++) {
      r[yi] = dv[rsum];
      g[yi] = dv[gsum];
      b[yi] = dv[bsum];

      rsum -= routsum;
      gsum -= goutsum;
      bsum -= boutsum;

      stackstart = stackpointer - radius + div;
      sir = stack[stackstart % div];

      routsum -= sir[0];
      goutsum -= sir[1];
      boutsum -= sir[2];

      if (y == 0) {
        vmin[x] = min(x + radius + 1, wm);
      }
      p = img.pixels[yw + vmin[x]];

      sir[0] = (p & 0xff0000) >> 16;
      sir[1] = (p & 0x00ff00) >> 8;
      sir[2] = (p & 0x0000ff);

      rinsum += sir[0];
      ginsum += sir[1];
      binsum += sir[2];

      rsum += rinsum;
      gsum += ginsum;
      bsum += binsum;

      stackpointer = (stackpointer + 1) % div;
      sir = stack[(stackpointer) % div];

      routsum += sir[0];
      goutsum += sir[1];
      boutsum += sir[2];

      rinsum -= sir[0];
      ginsum -= sir[1];
      binsum -= sir[2];

      yi++;
    }
    yw += w;
  }

  for (x = 0; x < w; x++) {
    rinsum = ginsum = binsum = routsum = goutsum = boutsum = rsum = gsum = bsum = 0;
    yp = -radius * w;
    for (i = -radius; i <= radius; i++) {
      yi = max(0, yp) + x;

      sir = stack[i + radius];

      sir[0] = r[yi];
      sir[1] = g[yi];
      sir[2] = b[yi];

      rbs = r1 - abs(i);

      rsum += sir[0] * rbs;
      gsum += sir[1] * rbs;
      bsum += sir[2] * rbs;

      if (i > 0) {
        rinsum += sir[0];
        ginsum += sir[1];
        binsum += sir[2];
      } else {
        routsum += sir[0];
        goutsum += sir[1];
        boutsum += sir[2];
      }

      if (i < hm) {
        yp += w;
      }
    }
    yi = x;
    stackpointer = radius;
    for (y = 0; y < h; y++) {
      img.pixels[yi] = 0xff000000 | (dv[rsum] << 16) | (dv[gsum] << 8) | dv[bsum];

      rsum -= routsum;
      gsum -= goutsum;
      bsum -= boutsum;

      stackstart = stackpointer - radius + div;
      sir = stack[stackstart % div];

      routsum -= sir[0];
      goutsum -= sir[1];
      boutsum -= sir[2];

      if (x == 0) {
        vmin[y] = min(y + r1, hm) * w;
      }
      p = x + vmin[y];

      sir[0] = r[p];
      sir[1] = g[p];
      sir[2] = b[p];

      rinsum += sir[0];
      ginsum += sir[1];
      binsum += sir[2];

      rsum += rinsum;
      gsum += ginsum;
      bsum += binsum;

      stackpointer = (stackpointer + 1) % div;
      sir = stack[stackpointer];

      routsum += sir[0];
      goutsum += sir[1];
      boutsum += sir[2];

      rinsum -= sir[0];
      ginsum -= sir[1];
      binsum -= sir[2];

      yi += w;
    }
  }
  img.updatePixels();
}

void drawRoad() {
  fill(50, 150);
  noStroke();
  beginShape();
  vertex((width - roadTopWidth) / 2, 0);
  vertex((width + roadTopWidth) / 2, 0);
  vertex((width + roadBottomWidth) / 2, roadHeight);
  vertex((width - roadBottomWidth) / 2, roadHeight);
  endShape(CLOSE);
  strokeWeight(1);
  stroke(255);
  for (int i = 0; i <= cols; i++) {
    line(lanePositionsXTop[i], 0, lanePositionsXBottom[i], height);
  }
}

void setupLvl() {
  frameRate(60);
  limit = height - 200;
  roadBottomWidth = width - 50;
  roadHeight = height;

  lanePositionsXTop = new float[cols + 1];
  lanePositionsXBottom = new float[cols + 1];
  for (int i = 0; i <= cols; i++) {
    lanePositionsXTop[i] = map(i, 0, cols, (width - roadTopWidth) / 2, (width + roadTopWidth) / 2);
    lanePositionsXBottom[i] = map(i, 0, cols, (width - roadBottomWidth) / 2, (width + roadBottomWidth) / 2);
  }

  laneColors[0] = color(255, 0, 0);     // Rouge
  laneColors[1] = color(255, 127, 0);   // Orange
  laneColors[2] = color(255, 255, 0);   // Jaune
  laneColors[3] = color(0, 255, 0);     // Vert
  laneColors[4] = color(0, 0, 255);     // Bleu
  laneColors[5] = color(75, 0, 130);    // Indigo
  laneColors[6] = color(148, 0, 211);   // Violet
  laneColors[7] = color(255, 192, 203); // Rose

  levelBackgrounds[0] = loadImage("BGlvl1.jpg");
  levelBackgrounds[0].resize(width+10, height);
  levelBackgrounds[1] = loadImage("BGlvl2.jpg");
  levelBackgrounds[1].resize(width, height);
  ResultsIcon = loadImage("ResultatsIcon.png");
  ResultsIcon.resize(400, 150);

  lvls = new ArrayList<Lvl>();
  lvls.add(new Lvl(0, BPMs[0])); // Niveau 1 - Smoke on the Water (85 BPM)
  lvls.add(new Lvl(1, BPMs[1])); // Niveau 2 - Come As You Are (185 BPM)
}

void drawLvl() {
  Lvl lvl = lvls.get(selectedLvl);
  lvl.display();
}

void playMenuMusic() {
  if (!isMenuMusicPlaying) {
    if (currentLevelMusic != null) {
      currentLevelMusic.pause();
    }
    menuMusic.rewind();
    menuMusic.loop();
    isMenuMusicPlaying = true;
  }
}

void setup() {
  size(1200, 700);
  myPort = new Serial(this, "COM12", 9600);
  myPort.bufferUntil('\n');

  minim = new Minim(this);
  menuMusic = minim.loadFile("bgMusic.mp3");

  img = loadImage("menuBackground.png");
  img.resize(width, height);
  titleImg = loadImage("logo.png");
  jouer = loadImage("jouer.png");
  option = loadImage("option.png");
  quitter = loadImage("quitter.png");
  lvlSelectBackground = loadImage("menulvlSelect.png");
  customFont = createFont("Arial Black", 64);
  textFont(customFont);
  setupLvl();
  setupMenuLvl();
  myPort.write("N\n");
  particles = new ArrayList<Particle>();
  blurBuffer = createGraphics(width, height);
  playMenuMusic();
}

void draw() {
  background(0);
  if (!initialisationDone) {
    drawInitialisation();
  } else if (option1Active) {
    drawLvl();
  } else if (resultsScreenActive) {
    drawResultsScreen();
  } else if (menuLvlActive || menuOptionActive) {
    playMenuMusic();
    if (menuLvlActive) drawMenuLvl();
    else drawMenuOption();
  } else if (mainMenuActive) {
    playMenuMusic();
    drawMenu();
  }
}

void drawMenu() {
  // Fond et titre
  imageMode(CORNER);
  image(img, 0, 0);
  imageMode(CENTER);
  image(titleImg, width/2, 130, 350, 250);

  drawButton(width/2, 350, jouer, selectedOption == 0);
  drawButton(width/2, 450, option, selectedOption == 1);
  drawButton(width/2, 550, quitter, selectedOption == 2);
  String texts[] = {"Jouer", "Options", "Quitter", "Confirmer"};
  int indexC [] = {0, 1, 2, 3};
  drawControlsBackground();
  drawControls(texts, texts.length, indexC);
}

void drawButton(float x, float y, PImage label, boolean selected) {
  image(label, x, y);
  if (selected) {
    fill(255);
    ellipse(x-200, y, 20, 20);
  }
}

void drawControlsBackground() {
  rectMode(CORNER);
  fill(0, 150);
  noStroke();
  rect(0, height-60, width, 60);
  fill(255);
  textSize(16);
  textAlign(CENTER, CENTER);
}

void drawControls(String[] texts, int len, int[] indexC) {
  float y = height-30;
  float spacing = width/4;
  for (int i = 0; i < len; i ++) {
    drawControl(texts[i], spacing*( 0.5 +i), y, laneColors[indexC[i]]);
  }
}

void drawControl(String txt, float x, float y, color c) {
  text(txt, x, y);
  fill(c);
  rect(x + textWidth(txt)/2 + 15, y, 15, 15, 15);
  fill(255);
}

void drawMenuOption() {
  imageMode(CORNER);
  image(lvlSelectBackground, 0, 0);
  image((metroOn ? volumeON : volumeOFF), 200, 300);
  String texts[] = {"Activer", "Desactiver", "Quitter"};
  int indexC [] = {0, 1, 2};
  drawControlsBackground();
  drawControls(texts, texts.length, indexC);
}

void stop() {
  if (menuMusic != null) menuMusic.close();
  if (currentLevelMusic != null) currentLevelMusic.close();
  if (minim != null) minim.stop();
  super.stop();
}

int note = 0;
int squareSize = 50;
int squareSpacing = 60;


void handleArduinoInput() {
  if (!initialisationDone && arduinoInput == 0) {
      note ++;
      if (note == cols) {
        initialisationDone = true;
        mainMenuActive = true;
      }
    }
  

  if (resultsScreenActive) {
    if (arduinoInput == 3) {
      blurRadius = 0;
      particles.clear();
      resultsScreenActive = false;
      menuLvlActive = true;
      score = 0;
      lvls.set(selectedLvl, new Lvl(selectedLvl, BPMs[selectedLvl]));
    }
  }
  if (menuLvlActive) {

    switch(arduinoInput) {
    case 0:
      selectedLvl = 0;
      break;
    case 1:
      selectedLvl = 1;
      break;
    case 2:
      option1Active = true;
      menuLvlActive = false;
      break;
    case 4:
      menuLvlActive = false;
      mainMenuActive = true;
      break;
    }
  }

  if (menuOptionActive) {
    switch(arduinoInput) {
    case 0:
      metroOn = true;
      break;
    case 1:
      metroOn = false;
      break;
    case 2:
      menuOptionActive = false;
      mainMenuActive = true;
      break;
    }
  }
  if (mainMenuActive) {
    if (arduinoInput >= 0 && arduinoInput <= 2) {
      selectedOption = arduinoInput;
    } else if (arduinoInput == 3) {
      switch (selectedOption) {
      case 0:
        menuLvlActive = true;
        mainMenuActive = false;
        break;
      case 1:
        menuOptionActive = true;
        mainMenuActive = false;
        break;
      case 2:
        exit();
        break;
      }
    }
  }
}

void serialEvent(Serial port) {
  String data = port.readStringUntil('\n');
  if (data != null) {
    data = data.trim();
    try {
      arduinoInput = Integer.parseInt(data);
      handleArduinoInput();
      port.clear();
    }
    catch (NumberFormatException e) {
      // On ignore
    }
  }
}



void drawInitialisation() {
  imageMode(CORNER);
  image(img,0,0);
  fill(color(255),150);
  rect(width/2-250,height/2-200,500,100,50);
  fill(0);
  textSize(20);
  text("Veuillez initialiser votre instrument !",width/2-200,height/2-145);
  int totalWidth = 8 * squareSize + 7 * squareSpacing;
  int startX = (width - totalWidth) / 2;
  
  for (int i = 0; i < 8; i++) {
    if (i < note) {
      fill(laneColors[i]);
    } else {
      fill(color(255));
    }
    
    int x = startX + i * (squareSize + squareSpacing);
    int y = height/2 - squareSize/2;
    rect(x, y, squareSize, squareSize);
  }
}
