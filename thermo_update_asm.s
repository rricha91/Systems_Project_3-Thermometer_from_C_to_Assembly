### Begin with functions/executable code in the assmebly file via '.text' directive

.text
.global  set_temp_from_ports
        
## ENTRY POINT FOR REQUIRED FUNCTION
set_temp_from_ports:
   ## Parameters: temp_t temp
   ## rdi = temp_t temp

   ## assembly instructions here
# STEP 1: check if values are in range
   movw  THERMO_SENSOR_PORT(%rip), %dx    	    # register dx (Arg 3, 16-bit word) as THERMO_SENSOR_PORT
   cmpw  $28800, %dx                      	    # check if THERMO_SENSOR_PORT < 28800 (max temp) or < 0 (min temp), if so, goto .OUT_OF_BOUNDS
   ja    .OUT_OF_BOUNDS                          # note: the smallest the binary value for signed negative integer can become when converted to an unsigned integer is 268435456, which is > 28800

   movb  THERMO_STATUS_PORT(%rip), %cl          # register cl (Arg 4, 8-bit byte) as THERMO_STATUS_PORT
   movb  $4, %r8b                         	    # register r8b (Arg 5, 16-bit word) as 0b0000100 (4), converting r8b into a mask 
   andb  %cl, %r8b                              # set r8b = 0000 0100 & cl 			r8b becomes either 0000 0000 (non-error state) or 0000 0100 (error-state)
   cmpb  $4, %r8b                               # compare r8b with 0000 0100 and assign to r8b, if then r8b = 0000 0100, goto to .OUT_OF_BOUNDS
   je    .OUT_OF_BOUNDS

# STEP 2: Set rdi (temp_t temp) to nearest tenth of a degree C, and set mode to C
   movb    $1, 2(%rdi)                          # set temp->mode = 1 -> set mode to C
   shrw    $5, %dx                              # set dx = THERMO_STATUS_PORT >> 5 = THERMO_SENSOR_PORT / 32          
   movw    %dx, 0(%rdi)                         # set temp->tenths_degrees = dx
   subw    $450, 0(%rdi)                        # set temp->tenths_degrees -= 450

# STEP 3: Check if rounding is needed, and if so, then round rdi up by 1 
   movw    THERMO_SENSOR_PORT(%rip), %r8w       # register r8w (Arg 5, 8-bit byte) as THERMO_SENSOR_PORT                       
   shlw    $11, %r8w                            # set r8w = r8w << 11 -> r8w = (r8w % 32) * 32
   shrw    $11, %r8w                            # set r8w = r8w >> 11 -> r8w = r8w % 32
   cmpw    $15, %r8w                            # compare r8w with 15
   jle     .FAHRENHEIT_CHECK                    # if r8w <= 15, no rounding needed, jump to .FAHRENHEIT_CHECK
   incw    0(%rdi)                              # else increment temp->tenths_degrees, rounding it up by 1

# STEP 4: Check if the temp needs to be converted to fahrenheit, and convert it if it does
.FAHRENHEIT_CHECK:
    # convert to fahrenheit if needed
    movb    $32, %r8b                            # set r8b = 32 = 0000 0001                  mask for temperature mode, which is governed by the 5th bit.
    andb    THERMO_STATUS_PORT(%rip), %r8b      # r8b = 0010 0000 & THERMO_STATUS_PORT       apply mask
    cmpb    $32, %r8b                           # if r8b = 0010 0000, temp is F: goto .CONVERT_FAHRENHEIT
    je      .CONVERT_FAHRENHEIT    

# STEP 5: Return function.
.END_STFP_ONE:
    movl    $0, %eax                            # return 0; no errors
    ret                                         # return from the function

.OUT_OF_BOUNDS:                                  
    movw    $0, 0(%rdi)                         # set temp->tenths_degrees = 0; 
    movb    $3, 2(%rdi)                         # set temp->temp_mode = 3;      mode is "error"
    movl    $1, %eax                            # set return register = 1;      set_temp_from_ports failed or sensor read an invalid value
    ret  

.CONVERT_FAHRENHEIT:
    movw    0(%rdi), %r9w                       # register r9w as temp->tenths_degrees
    imulw   $9, %r9w                            # r9w = r9w * 9

    # division prep
    movq    $0, %rax                            # clear return register rax 
    movq    $0, %rdx                            # clear rdx (Arg 3, 64-bit register)
    movw    %r9w, %ax                           # set ax to short r9w
    cwtl                                        # "convert word to long" sign extend ax -> eax
    cltq                                        # "convert long to quad" sign extend eax -> rax
    cqto                                        # sign extend rax -> rdx
    movq    $5, %rcx                            # set rcx to long 5
    idivq   %rcx                                # integer divide combined rax/rdx register by rcx (5), rax->quotient, rdx->remainder

    addq    $320, %rax                          # rax += 320 = ((int)(THERMO_SENSOR_PORT * 9)/5) + 320 
    movw    %ax, 0(%rdi)                        # temp->tenths_degrees = rax
    movb    $2, 2(%rdi)                         # temp->mode = 2 -> set mode field to Fahrenheit
    jmp     .END_STFP_ONE                       # goto .END_STFP_ONE

