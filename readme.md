MacLight
--------------

Ready for your use, but very much undocumented.

#### PROBLEMS:
There is an issue with screen capturing in Lion. See issue #1. It is fixable, but I haven't personally had the time yet.

#### TODO:
* Allow user to select a serial port. Currently default to first arduino found
* Allow user to calibrate the output level of each channel. The red LEDs in my setup are slightly too bright, so all red values are multiplied by 0.9 at the moment.
* Refactor things out of app delegate where possible
* Retain user settings