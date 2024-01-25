
# Copyright (C) 2021 Alexander Junk <dev@junk.technology>
 
# This program is free software: you can redistribute it and/or modify it 
# under the terms of the GNU Lesser General Public License as published 
# by the Free Software Foundation, either version 3 of the License, or 
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; 
# without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. 
# See the GNU Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public License 
# along with this program. If not, see <https://www.gnu.org/licenses/>. 

import string
import gpio
import webserver

class FIELD
    var start_idx
    var end_idx
    var len
    var bite
    var value
    
    def init(start_idx, len, bite)
      self.start_idx = start_idx
      self.end_idx = start_idx + len - 1
      self.len = len
      self.bite = (bite == nil) ? 0 : bite
    end
end
    
class REGISTER
    var idx
    var fields
    var len
    var value
    var readable
    var writeable
    
    def init(idx, len, rw, fields)
        self.idx = idx
        self.fields = fields
        self.len = len
        self.readable = bool(string.count(rw, 'r'))
        self.writeable = bool(string.count(rw, 'w'))
    end
    
    def item(sub)
      return self.fields[sub]
    end
    
    def parse(val)
      if val == nil return false end
      self.value = val
      for f : self.fields
        f.value = val >> (f.start_idx + 8 * (self.len - f.bite - 1 ))
        f.value &= 0xFF
      end
      return true
    end
end
  
var registers = {

        "CONTROL" : REGISTER(0x00, 2, "rw",
            {
            "ON_FAULT_MASK"     : FIELD(7, 1),
            "ON_DELAY"          : FIELD(6, 1),
            "ON/ENB"            : FIELD(5, 1),
            "MASS_WRITE_ENABLE" : FIELD(4, 1),
            "FET_ON"            : FIELD(3, 1),
            "OC_AUTORETRY"      : FIELD(2, 1),
            "UV_AUTORETRY"      : FIELD(1, 1),
            "OV_AUTORETRY"      : FIELD(0, 1),

            "FB_MODE"  : FIELD(6, 2, 1),
            "UV_MODE"  : FIELD(4, 2, 1),
            "OV_MODE"  : FIELD(2, 2, 1),
            "VIN_MODE" : FIELD(0, 2, 1)
            }
        ),


        "STATUS" : REGISTER(0x1E, 2,  "r",
            {"ON_STATUS"                : FIELD(7, 1),
            "FET_BAD_COOLDOWN_STATUS"   : FIELD(6, 1),
            "FET_SHORT_PRESENT"         : FIELD(5, 1),
            "ON_PIN_STATUS"             : FIELD(4, 1),
            "POWER_GOOD_STATUS"         : FIELD(3, 1),
            "OC_COOLDOWN_STATUS"        : FIELD(2, 1),
            "UV_STATUS"                 : FIELD(1, 1),
            "OV_STATUS"                 : FIELD(0, 1),

            "GPIO3_STATUS"              : FIELD(7, 1, 1),
            "GPIO2_STATUS"              : FIELD(6, 1, 1),
            "GPIO1_STATUS"              : FIELD(5, 1, 1),
            "!ALERT_STATUS"             : FIELD(4, 1, 1),
            "EEPROM_BUSY"               : FIELD(3, 1, 1),
            "ADC_IDLE"                  : FIELD(2, 1, 1),
            "TICKER_OVERFLOW_PRESENT"   : FIELD(1, 1, 1),
            "METER_OVERFLOW_PRESENT"    : FIELD(0, 1, 1)
            }
        ),

        "ILIM_ADJUST" : REGISTER(0x11, 1,  "rw",
            {"ILIM_ADJUST"  : FIELD(5, 3),
            "FOLDBACK_MODE" : FIELD(3, 2),
            "VSOURCE/VDD"   : FIELD(2, 1),
            "GPIO_MODE"     : FIELD(1, 1),
            "16_BIT"        : FIELD(0, 1),
            }
        ),
        
        "POWER" : REGISTER(0x46, 2, "r",
            {"POWER_MSB" : FIELD(0, 8, 0),
             "POWER_LSB" : FIELD(0, 8, 1)
            }
        ),
        
        "VSENSE" : REGISTER(0x40, 2, "r",
            {"VSENSE_MSB" : FIELD(0, 8, 0),
             "VSENSE_LSB" : FIELD(0, 8, 1)
            }
        ),
        
        "VSOURCE" : REGISTER(0x3A, 2, "r",
            {"VSOURCE_MSB" : FIELD(0, 8, 0),
             "VSOURCE_LSB" : FIELD(0, 8, 1)
            }
        )
        
}

        