### Change to definine semi-global variables used with the next function 
### via the '.data' directive
.data
num_array:                                      # num_array[]
    .int 0b1111011                              # [0] = '0'
    .int 0b1001000                              # [1] = '1'
    .int 0b0111101                              # [2] = '2'
    .int 0b1101101                              # [3] = '3'
    .int 0b1001110                              # [4] = '4'
    .int 0b1100111                              # [5] = '5'
    .int 0b1110111                              # [6] = '6'
    .int 0b1001001                              # [7] = '7'
    .int 0b1111111                              # [8] = '8'
    .int 0b1101111                              # [9] = '9'
blank:
    .int 0b0000000                              # ' ' - blank
negative: 
    .int 0b0000100                              # '-' - negative
display_error:
    .int 0b00000110111101111110111110000000     # "display error"

### Change back to defining functions/execurable instructions
.text
.global  set_display_from_temp

## ENTRY POINT FOR REQUIRED FUNCTION
set_display_from_temp:  
    ## Parameters: temp_t temp, int *display
    ## rdi = temp_t temp
    ## rsi = int *display

    ## assembly instructions here

# STEP 1: Determine if the display is to be FAHRENHEIT or CELSIUS and check for any ERRORS
    movl   $0, (%rsi)                           # clear display (fill /w 0s)
    movq   %rdi, %rcx                           # rcx = rdi                    move temp into rcx (Arg 4, 64-bit register)
    sarq   $16, %rcx                            # rcx >> 16                    cl = temp.temp_mode

    cmpb   $1, %cl                             
    je     .CELS                                # if temp.temp_mode = 1, goto .CELS to do setup for Fahrenheit    
    cmpb   $2, %cl                             
    je     .FAHR                                # if temp.temp_mode = 2, goto .FAHR to do setup for Fahrenheit
    # OTHERWISE, temp.temp_mode != 1 && temp.temp_mode != 2, so mode must indicate an error

    .ERR:                                       
    movl    display_error(%rip), %r11d          # set r11d (32-bit double-word) to error bit sequence
    movl    %r11d, (%rsi)                       # set display to "error"
    movl    $1, %eax                            # return 1;                    indicates error
    ret                                         # return from function

    .FAHR:
    cmpw    $1130, %di                          # compare temp.tenths_degrees with 1130
    jg      .ERR                              # if (temp.tenths_degrees > 1130), jump to .ERROR
    cmpw    $-490, %di                          # compare temp.tenths_degrees with -490
    jl      .ERR                              # if (temp.tenths_degrees < -490), jump to .ERROR
    movl    $0b10, (%rsi)                       # sets display bits to indicate FAHRENHEIT
    jmp     .PREP_CALC                          # goto to .PREP_CALC

    .CELS:
    # OTHERWISE, temp.temp_mode < 2, thus temp.temp_mode = 1, so do setup for Celsius
    cmpw    $450, %di                           # compare temp.tenths_degrees with 450
    jg      .ERR                              # if (temp.tenths_degrees < 450), goto to .ERROR
    cmpw    $-450, %di                          # compare temp.tenths_degrees with -450
    jl      .ERR                              # if (temp.tenths_degrees < -450), goto to .ERROR
    movl    $0b01, (%rsi)                       # sets display bits to indicate CELSIUS 

    .PREP_CALC:                          
    movw    %di, %cx                            # set cx (Arg 4, 16-bit word) = temp.tenths_degrees
    cmpw    $0, %cx                             # compare temp.tenths_degrees with 0
    jge     .BEGIN_CALC                         # if cx >= 0, skip to .BEGIN_CALC, otherwise change the sign first
    NEG     %cx                                 # cx = -cx,  (makes cx positive if initially negative. done for calculation reasons.)


# STEP 2: calculate digits for {tenths, ones, tens, hundreds} and store in registers {r11, r10, r9, r8}  
.BEGIN_CALC:                              
# division prep for hundreads
    movq    $0, %rax                            # clear return register rax              
    movq    $0, %rdx                            # clear Arg 3 register  rdx
    movw    %cx, %ax                            # set ax to short cx                  cx = (abs value of temp.tenths_degrees)
    cwtl                                        # "convert word to long" sign extend ax -> eax
    cltq                                        # "convert long to quad" sign extend eax -> rax
    cqto                                        # sign extend rax -> rdx
    movq    $10, %rcx                           # set rcx to divisor (10)
    idivq   %rcx                                # integer divide combined rax/rdx register by rcx (10), rax->quotient, rdx->remainder
    movq    %rdx, %r11                          # set 64 bit register r11 = rdx = tenths        
    movw    %ax, %cx                            # set cx = quotient

