
#include "thermo.h"
#include <stdbool.h>

// Uses the two global variables (ports) THERMO_SENSOR_PORT and
// THERMO_STATUS_PORT to set the fields of `temp`. If
// THERMO_SENSOR_PORT is negative or above its maximum trusted value
// (associated with +45.0 deg C), this function sets the
// tenths_degrees to 0 and the temp_mode to 3 for `temp` before
// returning 1.  Otherwise, converts the sensor value to deg C using
// shift operations.  Further converts to deg F if indicated from
// THERMO_STATUS_PORT. Sets the fields of `temp` to appropriate
// values. `temp_mode` is 1 for Celsius, and 2 for Fahrenheit. Returns
// 0 on success. This function DOES NOT modify any global variables
// but may access them.
//
// CONSTRAINTS: Uses only integer operations. No floating point
// operations are used as the target machine does not have a FPU. Does
// not use any math functions such as abs().

int set_temp_from_ports(temp_t *temp){
   // Check if the sensor is negative, out of range, or if the port indicates an error.
   // If so, set the mode to error (3), degrees to 0, and return 1.
   if((THERMO_SENSOR_PORT < 0 
     || THERMO_SENSOR_PORT > 28800) 
     || ((THERMO_STATUS_PORT & (1 << 2)) >> 2)) { 
        temp->tenths_degrees = 0; 
        temp->temp_mode = 3; 
        return 1;
    }

   // Set the temp field to the tenth degree celsius, 
   // minus 450 for the -450 degree C starting point.
   temp->tenths_degrees = (THERMO_SENSOR_PORT >> 5) - 450;

   // If, after "dividing" the sensor port by 32, the remainder is large enough
   // to round (greater than or equal to 16 bits), round the result up by 1. 
   if (THERMO_SENSOR_PORT % 32 >= 16) temp->tenths_degrees += 1;

   // Checks if status of the thermometer is Fahrenheit.
   // If so, temp_mode is set to fahrenheite and the temperature is converted
   // from celcius to fahrenheit.
   if((THERMO_STATUS_PORT & (1 << 5)) >> 5){ // reads 5th bit of status port
        temp->temp_mode = 2;
        temp->tenths_degrees = ((temp->tenths_degrees * 9)/5) + 320; 
    }
   else temp->temp_mode = 1; // Leave mode in Celcius 
        
   return 0; 
}
//meow