class LTC4281 : Driver
  var addr
  var wire

  var reg
  
  var status
  
  var adc_step
  var adc_step_sense_current
  var adc_step_sense_power

  var pin_bat_ok_out, pin_bat_ok_in

  var bat_ok_in, bat_ok_out

  var power, current, voltage

  def init(registers, pin_bat_ok_in, pin_bat_ok_out)
    self.addr = 74
    self.wire = tasmota.wire_scan(self.addr)
    self.adc_step = 33.28 / 65535
    self.adc_step_sense_current = 0.04 / (65535 * 0.001)
    self.adc_step_sense_power = 65536 * 33.28 / 65535 * 0.04 / (65535 * 0.001) 

    self.reg = registers

    self.pin_bat_ok_out = pin_bat_ok_out
    self.pin_bat_ok_in  = pin_bat_ok_in

    self.bat_ok_out = 1

    print("Init complete")

    tasmota.add_cmd('BAT_PWR', / args -> self.cmd_bat_pwr(args))
    tasmota.add_cmd('BAT_VOLTAGE', / args -> self.cmd_bat_voltage(args))
    tasmota.add_cmd('BAT_CURRENT', / args -> self.cmd_bat_current(args))
    tasmota.add_cmd('BAT_SWITCH', / args -> self.cmd_bat_switch(args))
    tasmota.add_cmd('BAT_OK', / args -> self.cmd_bat_ok(args))

  end

  def read_register(reg)
    if !reg.readable return false end
    return self.wire.read(self.addr, reg.idx, reg.len)
  end

  def write_register(reg, value)
    if !reg.writeable return false end
    return self.wire.write(self.addr, reg.idx, value, reg.len)
  end

  def write_register_field(reg, field, value)
    if !reg.writeable return false end
    var current = self.read_register(reg)
    current &= ~( (0xFF >> (8 - field.len)) << (field.start_idx + 8 * (reg.len - field.bite - 1 )) )
    current |= ~( value << (field.start_idx + 8 * (reg.len - field.bite - 1 )) )
    return self.write_register(reg, current)
  end
  
  def update()
    for r : registers
        if r.readable
            r.parse(self.read_register(r))
        end
    end

    self.power   = registers["POWER"].value * self.adc_step_sense_power
    self.current = registers["VSENSE"].value * self.adc_step_sense_current
    self.voltage = registers["VSOURCE"].value * self.adc_step
    
    self.bat_ok_in = 1 ^ gpio.digital_read(self.pin_bat_ok_in)

    if self.voltage < 12.5
        self.bat_ok_out = 0
    end
    gpio.digital_write(self.pin_bat_ok_out, self.bat_ok_out)
  end

  def every_250ms()
    if !self.wire return nil end  #- exit if not initialized -#
    self.update()
  end

  # ------
  # Here starts (web) interface stuff

  def web_sensor()
    if !self.wire return nil end  #- exit if not initialized -#
    var msg = string.format(
            "{s}BAT_OK{m}%u {e}" ..
            "{s}Power{m}%f W{e}" ..
            "{s}Current{m}%f A{e}" ..
            "{s}Battery Voltage{m}%f V{e}",
            self.bat_ok_in,
            self.power,
            self.current,
            self.voltage
            )
    tasmota.web_send_decimal(msg)

    if webserver.has_arg("m_toggle_off")
        self.bat_ok_out = 0
    end

    if webserver.has_arg("m_toggle_on")
        self.bat_ok_out = 1
    end
    
  end

  def web_add_main_button()
    webserver.content_send("<p></p><button onclick='la(\"&m_toggle_on=1\");'>ON</button>")
    webserver.content_send("<p></p><button onclick='la(\"&m_toggle_off=1\");'>OFF</button>")
  end
  
  def cmd_bat_pwr()
    tasmota.resp_cmnd_str(string.format('%f', self.power))
  end

  def cmd_bat_voltage()
    tasmota.resp_cmnd_str(string.format('%f', self.voltage))
  end

  def cmd_bat_current()
    tasmota.resp_cmnd_str(string.format('%f', self.current))
  end

  def cmd_bat_switch()
    tasmota.resp_cmnd_str(string.format('%u', self.bat_ok_out))
  end

  def cmd_bat_ok()
    tasmota.resp_cmnd_str(string.format('%u', self.bat_ok_in))
  end
      
end

ltc4281 = LTC4281(registers, 8, 9)
ltc4281.update()
tasmota.add_driver(ltc4281)