# division prep for tens
    movq    $0, %rax                            # clear return register rax              
    movq    $0, %rdx                            # clear Arg 3 register  rdx
    movw    %cx, %ax                            # set ax to short cx                  cx = (previous quotient)
    cwtl                                        # "convert word to long" sign extend ax -> eax
    cltq                                        # "convert long to quad" sign extend eax -> rax
    cqto                                        # sign extend rax -> rdx
    movq    $10, %rcx                           # set rcx to divisor (10)
    idivq   %rcx                                # integer divide combined rax/rdx register by rcx (10), rax->quotient, rdx->remainder
    movq    %rdx, %r10                          # set 64 bit register r10 = rdx = ones       
    movw    %ax, %cx                            # set cx = quotient

# division prep for ones
    movq    $0, %rax                            # clear return register rax              
    movq    $0, %rdx                            # clear Arg 3 register  rdx
    movw    %cx, %ax                            # set ax to short cx                  cx = (previous quotient)
    cwtl                                        # "convert word to long" sign extend ax -> eax
    cltq                                        # "convert long to quad" sign extend eax -> rax
    cqto                                        # sign extend rax -> rdx
    movq    $10, %rcx                           # set rcx to divisor (10)
    idivq   %rcx                                # integer divide combined rax/rdx register by rcx (10), rax->quotient, rdx->remainder
    movq    %rdx, %r9                           # set 64 bit register r9 = rdx = tens        
    movw    %ax, %cx                            # set cx = quotient

# division prep for tenths
    movq    $0, %rax                            # clear return register rax              
    movq    $0, %rdx                            # clear Arg 3 register  rdx
    movw    %cx, %ax                            # set ax to short cx                  cx = (previous quotient)
    cwtl                                        # "convert word to long" sign extend ax -> eax
    cltq                                        # "convert long to quad" sign extend eax -> rax
    cqto                                        # sign extend rax -> rdx
    movq    $10, %rcx                           # set rcx to divisor (10)
    idivq   %rcx                                # integer divide combined rax/rdx register by rcx (10), rax->quotient, rdx->remainder
    movq    %rdx, %r8                           # set 64 bit register r8 = rdx = hundreds        
    movw    %ax, %cx                            # set cx = quotient

# STEP 3: Set the display digits
    leaq    num_array(%rip), %rdx               # set rdx = pointer to beginning of num_array       
    movq    %r8, %rcx                           # set rcx = r8 (set rcx to the hundreds digit)
    cmpq    $0, %rcx                            # check if hundreds digit is 0
    jg      .SET_BITS_HUNDREDS                   # if hundreds > 0, move to set add the digit

    cmpq    $0, %r9                             # otherwise, check if (tens > 0)
    jg      .NEGATIVE_CHECK_HUNDREDS            # if so, move to .NEGATIVE_CHECK_HUNDREDS to check if temp.tenths is negative

    shll    $7, (%rsi)                          # else, int display << 7 (fills with zeros for a blank display)       

.SET_BITS_TENS:
    movq    %r9, %rcx                           # set rcx = r9 (sets rcs to the tens digit)
    cmpq    $0, %rcx                            # check if hundreds digit equals 0
    je      .ZERO_CHECK_TENS                    # if so, jump to .ZERO_CHECK_TENS
    
    movq    %r9, %rcx                           # set rcx = r9, move the tens digit into rcx
    movl    (%rdx,%rcx,4), %ecx                 # set ecx = num_array[r9]
    shll    $7, (%rsi)                          # int display << 7 (shift intgeger display to make room for the next digit)
    orl     %ecx, (%rsi)                        # copies the 7 bits of ecx into the display

.SET_BITS_ONES:                                 # ones digit will always be displayed, and will always be displayed as a digit, even if it's a zero
    movq    %r10, %rcx                          # set rcx = r10, move the ones digit into rcx
    movl    (%rdx,%rcx,4), %ecx                 # ecx = num_array[r10]
    shll    $7, (%rsi)                          # int display << 7 (shift intgeger display to make room for the next digit)
    orl     %ecx, (%rsi)                        # copies the 7 bits of ecx into the display

.SET_BITS_TENTHS:                           
    movq    %r11, %rcx                          # rcx = r11, move the tenths digit into rcx
    movl    (%rdx,%rcx,4), %ecx                 # ecx = num_array[r11]
    shll    $7, (%rsi)                          # int display << 7 shift intgeger display to make room for the last digit)
    orl     %ecx, (%rsi)                        # copies the 7 bits of ecx into the display  


.END_SDFT_ONE:
    movl    $0, %eax                            # return 0; indicates success
    ret                                         # eventually return from the function