// Alters the bits of integer pointed to by display to reflect the
// temperature in struct arg temp.  If temp has a temperature value
// that is below minimum or above maximum temperature allowable or if
// the temp_mode is not Celsius or Fahrenheit, sets the display to
// read "ERR" and returns 1. Otherwise, calculates each digit of the
// temperature and changes bits at display to show the temperature
// according to the pattern for each digit.  This function DOES NOT
// modify any global variables except if `display` points at one.
// 
// CONSTRAINTS: Uses only integer operations. No floating point
// operations are used as the target machine does not have a FPU. Does
// not use any math functions such as abs().
int set_display_from_temp(temp_t temp, int *display){
    // Sets up display.
    *display <<= 31;

   // Checks for any kind of error. If mode indicates error, or an invalid temperature is used,
   // or an invalid mode is used, the 32-bit desplay is set to 'error' and the function returns 1.
    if(temp.temp_mode == 3 
   || (temp.temp_mode == 1 && (temp.tenths_degrees < -450 || temp.tenths_degrees > 450)) 
   || (temp.temp_mode != 1 && temp.temp_mode != 2) 
   || (temp.temp_mode == 2 && (temp.tenths_degrees < -490 || temp.tenths_degrees > 1130))){ 
        *display = (0b00000110111101111110111110000000); 
        return 1;
    }

    // Set up bit displays. 
    int num_arr[10] = {0b1111011, 0b1001000, 0b0111101, 0b1101101, 0b1001110, 0b1100111, 0b1110111, 0b1001001, 0b1111111, 0b1101111};
    int blank = 0b0000000;
    int negative = 0b0000100;

    
    // Create a clone of the temperature in degrees to use to calculate the value at each place.
    // If temp is negative, calculate with the positive version
    int mod_temp = temp.tenths_degrees;
    if(mod_temp < 0) mod_temp = -mod_temp; 

    // Get the tenths value. 
    // Subtract tenths off for next place
    // Gets the ones value.
    // Subtract ones off for next place
    // Gets the tens value.
    // Subtracts tens off for next place.
    // Get the hundreds value.
    int temp_tenths = mod_temp % 10; 
    mod_temp -= temp_tenths; 
    int temp_ones = (mod_temp % 100) / 10; 
    mod_temp -= temp_ones * 10; 
    int temp_tens = (mod_temp % 1000) / 100; 
    mod_temp -= temp_tens * 100; 
    int temp_hundreds = (mod_temp % 10000) / 1000;


    // If degrees is found in the hundreds, print its place number.
    // If there's no hundreds place, check if negative. If negative, print the negative symbol.
    // Otherwise, print blank.
    if(temp_hundreds > 0 || temp_hundreds == 1) *display = (*display << 7 | (num_arr[temp_hundreds])); 
    else if(temp.tenths_degrees < 0 && temp_tens != 0) *display  = (*display << 7 | negative); 
    else *display = (*display << 7 & blank); 


    // If the tens place is 0 and the hundreds place is greater than 0, shift display over 7 and set
    // 7 least significant bits to display 0.
    // If the number is negative and starts in the ones place, shift the display over 7 and add a
    // negative sign.
    // If the number is negative and there's a zero in the ones place, shift the display over 7 and 
    // set all preceding displays to blank.
    // If the number is positive and there's a number in the tens place, shift display over 7 and
    // set the least significant bits to display its number.
    if(temp_tens == 0 && temp_hundreds > 0) *display = (*display << 7 | num_arr[0]);
    else if(temp.tenths_degrees < 0 && temp_tens == 0 && temp_hundreds == 0 && temp_ones != 0) 
        *display = (*display << 7 | negative);
    else if(temp_tens == 0 && temp_hundreds == 0 && temp_ones == 0)
        *display = (*display << 7 & blank); 
    else if(temp_tens > 0)
        *display = (*display << 7 | num_arr[temp_tens]); 

   
    // If one's place is a number, shift the display over 7 bits and set the least significant bits to
    // display that number.
    // If there is no one's place number, but there is a tenths number, shift the display over 7 bits 
    // and set the least significant bits to the display for the negative sign.
    // If all the digits would be blank (all zero), shift the display over 7 bits and set all to blank.
    // If there is a number in the hundreds spot, or in the tens spot, shift the display
    // over by 7 bits and set the least significant bits to display zero in the ones spot.
    if(temp_ones > 0) *display = (*display << 7 | num_arr[temp_ones]); 
    else if(temp_ones == 0 && temp_tenths != 0 && temp_hundreds == 0 && temp_tens == 0)
        *display = (*display << 7 | negative);
    else if(temp_ones == 0 && temp_tenths == 0 && temp_tens == 0 && temp_hundreds == 0)
        *display = (*display << 7 & blank);
    else if(temp_tens == 0 && temp_hundreds > 0)
        *display = (*display << 7 | num_arr[0]);
    else if(temp_ones == 0 && (temp_hundreds > 0 || temp_tens > 0))
        *display = (*display << 7 | num_arr[0]);

    // If the tenths place has a digit, shift the display over 7 bits and set the least significant bits to display that number.
    if(temp_tenths >= 0) *display = (*display << 7 | num_arr[temp_tenths]);

    // If the display is in celcius, set the 28th bit to be 1.
    // Else, if fahrenheit, set the 29th bit to be 1.
    if(temp.temp_mode == 1) *display = (*display | (1 << 28));
    if(temp.temp_mode == 2) *display = (*display | (1 << 29));
    return 0;
}


int thermo_update(){
    // Creates and initializes a new temp object using the port temperature and temperature setting.
    temp_t temp = {};
    int set_return = set_temp_from_ports(&temp);

    // Initializes an integer to represent the display, and a boolean to indicate if there's been an error 
    // while still ensuring the display is updated.
    int display = 0;
    bool failed = false;

    // If set_temp_from_ports returned anything other than 0, then there has been an error.
    // The display is set to display an error, and 'failed' is set to true.
    // The function does not return yet, to ensure the display updates.
    if(set_return != 0){ 
        THERMO_DISPLAY_PORT = 0b00000110111101111110111110000000; 
        failed = true; 
    }

    // Set the display using the new temp object, and save the int returned by the set_display function
    set_return = set_display_from_temp(temp, &display);

    // If set_display_from_temp returned anything other than 0, then there has been an error.
    // The display is set to display an error, and 'failed' is set to true.
    // The function does not return yet, to ensure the display updates.
    if(set_return != 0){
        THERMO_DISPLAY_PORT = 0b00000110111101111110111110000000;
        failed = true; 
    }

    // If either part of the update procedure failed, return 1.
    // Otherwise THERMO_DISPLAY_PORT is set to display and the function returns 0.
    if(failed == true){ 
        return 1;
    }
    else{ 
        THERMO_DISPLAY_PORT = display;
        return 0;
    }
    
}

