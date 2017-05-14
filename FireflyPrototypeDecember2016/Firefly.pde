/**
 * Firefly
 *
 * (c) 2012 Sofian Audry -- info(@)sofianaudry(.)com
 *
 * This agent has a single input and a single "flash" action. It mimicks
 * synchronizing fireflies. Based on the paper:
 * Tyrrell & Auer (2006) "Fireflies as Role Models for Synchronization in Ad Hoc Networks"
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public static enum FireflyState {
  IDLE,
  BLIND,
  FLASH,
  REFRACT
}

class Firefly {

  final float MOVING_AVERAGE_FACTOR = 0.001f;

  /// Threshold over which the agent flashes.
  float flashPeriod;

  /// Time which the agent is refractory ie. blind right after flashing (in seconds).
  float refractoryTime;

  /// Time for which the agent is blind after seeing a flash (usually equal to the
  /// flashTime of its neighbors).
  float blindTime;

  /// Time the "flash" stays on.
  float flashTime;

  /// Adjustment to power when a neighbor flashes as a proportion of flashPeriod (should be in [0,1]).
  float flashAdjust;

  /// Adjustment multiplier for heartbeat.
  float heartBeatAdjustFactor;

  // Internal use.

  // Current state.
  FireflyState state;
  
  // Overrides everything and sync with heart.
  boolean syncWithHeart;
  int syncWithHeartEvery;
  int syncWithHeartCounter;

  // Multi-purpose timer.
  Chrono stateTimer;
  long stateTime;

  // Main timer.
  Chrono mainTimer;

  // Mean counter.
  float mean;

  float action;

  // Particle for the firing.
  Particle fireParticle;

  Firefly(float flashPeriod, PVector origin)
  {
    this(flashPeriod, FLASH_ADJUST, 0.01, 0.01, 0.01, HEART_BEAT_ADUST_FACTOR, origin);
  }

  Firefly(float flashPeriod, float flashAdjust, float heartBeatAdjustFactor, PVector origin)
  {
    this(flashPeriod, flashAdjust, 0.01, 0.01, 0.01, heartBeatAdjustFactor, origin);
  }

  Firefly(float flashPeriod,
          float flashAdjust,
          float refractoryTime,
          float blindTime,
          float flashTime,
          float heartBeatAdjustFactor, PVector origin)
  {
    this.flashPeriod    = flashPeriod;
    this.flashAdjust    = flashAdjust;
    this.refractoryTime = refractoryTime;
    this.blindTime      = blindTime;
    this.flashTime      = flashTime;
    this.heartBeatAdjustFactor = heartBeatAdjustFactor;

    mainTimer  = new Chrono(false);
    stateTimer = new Chrono(false);

    fireParticle = new Particle(origin);

    state = FireflyState.IDLE;
    
    syncWithHeart = false;
    syncWithHeartEvery = 1;
  }

  void pulseAway() {
    fireParticle.particleResponse(action);
  }

  Particle getFireParticle() {
    return fireParticle;
  }

  void displayParticle(Environment env) {
    fireParticle.run(this, env);
  }
  
  void syncWithHeart(int every) {
    syncWithHeart = true;
    syncWithHeartEvery = every;
    syncWithHeartCounter = every-1; // next call to step() will trigger action
    println("sync with heart : " + every);
  }
  
  void unsyncWithHeart() {
    syncWithHeart = false;
  }

  void init() {
    mainTimer.stop();
    stateTimer.stop();
  }

  // Returns the value of last action taken by the agent (after step()).
  float getAction() {
    return action;
  }

  void setPeriod(float period) {
    this.flashPeriod = period;
  }

  void setPhase(float phase) {
    mainTimer.restart(round(phase * flashPeriod * 1000));
  }

  /// De-synchronize by changing to random phase.
  void dePhase() {
    // Offset the period so as to desynchronize the agents.
    setPhase(random(1));
  }

  void setFlashAdjust(float flashAdjust) {
    this.flashAdjust = flashAdjust;
  }

  void setHeartBeatAdjustFactor(float heartBeatAdjustFactor) {
    this.heartBeatAdjustFactor = heartBeatAdjustFactor;
  }

  /// Returns incoming "light" for this agent. For now it will be 0 if no agents have flashed and 1 otherwise.
  float getIncoming(Environment env) {
    float incoming = 0;

    ArrayList<Firefly> agents = env.getFireflies();
    for (Firefly agent : agents) {
      // If agent has flashed.
      if (agent != this && agent.getAction() > 0)
        incoming = 1;
    }

    return incoming;
  }

  /// Start the firefly.
  float start(Environment env) {
    // Select random phase.
    dePhase();

    // Init
    _changeState(FireflyState.IDLE, 0);
    mean = 0.5f;
    action = 0;

    // Perform one step.
    return step(env);
  }

  /// Perform one step and returns the action of the agent in [0..1].
  float step(Environment env) {
    if (syncWithHeart) {
      action = 0;
      boolean heartBeat = (env.getBeat() > 0);
      if (heartBeat) {
        syncWithHeartCounter++;
        println("counter: " + syncWithHeartCounter);
        if (syncWithHeartCounter >= syncWithHeartEvery) {
          syncWithHeartCounter = 0;
          action = 1;
          println("beat!");
        }
      }
    }
    
    else {
      // Turn off (default).
      action = 0;
  
      // Incoming signal.
      float incoming = getIncoming(env);
  
      // Update statistics.
      mean -= MOVING_AVERAGE_FACTOR * (mean - incoming);
  
      //// Natural increase in power.
      //if (state != FireflyState.FLASH)
      //  power++;
  
      // State machine.
      switch (state) {
      case IDLE: {
          float adjust = 0;
          if (env.getBeat() > 0)
            adjust = heartBeatAdjustFactor;
          if (incoming > mean)
            adjust += flashAdjust;
            
          // Check for incoming flashes.
          if (adjust > 0) {
//            float adjust = flashAdjust * (heartBeat ? heartBeatAdjustFactor : 1);
            mainTimer.add(round(flashPeriod * adjust * 1000));
            state = FireflyState.BLIND;
            stateTime = round(blindTime * 1000);
            stateTimer.restart();
          }
          _checkFlash();
        }
        break;
  
      case BLIND:
      case REFRACT:
        // This section will apply to both uninterrupted blind
        if (!_checkFlash()) { // If we must flash, do it and exit.
          // When timer is out, transit to IDLE.
          if (_timeOut()) state = FireflyState.IDLE;
        }
        break;
  
      case FLASH:
        // Flash baby!
        _stepFlash();
        break;
      default:;
      }
    }
    
    return action;
  }

  boolean _timeOut() {
    return stateTimer.hasPassed(stateTime);
  }

  boolean _checkFlash() {
    // Check if we need to flash.
    if (mainTimer.hasPassed(round(flashPeriod*1000))) {
      mainTimer.restart();
      _changeState(FireflyState.FLASH, flashTime);
      _stepFlash();
      return true;
    }
    return false;
  }

  void _stepFlash() {
    action = 1;

    // Stop flashing.
    if (_timeOut()) {
      mainTimer.restart();
      _changeState(FireflyState.REFRACT, refractoryTime); // refractory period
    }
  }

  void _changeState(FireflyState newState, float newTime) {
    state = newState;
    stateTime = round(newTime * 1000);
    stateTimer.restart();
  }
};