.SET_BITS_HUNDREDS:
    shll    $7, (%rsi)                          # int display << 7 (makes room for new digit in integer display)
    movl    (%rdx,%rcx,4), %ecx                 # set ecx = num_array[r8]
    orl     %ecx, (%rsi)                        # copy the 7 bits of ecx into the intgeger display 

    jmp    .SET_BITS_TENS                        # hundreds bit set, jump to .SET_BITS_TENS

.NEGATIVE_CHECK_HUNDREDS:                         
    shll    $7, (%rsi)                          # int display << 7 (creates a new blank digit, and makes potential room for negative sign's bits)

    cmpw    $0, %di                             # compare temp.tenths with 0
    jge     .SET_BITS_TENS                       # if temp.tenths >= 0,  hundreds has now been set in all cases: jump to .SET_BITS_TENS

    movl    negative(%rip), %ecx                # set ecx = 0b0000100, the binary value for the negative sign display
    orl     %ecx, (%rsi)                        # copy the bits of the negative sign into the display int, so one is displayed in the hundreds place
    
    jmp     .SET_BITS_TENS                       # jump to .SET_BITS_TENS as hundreds bit is set, continue to set the tens place
 
.NEGATIVE_CHECK_TENS:
   # due to decimals, the ones digit will not be blank even if it is a zero
   # so even if the ones digit is zero, if the whole number is negative, then the tens must display as negative

    shll    $7, (%rsi)                          # int display << 7 (fills with zeros, making a blank display digit, and makes room for potential negative.)

    cmpw    $0, %di                             # compare 0 with temp.tenths_degrees
    jge     .SET_BITS_ONES                      # if >= zero, then tens must be blank: return to setting SET_BITS_ONES

    movl    negative(%rip), %ecx                # ecx = negative, moves negative int's bits into ecx
    orl     %ecx, (%rsi)                        # copies negative's bits into display int so a negative symbol is displayed in the tens place
    jmp     .SET_BITS_ONES                      # jump to .SET_BITS_ONES, tens place display digit set

.ZERO_CHECK_TENS:
    cmpq    $0, %r8                             # check if hundreds digit is zero
    je      .NEGATIVE_CHECK_TENS                # if so, jump to NEGATIVE_CHECK_TENS, as tens = 0 and hundreds = 0  

    # otherwise, hundreads > 0 and tens = 0
    shll    $7, (%rsi)                          # int display << 7 (creates room for next 7 bits)

    movl    (%rdx,%rcx,4), %ecx                 # set ecx = num_array[0] = 0
    orl     %ecx, (%rsi)                        # copy the bits to display '0' into the new 7 bits of the integer display
    jmp     .SET_BITS_ONES                      # tens bits are set: jump to .SET_BITS_ONES




.text
.global thermo_update
        
## ENTRY POINT FOR REQUIRED FUNCTION
thermo_update:
    pushq   %r15                                # push r15
    subq    $24, %rsp                           # expand stack by 24 bits 
    movl    $0, 4(%rsp)                         # add 32 bits of 0 to stack pointer starting at byte 4
    leaq    4(%rsp), %rdi                       # set rdi (arg 1) to point 4 bytes above rsp   
    
    call    set_temp_from_ports                 # call function ser_temp_from_ports, store return value in eax
    cmpl    $1, %eax                            # check if function return is 1, 
    je      .UPDATE_FAIL                        # if so then jump to .FAIL
    movl    %eax, %r15d                         # else, set r15d to the value in eax, preserving the result
  
    movl    $0, (%rsp)                          # add 4 bytes(32 bits) of 0 to stack pointer starting at byte 0
    movq    %rsp, %rsi                          # set rsi (arg 1) = temp_t
    movl    4(%rsp), %edi                       # set edi (arg 2) = display int   
    
    call    set_display_from_temp               # call function set_display_from_temps, store return value in eax
    cmpl    $1, %eax                            # check if function return is 1, 
    je      .UPDATE_FAIL                        # if so then jump to .UPDATE_FAIL    
        
    movl    (%rsp), %ecx                        # set ecx = stack pointer (32 bits 8 bytes))   
    movl    %ecx, THERMO_DISPLAY_PORT(%rip)     # set DISPLAY_PORT = ecx

    addq    $24, %rsp                           # shrink stack back down
    movl    $0, %eax                            # set return register = 0 (indicates success)
    popq    %r15                                # pop r15
    ret                                         # return 0; success

.UPDATE_FAIL:                                          
    movl    $116912000, THERMO_DISPLAY_PORT(%rip)  # move error bits into DISPLAY_PORT
    addq    $24, %rsp                              # shrink stack back down
    movl    $1, %eax                               # set return register = 1 (indicates failure)
    popq    %r15                                   # pop r15
    ret                                            # return  