# BProtect

This repository contains the design files and firmware for the BProtect battery management board.

## Overview
The battery management system consists of a LTC4281 Hot-Swap controller handling the power path control as well as a Espressif ESP32 running the interfacing firmware. 

The design was created in KiCad and can be found in the [board](/board) folder.
Some notes about design considerations, component selection and sizing are contained in the schematic.

The ESP32 runs the awesome [Tasmota](https://tasmota.github.io/docs/) firmware and has a custom driver for the LTC4281 written in [Berry](https://berry-lang.github.io/). It can be found in the [app](/app) folder.


## Usage
Assemble the board as per schematics and flash Tasmota (version >=13).
Drop the Berry-script named [ltc4281.be](/app/ltc4281.be) from the [app](/app) folder into the filesystem and add it to the 'autoexec.be' as per the example.

## License
This project is licensed under the GPLv3.

