# --- front-matter:toml ---
model = "PMSM_NP_Boost.slx"
component = "PMSM_NP_Boost/Controller"
[inputs]
Vdc = "Vdc"
I1 = "I1"
I2 = "I2"
I3 = "I3"
[outputs]
PWM1 = "PWM1"
PWM2 = "PWM2"
PWM3 = "PWM3"
PWM4 = "PWM4"
PWM5 = "PWM5"
PWM6 = "PWM6"
# --- end front-matter ---

Feature: PMSM Neutral-Point Boost Controller Verification
  Verify controller behavior using baseline comparison.

Scenario: Over-voltage condition response
  Controller should respond to over-voltage by deactivating PWM outputs.
  Given inputs
    * Vdc = step(700 -> 900 @ 10ms)
    * I1 = const(10)
    * I2 = const(10)
    * I3 = const(10)
  When simulate for 50ms in Normal mode
  Then baseline "ov_protection.mat"

Scenario: Over-current condition response
  Controller should respond to over-current by deactivating PWM outputs.
  Given inputs
    * Vdc = const(700)
    * I1 = step(10 -> 250 @ 10ms)
    * I2 = const(10)
    * I3 = const(10)
  When simulate for 50ms in Normal mode
  Then baseline "oc_protection.mat"

Scenario: Normal regulation response
  Controller should produce active PWM when Vdc is below setpoint.
  Given inputs
    * Vdc = const(700)
    * I1 = const(10)
    * I2 = const(10)
    * I3 = const(10)
  When simulate for 50ms in Normal mode
  Then baseline "normal_regulation.mat"
